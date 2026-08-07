import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Spinner } from "@/components/ui/spinner";
import toast from "react-hot-toast";
import { MessageItem, type MessageActionHandlers } from "./MessageItem";
import { formatDayLabel, sameDay } from "@/lib/format";
import type { Message } from "@/types";
import {
  groupMessagesByReply,
  isFoldedPermission,
  permissionSourceId,
} from "./messageTree";

// Skip layout/paint for off-screen rows during frequent streaming re-renders while
// keeping every row in the DOM — the data-msg-id jump, native scroll anchoring on
// prepend, day labels, and auto-scroll all keep working. `auto` in contain-intrinsic-size
// remembers each row's last real height; 80px is only the estimate for never-rendered rows.
const ROW_CONTENT_VISIBILITY: CSSProperties = {
  contentVisibility: "auto",
  containIntrinsicSize: "auto 80px",
};

interface Props {
  messages: Message[];
  currentUserId?: string;
  channelId?: string;
  /** Member id → display label, for messages that arrive without a sender_name. */
  senderNames?: Map<string, string>;
  hasMore?: boolean;
  onLoadMore?: () => void;
  loading?: boolean;
  /** Reply / copy / forward / multi-select callbacks (stable identity). */
  actions?: MessageActionHandlers;
  selectMode?: boolean;
  selectedIds?: ReadonlySet<string>;
  /** Jump request from outside (ViewBoard history items): scroll the message into
   *  view and flash it. `nonce` distinguishes repeat jumps to the same message.
   *  The sender (ChannelView) backfills history first, so the target is loaded. */
  focusMsg?: { msgId: string; nonce: number; requestId?: string | null } | null;
  /** Message currently being replied to — hosts the inline composer slot. */
  replyToId?: string | null;
  /** Inline reply composer (and context bar) rendered under `replyToId`. */
  inlineReply?: ReactNode;
}

export function MessageList({
  messages,
  currentUserId,
  channelId,
  senderNames,
  hasMore,
  onLoadMore,
  loading,
  actions,
  selectMode,
  selectedIds,
  focusMsg,
  replyToId,
  inlineReply,
}: Props) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const isAtBottomRef = useRef(true);
  // Transient flash for a jumped-to message (cleared after the highlight fades).
  const [highlightId, setHighlightId] = useState<string | null>(null);

  // Approvals keyed by the bot-turn msg_id they belong to (pending + resolved).
  const approvalsBySource = useMemo(() => {
    const map = new Map<string, Message[]>();
    for (const m of messages) {
      if (m.msg_type !== "permission") continue;
      const source = permissionSourceId(m);
      if (!source) continue;
      const list = map.get(source);
      if (list) list.push(m);
      else map.set(source, [m]);
    }
    return map;
  }, [messages]);

  const { roots, childrenByParent, byId } = useMemo(
    () => groupMessagesByReply(messages),
    [messages],
  );

  // External jump (ViewBoard history rows): scroll to the anchored row + flash.
  // ChannelView backfills older pages before focusing, so by the time focusMsg
  // lands the message is loaded — no anchor now means the row exists but isn't
  // rendered (e.g. an approval folded into the bot turn's Agent steps). Prefer
  // the source bot turn when the target is a folded permission card.
  useEffect(() => {
    if (!focusMsg) return;
    const folded = messages.find((m) => m.msg_id === focusMsg.msgId);
    const targetId =
      folded && isFoldedPermission(folded)
        ? permissionSourceId(folded) ?? focusMsg.msgId
        : focusMsg.msgId;
    const el = containerRef.current?.querySelector(
      `[data-msg-id="${CSS.escape(targetId)}"]`,
    );
    if (!el) {
      toast("This message isn't shown in the channel view", {
        icon: "🔍",
        id: "jump-hidden",
      });
      return;
    }
    el.scrollIntoView({ block: "center", behavior: "smooth" });
    setHighlightId(targetId);
    // content-visibility rows above the target materialize their real heights
    // during the smooth scroll (backfilled pages arrive with 80px estimates),
    // drifting the anchor — one instant corrective pass after it settles.
    const settle = setTimeout(() => {
      containerRef.current
        ?.querySelector(`[data-msg-id="${CSS.escape(targetId)}"]`)
        ?.scrollIntoView({ block: "center" });
    }, 700);
    const t = setTimeout(() => setHighlightId(null), 1800);
    return () => {
      clearTimeout(settle);
      clearTimeout(t);
    };
  }, [focusMsg, messages]);

  const nameOf = useMemo(
    () => (senderId: string) =>
      senderNames?.get(senderId) ?? senderId.slice(0, 8),
    [senderNames],
  );

  // Count every rendered message (roots + nested) for auto-scroll growth.
  const renderedCount = useMemo(() => {
    let n = 0;
    for (const m of messages) {
      if (!isFoldedPermission(m)) n += 1;
    }
    return n;
  }, [messages]);
  const prevLenRef = useRef(renderedCount);

  // Channel switch: the next content commit is a whole new timeline (cache seed
  // or cold reload), not an append — jump straight to the bottom instantly.
  const lastChannelRef = useRef(channelId);
  const channelSwitchScrollRef = useRef(false);
  if (lastChannelRef.current !== channelId) {
    lastChannelRef.current = channelId;
    channelSwitchScrollRef.current = true;
    isAtBottomRef.current = true;
  }

  function handleScroll() {
    const el = containerRef.current;
    if (!el) return;
    isAtBottomRef.current =
      el.scrollHeight - el.scrollTop - el.clientHeight < 80;

    if (el.scrollTop < 120 && hasMore && onLoadMore && !loading) {
      onLoadMore();
    }
  }

  useEffect(() => {
    const newLen = renderedCount;
    const grew = newLen > prevLenRef.current;
    prevLenRef.current = newLen;

    if (channelSwitchScrollRef.current) {
      channelSwitchScrollRef.current = false;
      bottomRef.current?.scrollIntoView();
      return;
    }
    if (grew && isAtBottomRef.current) {
      bottomRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [renderedCount]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView();
  }, []);

  // Scroll inline reply into view when reply target changes.
  useEffect(() => {
    if (!replyToId) return;
    const el = containerRef.current?.querySelector(
      `[data-msg-id="${CSS.escape(replyToId)}"]`,
    );
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [replyToId]);

  if (!loading && roots.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center text-zinc-400 text-sm">
        No messages yet. Start the conversation!
      </div>
    );
  }

  function renderNode(msg: Message, depth: number, prevRoot: Message | null) {
    const kids = childrenByParent.get(msg.msg_id) ?? [];
    const showDayLabel =
      depth === 0 &&
      (!prevRoot || !sameDay(prevRoot.created_at, msg.created_at));
    const isConsecutive =
      depth === 0 &&
      !showDayLabel &&
      !!prevRoot &&
      prevRoot.sender_id === msg.sender_id &&
      prevRoot.sender_type === msg.sender_type &&
      !prevRoot.is_deleted;
    const parentInView = !!(
      msg.reply_to_msg_id && byId.has(msg.reply_to_msg_id)
    );
    const focusRequestId =
      focusMsg &&
      (focusMsg.msgId === msg.msg_id ||
        (approvalsBySource.get(msg.msg_id) ?? []).some(
          (a) => a.msg_id === focusMsg.msgId,
        ))
        ? focusMsg.requestId ?? null
        : null;

    return (
      <div key={msg.msg_id}>
        {showDayLabel && (
          <div className="flex justify-center px-4 pt-8 pb-2">
            <span className="text-xs text-zinc-400 font-medium">
              {formatDayLabel(msg.created_at)}
            </span>
          </div>
        )}
        <div
          data-msg-id={msg.msg_id}
          style={ROW_CONTENT_VISIBILITY}
          className={
            msg.msg_id === highlightId
              ? "rounded-lg bg-indigo-500/10 ring-1 ring-inset ring-indigo-500/40 transition-colors duration-700"
              : "transition-colors duration-700"
          }
        >
          <MessageItem
            message={msg}
            isConsecutive={!!isConsecutive}
            nested={depth > 0}
            hideReplyQuote={parentInView}
            currentUserId={currentUserId}
            channelId={channelId}
            senderName={senderNames?.get(msg.sender_id)}
            actions={actions}
            selectMode={selectMode}
            selected={selectedIds?.has(msg.msg_id) ?? false}
            repliedTo={
              msg.reply_to_msg_id
                ? byId.get(msg.reply_to_msg_id) ?? null
                : null
            }
            nameOf={nameOf}
            pendingApprovals={approvalsBySource.get(msg.msg_id)}
            focusRequestId={focusRequestId}
          />
          {kids.length > 0 && (
            <div
              className={
                depth === 0
                  ? "ml-12 mr-4 border-l border-zinc-800/80 pl-3 space-y-0.5"
                  : "ml-4 border-l border-zinc-800/60 pl-2 space-y-0.5"
              }
            >
              {kids.map((child) => renderNode(child, depth + 1, null))}
            </div>
          )}
          {replyToId === msg.msg_id && inlineReply ? (
            <div className="ml-12 mr-4 mt-1 mb-2 rounded-lg border border-zinc-800 bg-zinc-950/80 px-2 py-2">
              {inlineReply}
            </div>
          ) : null}
        </div>
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      onScroll={handleScroll}
      className="chat-scrollbar flex-1 overflow-y-auto overscroll-contain py-2"
    >
      {loading && (
        <div className="flex justify-center py-4">
          <Spinner size={20} className="text-zinc-600" />
        </div>
      )}

      {roots.map((msg, i) => renderNode(msg, 0, i > 0 ? roots[i - 1]! : null))}
      <div ref={bottomRef} />
    </div>
  );
}
