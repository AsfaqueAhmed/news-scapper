// Many RSS feeds omit an image on some items even though the article page
// itself has one (og:image, twitter:image, or just the first inline photo).
// This job finds recent articles still missing image_url, fetches the
// article's own page, and pulls the first usable image out of the HTML.
//
// Scoped deliberately narrow so it can't turn into an unbounded crawl:
//  - only articles published on/after IMAGE_BACKFILL_CUTOFF
//  - only articles never attempted before (image_checked_at IS NULL)
//  - at most `limit` (default 3) per invocation, via a 5-minute pg_cron job
// Every attempt -- found or not -- sets image_checked_at so it's never
// retried, and is logged to fetch_log for the same observability the
// scrape cycle already has.
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 2026-08-02 00:00 BDT (UTC+6) -- articles published before this were
// already in the app before this feature shipped and are left alone.
const IMAGE_BACKFILL_CUTOFF = "2026-08-01T18:00:00.000Z";
const DEFAULT_LIMIT = 3;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Candidate {
  id: string;
  link: string;
  source_id: string;
  source_name: string;
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

// Also catches generic site-wide fallback/template images some CMSs
// render on every article page -- a default og:image
// (thehindu.com/theme/images/og-image.png), a syndication trust badge
// (thehindu.com/theme/images/th-online/google-preferred-badge.png), etc.
// None of those are a real per-article photo.
const SKIP_IMAGE_PATTERN =
  /(logo|icon|sprite|avatar|spacer|blank|placeholder|1x1|pixel\.|og-image|og_image|default[-_]?image|fallback|share-image|social-image|badge|preferred)/i;

// Analytics/tracking beacons (scorecardresearch, GA, etc.) are often the
// first <img> tag in a page's HTML for tracking purposes, well before any
// real content photo. Requiring a genuine image extension in the path
// (before any query string) filters those out, since beacon URLs are
// almost always an endpoint path like "/p" or "/collect" with no
// extension at all.
const IMAGE_EXTENSION_PATTERN = /\.(?:jpe?g|png|webp|gif|avif)(?:$|\?)/i;

function firstMetaImage(html: string): string | null {
  const patterns = [
    /<meta[^>]+property=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["']/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image(?::secure_url)?["']/i,
    /<meta[^>]+name=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["']/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image(?::src)?["']/i,
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match?.[1]) return match[1];
  }
  return null;
}

// Prefer scanning inside <article>/<main> -- global template chrome
// (header logos, trust badges, nav icons) lives outside those tags on
// almost every news CMS, so this alone filters out most site-wide junk
// before the keyword/extension checks even run. Falls back to the whole
// document if neither tag is present.
function articleSection(html: string): string {
  for (const tag of ["article", "main"]) {
    const match = html.match(new RegExp(`<${tag}[^>]*>[\\s\\S]*?<\\/${tag}>`, "i"));
    if (match) return match[0];
  }
  return html;
}

function firstContentImage(html: string): string | null {
  const imgTag = /<img[^>]+src=["']([^"']+)["']/gi;
  let match: RegExpExecArray | null;
  while ((match = imgTag.exec(articleSection(html))) !== null) {
    const src = match[1];
    if (!src || src.startsWith("data:") || SKIP_IMAGE_PATTERN.test(src)) continue;
    if (!IMAGE_EXTENSION_PATTERN.test(src)) continue;
    return src;
  }
  return null;
}

async function findArticleImage(articleUrl: string): Promise<string | null> {
  let response: Response;
  try {
    response = await fetch(articleUrl, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml",
      },
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) {
    throw new FetchError(`Network error: ${e}`);
  }
  if (!response.ok) throw new FetchError(`HTTP ${response.status}`, response.status);

  const html = await response.text();
  let raw = firstMetaImage(html);
  if (raw && SKIP_IMAGE_PATTERN.test(raw)) raw = null;
  raw ??= firstContentImage(html);
  if (!raw) return null;

  try {
    return new URL(raw, articleUrl).href;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let body: { limit?: number } = {};
  if (req.method === "POST") {
    try {
      body = await req.json();
    } catch {
      // no/empty body is fine, use defaults
    }
  }
  const limit = body.limit ?? DEFAULT_LIMIT;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const runId = crypto.randomUUID();
  const errors: string[] = [];

  const { data: candidates, error: selectError } = await supabase
    .from("articles")
    .select("id, link, source_id, source_name")
    .is("image_url", null)
    .is("image_checked_at", null)
    .gte("pub_date", IMAGE_BACKFILL_CUTOFF)
    .order("pub_date", { ascending: true })
    .limit(limit);

  if (selectError) {
    return new Response(JSON.stringify({ error: selectError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const logRows: FetchLogRow[] = [];
  let imagesFound = 0;

  for (const article of (candidates ?? []) as Candidate[]) {
    const calledAt = new Date();
    const t0 = performance.now();
    let status: "success" | "error" = "success";
    let httpStatus: number | null = null;
    let errorMessage: string | null = null;
    let imageUrl: string | null = null;

    try {
      imageUrl = await findArticleImage(article.link);
      httpStatus = 200;
    } catch (e) {
      status = "error";
      errorMessage = e instanceof Error ? e.message : String(e);
      httpStatus = e instanceof FetchError ? e.httpStatus ?? null : null;
      errors.push(`${article.id}: ${errorMessage}`);
    }

    const updates: Record<string, unknown> = { image_checked_at: new Date().toISOString() };
    if (imageUrl) {
      updates.image_url = imageUrl;
      imagesFound++;
    }
    const { error: updateError } = await supabase.from("articles").update(updates).eq("id", article.id);
    if (updateError) errors.push(`update ${article.id}: ${updateError.message}`);

    logRows.push({
      run_id: runId,
      source_id: article.source_id,
      source_name: article.source_name,
      feed_url: article.link,
      status,
      http_status: httpStatus,
      articles_found: imageUrl ? 1 : 0,
      duration_ms: Math.round(performance.now() - t0),
      error_message: errorMessage,
      called_at: calledAt.toISOString(),
    });
  }

  if (logRows.length > 0) {
    const { error: logError } = await supabase.from("fetch_log").insert(logRows);
    if (logError) errors.push(`fetch_log insert: ${logError.message}`);
  }

  return new Response(
    JSON.stringify({
      runId,
      candidatesChecked: (candidates ?? []).length,
      imagesFound,
      errors,
      finishedAt: new Date().toISOString(),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
