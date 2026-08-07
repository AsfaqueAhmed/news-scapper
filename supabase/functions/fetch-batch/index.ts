// Two modes, one implementation: this is the ONLY place RSS/Atom feeds get
// fetched and parsed -- the app used to duplicate this logic client-side
// (Dart), and the two implementations drifted out of sync (broken RFC 822
// date parsing, a different article-id scheme), which is exactly what
// caused corrupted pub_dates and duplicate rows. Now every ingestion path
// goes through here.
//
//  - Rotation mode (no `sourceIds` in the body): each invocation fetches
//    the next `limit` (default 5) enabled sources, tracked via the
//    `fetch_cursor` table so a cron (every 2 minutes, offset by 3) cycles
//    through the full source list over time.
//  - On-demand mode (`sourceIds: string[]` in the body): fetches exactly
//    those sources, e.g. the app's "pull to refresh". Skips the rotating
//    cursor and the once-per-cycle prune -- those are exclusive to the
//    scheduled rotation.
//
// Different sources are fetched in parallel; within one source, its RSS
// and HTML attempts run sequentially (see `attempts.push(await ...)`
// below), so a slow homepage scrape adds to that source's own turn rather
// than the whole batch's. Every per-source fetch attempt is logged to
// `fetch_log` (status, http status, duration, article count, error) for
// observability.
import { createClient } from "npm:@supabase/supabase-js@2";
import { XMLParser } from "npm:fast-xml-parser@4";
import { htmlScrapers } from "./html_scrapers.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY");

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const OPENROUTER_MODEL = "openai/gpt-4o-mini";
// AI enrichment is temporarily switched off -- flip to true to resume
// calling OpenRouter from the scheduled scrape. Nothing else changes.
const ENRICHMENT_ENABLED = false;
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
  feed_url: string | null;
  base_url: string | null;
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
  method: "rss" | "html";
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

async function fetchRss(source: Source): Promise<ArticleRow[]> {
  let response: Response;
  try {
    response = await fetch(source.feed_url!, {
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

async function fetchHtml(source: Source): Promise<ArticleRow[]> {
  const scraper = htmlScrapers[source.id];
  if (!scraper || !source.base_url) return [];
  let response: Response;
  try {
    response = await fetch(source.base_url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; NewsScrapperBot/1.0)",
        "Accept": "text/html",
      },
      signal: AbortSignal.timeout(20000),
    });
  } catch (e) {
    throw new FetchError(`Network error: ${e}`);
  }
  if (!response.ok) {
    throw new FetchError(`HTTP ${response.status}`, response.status);
  }
  const html = await response.text();
  const items = scraper(html, source.base_url);
  const rows: ArticleRow[] = [];
  for (const item of items) {
    rows.push({
      id: await articleId(item.link, source.id, item.title),
      title: item.title,
      link: item.link,
      description: null,
      image_url: item.imageUrl,
      pub_date: new Date().toISOString(),
      source_id: source.id,
      source_name: source.name,
      is_read: false,
    });
  }
  return rows;
}

async function enrichArticles(
  articles: ArticleRow[],
  runId: string,
  apiToken?: string,
): Promise<Array<{ articleId: string; category: string | null; groupId: string | null }>> {
  const key = apiToken || OPENROUTER_API_KEY;
  if (!key || articles.length === 0) return [];

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
      Authorization: `Bearer ${key}`,
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

interface FetchAttempt {
  articles: ArticleRow[];
  logRow: FetchLogRow;
}

async function attemptFetch(
  source: Source,
  method: "rss" | "html",
  url: string,
  runId: string,
  run: () => Promise<ArticleRow[]>,
): Promise<FetchAttempt> {
  const calledAt = new Date();
  const t0 = performance.now();
  try {
    const articles = await run();
    return {
      articles,
      logRow: {
        run_id: runId,
        source_id: source.id,
        source_name: source.name,
        feed_url: url,
        method,
        status: "success",
        http_status: 200,
        articles_found: articles.length,
        duration_ms: Math.round(performance.now() - t0),
        error_message: null,
        called_at: calledAt.toISOString(),
      },
    };
  } catch (e) {
    const errorMessage = e instanceof Error ? e.message : String(e);
    return {
      articles: [],
      logRow: {
        run_id: runId,
        source_id: source.id,
        source_name: source.name,
        feed_url: url,
        method,
        status: "error",
        http_status: e instanceof FetchError ? e.httpStatus ?? null : null,
        articles_found: null,
        duration_ms: Math.round(performance.now() - t0),
        error_message: errorMessage,
        called_at: calledAt.toISOString(),
      },
    };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let body: { offset?: number; limit?: number; sourceIds?: string[]; openRouterToken?: string } = {};
  if (req.method === "POST") {
    try {
      body = await req.json();
    } catch {
      // no/empty body is fine, use defaults
    }
  }
  const limit = body.limit ?? DEFAULT_BATCH_SIZE;
  const explicitSourceIds =
    Array.isArray(body.sourceIds) && body.sourceIds.length > 0 ? body.sourceIds : null;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const errors: string[] = [];
  const runId = crypto.randomUUID();

  let sources: Source[];
  let offset = 0;
  let usingCursor = false;
  let totalCount = 0;

  if (explicitSourceIds) {
    // On-demand mode: fetch exactly the requested sources, skipping the
    // rotating-cursor bookkeeping below (that's exclusive to the
    // scheduled cron sweep).
    const { data: requested, error: requestedError } = await supabase
      .from("sources")
      .select("id, name, feed_url, base_url")
      .in("id", explicitSourceIds)
      .eq("enabled", true);
    if (requestedError) {
      return new Response(JSON.stringify({ error: requestedError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    sources = (requested ?? []) as Source[];
  } else {
    const { data: allSources, error: sourcesError } = await supabase
      .from("sources")
      .select("id, name, feed_url, base_url")
      .eq("enabled", true)
      .order("id");

    if (sourcesError) {
      return new Response(JSON.stringify({ error: sourcesError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    totalCount = (allSources ?? []).length;

    // usingCursor calls atomically claim their offset AND advance the
    // shared cursor in one row-locked transaction (claim_next_fetch_offset),
    // so two overlapping invocations can never read the same offset and
    // duplicate a batch.
    usingCursor = typeof body.offset !== "number";
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

    sources = (allSources ?? []).slice(offset, offset + limit) as Source[];
  }

  const results = await Promise.all(sources.map(async (source) => {
    const attempts: FetchAttempt[] = [];
    if (source.feed_url) {
      attempts.push(await attemptFetch(source, "rss", source.feed_url, runId, () => fetchRss(source)));
    }
    if (htmlScrapers[source.id] && source.base_url) {
      attempts.push(await attemptFetch(source, "html", source.base_url, runId, () => fetchHtml(source)));
    }
    if (attempts.length === 0) {
      // A source with no RSS feed and no registered HTML scraper (e.g. one
      // just added via the app with only a Base URL, for an outlet that
      // hasn't gotten a scraper yet) would otherwise fetch nothing and
      // leave no trace anywhere -- not even a fetch_log row -- making it
      // indistinguishable from a source that's simply quiet. Logging it
      // makes that state visible instead of silent.
      attempts.push(
        await attemptFetch(source, "html", source.base_url ?? "", runId, () => {
          throw new Error("No feed_url and no registered HTML scraper for this source");
        }),
      );
    }
    return { source, attempts };
  }));

  const fetched: ArticleRow[] = [];
  const rssArticles: ArticleRow[] = [];
  const htmlArticles: ArticleRow[] = [];
  const logRows: FetchLogRow[] = [];
  for (const r of results) {
    for (const attempt of r.attempts) {
      fetched.push(...attempt.articles);
      (attempt.logRow.method === "rss" ? rssArticles : htmlArticles).push(...attempt.articles);
      logRows.push(attempt.logRow);
      if (attempt.logRow.status === "error") {
        errors.push(`${r.source.name} (${attempt.logRow.method}): ${attempt.logRow.error_message}`);
      }
    }
  }

  if (logRows.length > 0) {
    const { error: logError } = await supabase.from("fetch_log").insert(logRows);
    if (logError) errors.push(`fetch_log insert: ${logError.message}`);
  }

  // RSS always wins over HTML for the same article (same link -> same id):
  // seed the map from `rssArticles` first, then let `htmlArticles` fill in
  // only ids RSS didn't already cover *within this tick*. Dedup within one
  // tick isn't enough on its own, though -- across ticks, an article the
  // homepage still lists but this tick's RSS payload doesn't happen to
  // include (RSS windows are short) would otherwise get its already-good
  // pub_date/description/image_url overwritten by the plain `upsert` below,
  // since upsert replaces the whole row on conflict. So html-only rows are
  // upserted separately with `ignoreDuplicates: true` (ON CONFLICT DO
  // NOTHING): a homepage article lands once, the first time any tick sees
  // it, and every later tick leaves an existing row completely alone
  // rather than re-stamping it with a fresh "now" and a null
  // description/image. Only rows RSS actually re-affirms in a given tick
  // get the full overwrite -- which is correct, since RSS is the
  // authoritative source when it has an opinion.
  const seen = new Map<string, ArticleRow>();
  for (const article of rssArticles) seen.set(article.id, article);
  for (const article of htmlArticles) {
    if (!seen.has(article.id)) seen.set(article.id, article);
  }
  const deduped = Array.from(seen.values());
  const rssIds = new Set(rssArticles.map((a) => a.id));

  if (deduped.length > 0) {
    // Exclude is_read: a re-scraped article is always freshly parsed as
    // unread, and upserting that would silently clobber a user's "read"
    // state every time this source gets re-fetched. Leaving it out of the
    // payload means new rows still get false (the column default) while
    // existing rows keep whatever is_read they had.
    const rows = deduped.map(({ is_read: _is_read, ...rest }) => rest);
    const rssRows = rows.filter((row) => rssIds.has(row.id));
    const htmlOnlyRows = rows.filter((row) => !rssIds.has(row.id));
    let upsertFailed = false;

    if (rssRows.length > 0) {
      const { error } = await supabase.from("articles").upsert(rssRows);
      if (error) {
        errors.push(`upsert (rss): ${error.message}`);
        upsertFailed = true;
      }
    }
    if (htmlOnlyRows.length > 0) {
      const { error } = await supabase.from("articles").upsert(htmlOnlyRows, { ignoreDuplicates: true });
      if (error) {
        errors.push(`upsert (html-only): ${error.message}`);
        upsertFailed = true;
      }
    }

    if (!upsertFailed) {
      // Bump the app's realtime sync counter -- but only when something
      // actually landed, so idle cron ticks don't trigger client reloads.
      const { error: bumpError } = await supabase.rpc("bump_sync_version");
      if (bumpError) errors.push(`sync bump: ${bumpError.message}`);
    }
  }

  let enrichedCount = 0;
  if (ENRICHMENT_ENABLED && deduped.length > 0) {
    try {
      const enrichments = await enrichArticles(deduped, runId, body.openRouterToken);
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

  // Prune once per full cycle: fires whenever a scheduled rotation turn
  // starts back at the beginning (offset 0). Exclusive to rotation mode --
  // on-demand refreshes shouldn't trigger a prune sweep.
  if (!explicitSourceIds && offset === 0) {
    const cutoff = new Date(Date.now() - PRUNE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const { error: pruneError } = await supabase.from("articles").delete().lt("pub_date", cutoff);
    if (pruneError) errors.push(`prune: ${pruneError.message}`);
  }

  // The cursor was already atomically advanced by claim_next_fetch_offset
  // above; this is purely for the response, not a second write. Only
  // meaningful in rotation mode.
  let nextOffset = 0;
  if (!explicitSourceIds) {
    nextOffset = offset + limit;
    if (totalCount === 0 || nextOffset >= totalCount) nextOffset = 0;
  }

  return new Response(
    JSON.stringify({
      runId,
      mode: explicitSourceIds ? "sourceIds" : "rotation",
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
