// Proxies RSS/Atom feed fetches server-side so the Flutter web build can
// read feeds that don't send CORS headers (BBC, Guardian, TechCrunch, etc.
// all reject direct browser fetches). No auth: this only ever forwards a
// GET to a caller-supplied public feed URL and returns the raw body, so
// there's no user data or write access to protect.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const target = new URL(req.url).searchParams.get("url");
  if (!target) {
    return new Response(JSON.stringify({ error: "Missing url parameter" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let parsed: URL;
  try {
    parsed = new URL(target);
  } catch {
    return new Response(JSON.stringify({ error: "Invalid url parameter" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return new Response(JSON.stringify({ error: "Only http(s) urls are allowed" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const upstream = await fetch(parsed.toString(), {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; NewsScrapperBot/1.0; +https://github.com/AsfaqueAhmed/news-scapper)",
        "Accept": "application/rss+xml, application/xml, text/xml, */*",
      },
      redirect: "follow",
    });
    // upstream.text() already decoded the body correctly (using the
    // upstream's declared charset, or UTF-8 by default per the Fetch
    // spec) -- but many feeds' Content-Type omits a charset entirely
    // (e.g. plain "text/plain" or "application/rss+xml"), and returning
    // that as-is downstream is what broke non-ASCII text: Dart's `http`
    // package defaults to Latin-1 when no charset is declared, so any
    // multi-byte UTF-8 text (Bengali, etc.) got mis-decoded into mojibake
    // even though the actual bytes on the wire were correct UTF-8. Always
    // declaring charset=utf-8 here matches what `new Response(body)`
    // actually sends (a JS string body is always UTF-8-encoded), so every
    // client decodes it the same, correct way.
    const body = await upstream.text();
    const upstreamType = upstream.headers.get("content-type") ?? "application/xml";
    const baseType = upstreamType.split(";")[0].trim();
    return new Response(body, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        "Content-Type": `${baseType}; charset=utf-8`,
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `Upstream fetch failed: ${e}` }), {
      status: 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
