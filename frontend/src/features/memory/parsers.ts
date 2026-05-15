import type { FileCard, TimelineItem } from "./types";

export function relativeTime(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const now = Date.now();
  const diff = now - d.getTime();
  if (diff < 60000) return "刚刚";
  if (diff < 3600000) return `${Math.floor(diff / 60000)} 分钟前`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)} 小时前`;
  return d.toLocaleDateString("zh-CN", { month: "short", day: "numeric" });
}

export function parseFilesIndex(md: string): FileCard[] {
  if (!md.trim()) return [];
  const blocks = md
    .split(/\n---\n/)
    .map((b) => b.trim())
    .filter(Boolean);
  return blocks.map((block) => {
    const lines = block.split("\n");
    const filename = (lines[0] || "").replace(/^###\s*/, "");
    let fileId = "";
    let contentType = "";
    let summary = "";
    let time = "";
    for (const line of lines.slice(1)) {
      const m = line.match(/^-\s*file_id:\s*`([^`]+)`/);
      if (m) {
        fileId = m[1];
        continue;
      }
      const m2 = line.match(/^-\s*类型:\s*(.+)/);
      if (m2) {
        contentType = m2[1].trim();
        continue;
      }
      const m3 = line.match(/^-\s*摘要:\s*(.+)/);
      if (m3) {
        summary = m3[1].trim();
        continue;
      }
      const m4 = line.match(/^-\s*登记时间:\s*(.+)/);
      if (m4) {
        time = m4[1].trim();
      }
    }
    return { filename, fileId, contentType, summary, time };
  });
}

export function parseRecentXml(xml: string): TimelineItem[] {
  if (!xml.trim()) return [];
  const items: TimelineItem[] = [];
  const re =
    /<page\s+id="([^"]*)"[^>]*from="([^"]*)"[^>]*to="([^"]*)">([\s\S]*?)<\/page>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    items.push({ pageId: m[1], from: m[2], to: m[3], summary: m[4] });
  }
  return items;
}

export function formatRange(from: string, to: string): string {
  try {
    const a = new Date(from);
    const b = new Date(to);
    const df = a.toLocaleDateString("zh-CN", {
      month: "short",
      day: "numeric",
    });
    const tf = a.toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
    });
    const tb = b.toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
    });
    return `${df} ${tf} — ${tb}`;
  } catch {
    return `${from} — ${to}`;
  }
}
