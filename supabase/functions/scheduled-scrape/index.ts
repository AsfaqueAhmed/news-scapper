// Server-side version of the app's scrape-refresh cycle (NewsRepositoryImpl.refresh
// in the Flutter client): fetch every enabled source's feed, dedupe, upsert into
// `articles`, run AI enrichment, prune anything older than 14 days. Meant to be
// invoked on a schedule via pg_cron + pg_net (see the migration that sets that up),
// but can also be called directly for a manual test run.
//
// Superseded by fetch-batch (round-robin batching + fetch_log observability +
// HTML-scraper fallback); kept only for reference, not called by any pg_cron job.
import { createClient } from "npm:@supabase/supabase-js@2";
import { XMLParser } from "npm:fast-xml-parser@4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY");

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const OPENROUTER_MODEL = "openai/gpt-4o-mini";
const PRUNE_AFTER_DAYS = 14;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Source {
  id: string;
  name: string;
  feed_url: string;
}

interface ArticleRow {
  id: string;
  title: string;
  link: string;
  description: string | null;
  image_url: string | null;
  pub_date: string;
  source_id: string;
  source_name: string;
  is_read: boolean;
}

function asArray<T>(v: T | T[] | undefined | null): T[] {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

function stripHtml(html?: string | null): string | null {
  if (html === undefined || html === null) return null;
  const text = String(html)
    .replace(/<[^>]*>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
  return text.length === 0 ? null : text;
}

function extractImageFromHtml(html?: string | null): string | null {
  if (!html) return null;
  const match = String(html).match(/<img[^>]+src=["']([^"']+)["']/i);
  return match ? match[1] : null;
}

function parseDate(raw?: string | null): string {
  if (raw) {
    const d = new Date(raw);
    if (!isNaN(d.getTime())) return d.toISOString();
  }
  return new Date().toISOString();
}

async function articleId(link: string, sourceId: string, title: string): Promise<string> {
  const basis = link.length > 0 ? link : `${sourceId}|${title}`;
  const data = new TextEncoder().encode(basis);
  const hash = await crypto.subtle.digest("SHA-1", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const xmlParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  isArray: (name) => name === "item" || name === "entry" || name === "link",
});

async function parseFeed(xml: string, source: Source): Promise<ArticleRow[]> {
  const doc = xmlParser.parse(xml);

  if (doc.rss?.channel) {
    const items = asArray(doc.rss.channel.item);
    const rows: ArticleRow[] = [];
    for (const item of items) {
      const link = typeof item.link === "string" ? item.link : (asArray(item.link)[0] ?? "");
      const title = stripHtml(item.title) ?? "(untitled)";
      if (!link) continue;
      const description = stripHtml(item.description);
      const imageUrl =
        item.enclosure?.["@_url"] ??
        item["media:content"]?.["@_url"] ??
        item["media:thumbnail"]?.["@_url"] ??
        extractImageFromHtml(item.description) ??
        null;
      rows.push({
        id: await articleId(link, source.id, title),
        title,
        link,
        description,
        image_url: imageUrl,
        pub_date: parseDate(item.pubDate),
        source_id: source.id,
        source_name: source.name,
        is_read: false,
      });
    }
    return rows;
  }

  if (doc.feed?.entry) {
    const items = asArray(doc.feed.entry);
    const rows: ArticleRow[] = [];
    for (const item of items) {
      const links = asArray(item.link);
      const link = links[0]?.["@_href"] ?? "";
      const title = stripHtml(item.title) ?? "(untitled)";
      if (!link) continue;
      rows.push({
        id: await articleId(link, source.id, title),
        title,
        link,
        description: stripHtml(item.summary ?? item.content),
        image_url: null,
        pub_date: parseDate(item.updated ?? item.published),
        source_id: source.id,
        source_name: source.name,
        is_read: false,
      });
    }
    return rows;
  }

  throw new Error("Unrecognized feed format (not RSS or Atom)");
}

async function fetchSource(source: Source): Promise<ArticleRow[]> {
  const response = await fetch(source.feed_url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (compatible; NewsScrapperBot/1.0)",
      "Accept": "application/rss+xml, application/xml, text/xml, */*",
    },
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  const body = await response.text();
  return parseFeed(body, source);
}

async function enrichArticles(
  articles: ArticleRow[],
  runId: string,
): Promise<Array<{ articleId: string; category: string | null; groupId: string | null }>> {
  if (!OPENROUTER_API_KEY || articles.length === 0) return [];

  const indexed = articles.map((a, i) => ({
    index: i,
    title: a.title,
    source: a.source_name,
    description: a.description ?? "",
  }));

  const prompt = `You are given a JSON array of news articles freshly scraped from multiple
RSS sources. For each article, decide:
1. "category": a short topic label (e.g. "Politics", "Technology", "Sports",
   "Business", "Health", "Science", "Entertainment", "World", "Other").
2. "group": an integer group key shared by every article that reports on
   the SAME real-world news story, even if wording differs across sources.
   Articles that are the only coverage of their story get a group key that
   no other article shares (e.g. their own index).

Articles:
${JSON.stringify(indexed)}

Respond with ONLY a JSON array, no prose, in this exact shape:
[{"index": 0, "category": "Technology", "group": 0}, ...]`;

  const upstream = await fetch(OPENROUTER_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: OPENROUTER_MODEL,
      messages: [{ role: "user", content: prompt }],
      temperature: 0,
    }),
  });

  if (!upstream.ok) {
    throw new Error(`OpenRouter HTTP ${upstream.status}: ${await upstream.text()}`);
  }

  const decoded = await upstream.json();
  const content = decoded?.choices?.[0]?.message?.content as string | undefined;
  if (!content) throw new Error("Unexpected OpenRouter response shape");

  const start = content.indexOf("[");
  const end = content.lastIndexOf("]");
  if (start === -1 || end === -1 || end < start) {
    throw new Error("No JSON array found in model output");
  }
  const parsed = JSON.parse(content.substring(start, end + 1)) as Array<
    { index?: number; category?: string; group?: unknown }
  >;

  const results = [];
  for (const entry of parsed) {
    const index = entry.index;
    if (index === undefined || index < 0 || index >= articles.length) continue;
    results.push({
      articleId: articles[index].id,
      category: entry.category ?? null,
      groupId: entry.group !== undefined && entry.group !== null ? `${runId}_g${entry.group}` : null,
    });
  }
  return results;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const errors: string[] = [];
  const runId = crypto.randomUUID();

  const { data: sources, error: sourcesError } = await supabase
    .from("sources")
    .select("id, name, feed_url")
    .eq("enabled", true);

  if (sourcesError) {
    return new Response(JSON.stringify({ error: sourcesError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const fetched: ArticleRow[] = [];
  for (const source of (sources ?? []) as Source[]) {
    try {
      fetched.push(...(await fetchSource(source)));
    } catch (e) {
      errors.push(`${source.name}: ${e}`);
    }
  }

  const deduped = Object.values(
    Object.fromEntries(fetched.map((a) => [a.id, a])),
  ) as ArticleRow[];

  if (deduped.length > 0) {
    const { error: upsertError } = await supabase.from("articles").upsert(deduped);
    if (upsertError) errors.push(`upsert: ${upsertError.message}`);
  }

  let enrichedCount = 0;
  if (deduped.length > 0) {
    try {
      const enrichments = await enrichArticles(deduped, runId);
      for (const e of enrichments) {
        const values: Record<string, unknown> = {};
        if (e.category !== null) values.category = e.category;
        if (e.groupId !== null) values.group_id = e.groupId;
        if (Object.keys(values).length === 0) continue;
        const { error } = await supabase.from("articles").update(values).eq("id", e.articleId);
        if (!error) enrichedCount++;
      }
    } catch (e) {
      errors.push(`enrichment: ${e}`);
    }
  }

  const cutoff = new Date(Date.now() - PRUNE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const { error: pruneError } = await supabase.from("articles").delete().lt("pub_date", cutoff);
  if (pruneError) errors.push(`prune: ${pruneError.message}`);

  return new Response(
    JSON.stringify({
      runId,
      sourcesTried: (sources ?? []).length,
      articlesFetched: fetched.length,
      articlesUpserted: deduped.length,
      articlesEnriched: enrichedCount,
      errors,
      finishedAt: new Date().toISOString(),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
