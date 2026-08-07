import type { Message, PermissionContentData } from "@/types";

/** Approvals anchored to a bot turn render inside Agent steps, not as channel rows. */
export function isFoldedPermission(m: Message): boolean {
  if (m.msg_type !== "permission") return false;
  const source = (m.content_data as PermissionContentData | null | undefined)
    ?.source_msg_id;
  return typeof source === "string" && source.length > 0;
}

export function permissionSourceId(m: Message): string | null {
  const source = (m.content_data as PermissionContentData | null | undefined)
    ?.source_msg_id;
  return typeof source === "string" && source.length > 0 ? source : null;
}

export function messageSessionId(m: Message): string | null {
  const data = m.content_data as Record<string, unknown> | null | undefined;
  const sid = data?.session_id;
  return typeof sid === "string" && sid.length > 0 ? sid : null;
}

/**
 * Split a loaded message window into top-level roots and children keyed by parent.
 * A message with `reply_to_msg_id` pointing at another loaded (non-folded) message
 * is a sub-message; otherwise it stays a root (orphan reply when parent isn't loaded).
 * Folded permissions are excluded from both roots and children.
 */
export function groupMessagesByReply(messages: Message[]): {
  roots: Message[];
  childrenByParent: Map<string, Message[]>;
  byId: Map<string, Message>;
} {
  const byId = new Map<string, Message>();
  for (const msg of messages) {
    if (isFoldedPermission(msg)) continue;
    byId.set(msg.msg_id, msg);
  }

  const childrenByParent = new Map<string, Message[]>();
  const roots: Message[] = [];

  for (const msg of messages) {
    if (isFoldedPermission(msg)) continue;
    const parentId = msg.reply_to_msg_id;
    if (parentId && byId.has(parentId) && parentId !== msg.msg_id) {
      const list = childrenByParent.get(parentId);
      if (list) list.push(msg);
      else childrenByParent.set(parentId, [msg]);
    } else {
      roots.push(msg);
    }
  }

  // Keep each sibling list in channel order (stable: messages already sorted).
  for (const [, kids] of childrenByParent) {
    kids.sort((a, b) => (a.channel_seq ?? 0) - (b.channel_seq ?? 0));
  }

  return { roots, childrenByParent, byId };
}
