// Round-robin batched scrape: each invocation fetches the next `limit`
// (default 5) enabled sources, tracked via the `fetch_cursor` table so a
// 5-minute cron cycles through the full source list over time instead of
// needing one cron job per fixed offset. Every per-source fetch attempt is
// logged to `fetch_log` (status, http status, duration, article count,
// error) for observability. Pass an explicit `offset` in the body to
// override the cursor for a one-off manual run (doesn't touch the cursor).
import { createClient } from "npm:@supabase/supabase-js@2";
import { XMLParser } from "npm:fast-xml-parser@4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY");

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const OPENROUTER_MODEL = "openai/gpt-4o-mini";
const PRUNE_AFTER_DAYS = 14;
const DEFAULT_BATCH_SIZE = 5;

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

interface FetchLogRow {
  run_id: string;
  source_id: string;
  source_name: string;
  feed_url: string;
  status: "success" | "error";
  http_status: number | null;
  articles_found: number | null;
  duration_ms: number;
  error_message: string | null;
  called_at: string;
}

class FetchError extends Error {
  httpStatus?: number;
  constructor(message: string, httpStatus?: number) {
    super(message);
    this.httpStatus = httpStatus;
  }
}

function asArray<T>(v: T | T[] | undefined | null): T[] {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

// fast-xml-parser only gives back a plain string for a tag whose content
// is pure text. A tag containing markup -- e.g. The Daily Star wraps
// headlines as `<title><a href="...">Real Headline</a></title>` -- parses
// into a nested object instead (keyed by child tag name, "#text" for
// surrounding text, "@_..." for attributes). Naively `String()`-ing that
// object produces the literal text "[object Object]" rather than the
// headline. Recursively collect every text fragment so any such nesting
// still yields real text.
function extractText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value)) return value.map(extractText).join(" ");
  if (typeof value === "object") {
    const parts: string[] = [];
    for (const [key, val] of Object.entries(value as Record<string, unknown>)) {
      if (key.startsWith("@_")) continue; // skip XML attributes
      parts.push(extractText(val));
    }
    return parts.join(" ");
  }
  return "";
}

function stripHtml(value?: unknown): string | null {
  if (value === undefined || value === null) return null;
  const text = extractText(value)
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

// Scoped by source: a publisher that runs multiple feeds (e.g. BBC's
// News/UK/World feeds all link back to the same bbc.co.uk article URLs)
// would otherwise collapse into a single row, with whichever source's
// batch ran last silently overwriting the others. Keeping them as
// separate per-source rows matches how genuinely different publishers
// covering the same story already work -- the AI enrichment's groupId
// links them together as "N sources" instead of one silently winning.
async function articleId(link: string, sourceId: string, title: string): Promise<string> {
  const basis = link.length > 0 ? `${sourceId}|${link}` : `${sourceId}|${title}`;
  const data = new TextEncoder().encode(basis);
  const hash = await crypto.subtle.digest("SHA-1", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const xmlParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  isArray: (name) => name === "item" || name === "entry" || name === "link",
  // stripHtml() already decodes the handful of entities we care about
  // (&amp; &quot; &#39; &lt; &gt;) after parsing. Leaving the parser's own
  // entity processing on hits its built-in expansion-limit guard (>1000
  // entities in one document) on content-heavy feeds like The Guardian's.
  processEntities: false,
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
  let response: Response;
  try {
    response = await fetch(source.feed_url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; NewsScrapperBot/1.0)",
        "Accept": "application/rss+xml, application/xml, text/xml, */*",
      },
      signal: AbortSignal.timeout(20000),
    });
  } catch (e) {
    throw new FetchError(`Network error: ${e}`);
  }
  if (!response.ok) {
    throw new FetchError(`HTTP ${response.status}`, response.status);
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

  let body: { offset?: number; limit?: number } = {};
  if (req.method === "POST") {
    try {
      body = await req.json();
    } catch {
      // no/empty body is fine, use defaults
    }
  }
  const limit = body.limit ?? DEFAULT_BATCH_SIZE;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const errors: string[] = [];
  const runId = crypto.randomUUID();

  const { data: allSources, error: sourcesError } = await supabase
    .from("sources")
    .select("id, name, feed_url")
    .eq("enabled", true)
    .order("id");

  if (sourcesError) {
    return new Response(JSON.stringify({ error: sourcesError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const totalCount = (allSources ?? []).length;

  // usingCursor calls atomically claim their offset AND advance the
  // shared cursor in one row-locked transaction (claim_next_fetch_offset),
  // so two overlapping invocations can never read the same offset and
  // duplicate a batch.
  const usingCursor = typeof body.offset !== "number";
  let offset: number;
  if (!usingCursor) {
    offset = totalCount === 0 ? 0 : (body.offset as number) % totalCount;
  } else {
    const { data: claimedOffset, error: claimError } = await supabase.rpc(
      "claim_next_fetch_offset",
      { p_limit: limit, p_total: totalCount },
    );
    if (claimError) {
      return new Response(JSON.stringify({ error: `cursor claim: ${claimError.message}` }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    offset = claimedOffset ?? 0;
  }

  const sources = (allSources ?? []).slice(offset, offset + limit) as Source[];

  const fetched: ArticleRow[] = [];
  const logRows: FetchLogRow[] = [];
  for (const source of sources) {
    const calledAt = new Date();
    const t0 = performance.now();
    let status: "success" | "error" = "success";
    let httpStatus: number | null = null;
    let articlesFound: number | null = null;
    let errorMessage: string | null = null;
    try {
      const articles = await fetchSource(source);
      fetched.push(...articles);
      articlesFound = articles.length;
      httpStatus = 200;
    } catch (e) {
      status = "error";
      errorMessage = e instanceof Error ? e.message : String(e);
      httpStatus = e instanceof FetchError ? e.httpStatus ?? null : null;
      errors.push(`${source.name}: ${errorMessage}`);
    }
    logRows.push({
      run_id: runId,
      source_id: source.id,
      source_name: source.name,
      feed_url: source.feed_url,
      status,
      http_status: httpStatus,
      articles_found: articlesFound,
      duration_ms: Math.round(performance.now() - t0),
      error_message: errorMessage,
      called_at: calledAt.toISOString(),
    });
  }

  if (logRows.length > 0) {
    const { error: logError } = await supabase.from("fetch_log").insert(logRows);
    if (logError) errors.push(`fetch_log insert: ${logError.message}`);
  }

  const deduped = Object.values(
    Object.fromEntries(fetched.map((a) => [a.id, a])),
  ) as ArticleRow[];

  if (deduped.length > 0) {
    // Exclude is_read: a re-scraped article is always freshly parsed as
    // unread, and upserting that would silently clobber a user's "read"
    // state every time this source gets re-fetched. Leaving it out of the
    // payload means new rows still get false (the column default) while
    // existing rows keep whatever is_read they had.
    const rows = deduped.map(({ is_read: _is_read, ...rest }) => rest);
    const { error: upsertError } = await supabase.from("articles").upsert(rows);
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

  // Prune once per full cycle: fires whenever a turn starts back at the
  // beginning of the rotation (offset 0), same cadence regardless of how
  // many sources/batches there are.
  if (offset === 0) {
    const cutoff = new Date(Date.now() - PRUNE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const { error: pruneError } = await supabase.from("articles").delete().lt("pub_date", cutoff);
    if (pruneError) errors.push(`prune: ${pruneError.message}`);
  }

  // The cursor was already atomically advanced by claim_next_fetch_offset
  // above; this is purely for the response, not a second write.
  let nextOffset = offset + limit;
  if (totalCount === 0 || nextOffset >= totalCount) nextOffset = 0;

  return new Response(
    JSON.stringify({
      runId,
      usingCursor,
      offset,
      nextOffset,
      totalEnabledSources: totalCount,
      limit,
      sourcesTried: sources.length,
      sourceNames: sources.map((s) => s.name),
      articlesFetched: fetched.length,
      articlesUpserted: deduped.length,
      articlesEnriched: enrichedCount,
      errors,
      finishedAt: new Date().toISOString(),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
