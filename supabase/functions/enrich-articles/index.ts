// Calls an OpenRouter-hosted LLM to categorize freshly-scraped articles and
// detect same-story duplicates across sources, so the OpenRouter API key
// never has to live in the client app.
//
// A user can pass their own OpenRouter token in the request body; if they
// don't, this falls back to the project's OPENROUTER_API_KEY secret. Set it
// with: supabase secrets set OPENROUTER_API_KEY=<key> --project-ref <ref>
// (or via Dashboard -> Edge Functions -> Secrets). If neither is present,
// this returns a 400 explaining that.
const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const DEFAULT_MODEL = "openai/gpt-4o-mini";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ArticleInput {
  id: string;
  title: string;
  source: string;
  description?: string;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function extractJsonArray(content: string): string {
  const start = content.indexOf("[");
  const end = content.lastIndexOf("]");
  if (start === -1 || end === -1 || end < start) {
    throw new Error("No JSON array found in model output");
  }
  return content.substring(start, end + 1);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let body: {
    articles?: ArticleInput[];
    runId?: string;
    model?: string;
    userToken?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const articles = body.articles ?? [];
  const runId = body.runId ?? crypto.randomUUID();
  const model = body.model || DEFAULT_MODEL;
  const apiKey = body.userToken && body.userToken.trim().length > 0
    ? body.userToken.trim()
    : Deno.env.get("OPENROUTER_API_KEY");

  if (!apiKey) {
    return jsonResponse(
      { error: "No OpenRouter API key: pass userToken, or set the OPENROUTER_API_KEY project secret." },
      400,
    );
  }

  if (articles.length === 0) {
    return jsonResponse([]);
  }

  const indexed = articles.map((a, i) => ({
    index: i,
    title: a.title,
    source: a.source,
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

  let upstream: Response;
  try {
    upstream = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: prompt }],
        temperature: 0,
      }),
    });
  } catch (e) {
    return jsonResponse({ error: `OpenRouter request failed: ${e}` }, 502);
  }

  if (!upstream.ok) {
    const text = await upstream.text();
    return jsonResponse({ error: `OpenRouter HTTP ${upstream.status}: ${text}` }, 502);
  }

  const decoded = await upstream.json();
  const content = decoded?.choices?.[0]?.message?.content as string | undefined;
  if (!content) {
    return jsonResponse({ error: "Unexpected OpenRouter response shape" }, 502);
  }

  let parsed: Array<{ index?: number; category?: string; group?: unknown }>;
  try {
    parsed = JSON.parse(extractJsonArray(content));
  } catch (e) {
    return jsonResponse({ error: `Could not parse model output as JSON: ${e}` }, 502);
  }

  const results = [];
  for (const entry of parsed) {
    const index = entry.index;
    if (index === undefined || index < 0 || index >= articles.length) continue;
    results.push({
      articleId: articles[index].id,
      category: entry.category ?? null,
      groupId: entry.group !== undefined && entry.group !== null
        ? `${runId}_g${entry.group}`
        : null,
    });
  }

  return jsonResponse(results);
});
