// Homepage HTML scrapers for BD newspapers whose RSS feeds lag behind
// their live site. There's no shared markup pattern across BD news
// homepages (confirmed against both live sites and the selectors used in
// github.com/KSMubasshir/bd-newspaper-crawlers), so each outlet gets its
// own small parser here rather than one generic heuristic.
import { parseHTML } from "npm:linkedom@0.18.5";

export interface ScrapedItem {
  title: string;
  link: string;
  imageUrl: string | null;
}

export function resolveUrl(href: string, base: string): string {
  try {
    return new URL(href, base).toString();
  } catch {
    return href;
  }
}

function parseProthomAloHomepage(html: string, baseUrl: string): ScrapedItem[] {
  const { document } = parseHTML(html);
  const items: ScrapedItem[] = [];
  const seen = new Set<string>();
  for (const anchor of document.querySelectorAll(".headline-title .title-link[href]")) {
    const href = anchor.getAttribute("href");
    const title = (anchor.textContent ?? "").trim();
    if (!href || !title) continue;
    const link = resolveUrl(href, baseUrl);
    if (seen.has(link)) continue;
    seen.add(link);
    items.push({ title, link, imageUrl: null });
  }
  return items;
}

function parseDailyStarHomepage(html: string, baseUrl: string): ScrapedItem[] {
  const { document } = parseHTML(html);
  const items: ScrapedItem[] = [];
  const seen = new Set<string>();
  for (const anchor of document.querySelectorAll(".card-title a[href]")) {
    const href = anchor.getAttribute("href");
    const title = (anchor.textContent ?? "").trim();
    if (!href || !title) continue;
    const link = resolveUrl(href, baseUrl);
    if (seen.has(link)) continue;
    seen.add(link);
    const card = anchor.closest(".card");
    const img = card?.querySelector("img[src]");
    const imgSrc = img?.getAttribute("src");
    items.push({ title, link, imageUrl: imgSrc ? resolveUrl(imgSrc, baseUrl) : null });
  }
  return items;
}

export const htmlScrapers: Record<string, (html: string, baseUrl: string) => ScrapedItem[]> = {
  "prothom-alo": parseProthomAloHomepage,
  "the-daily-star": parseDailyStarHomepage,
};
