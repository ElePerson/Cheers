import type { BotRow, BotScope } from "./types";

const BOT_SCOPE_OPTIONS: { value: BotScope; label: string; hint: string }[] = [
  { value: "private", label: "Private", hint: "仅自己可发起私信或邀请" },
  { value: "friend", label: "Friend", hint: "自己和好友可发起私信或邀请" },
  { value: "everyone", label: "Everyone", hint: "所有用户可发起私信或邀请" },
];

export function normalizeBotScope(scope?: string | null): BotScope {
  if (scope === "private" || scope === "friend" || scope === "everyone") return scope;
  return "friend";
}

export function botScopeLabel(scope?: string | null) {
  const normalized = normalizeBotScope(scope);
  const found = BOT_SCOPE_OPTIONS.find((x) => x.value === normalized);
  return found?.label || "Friend";
}

export function botOwnerLabel(bot: Pick<BotRow, "owner" | "created_by">) {
  return bot.owner?.display_name || bot.owner?.username || bot.created_by || "系统";
}

export function BotScopeControl({
  value,
  onChange,
  disabled = false,
}: {
  value: BotScope;
  onChange: (scope: BotScope) => void;
  disabled?: boolean;
}) {
  const current = BOT_SCOPE_OPTIONS.find((opt) => opt.value === value) || BOT_SCOPE_OPTIONS[1];
  return (
    <div style={{ display: "grid", gap: 6 }}>
      <div
        className="an-seg"
        role="radiogroup"
        aria-label="Bot 使用范围"
        style={{ display: "inline-flex", justifySelf: "start" }}
      >
        {BOT_SCOPE_OPTIONS.map((opt) => (
          <button
            key={opt.value}
            type="button"
            className={value === opt.value ? "on" : ""}
            onClick={() => onChange(opt.value)}
            disabled={disabled}
            role="radio"
            aria-checked={value === opt.value}
          >
            {opt.label}
          </button>
        ))}
      </div>
      <div className="an-rc-sub" style={{ marginTop: 0 }}>
        {current.hint}
      </div>
    </div>
  );
}

function botOnlineMeta(bot: BotRow) {
  if (bot.is_builtin) {
    const online = bot.is_online !== false && bot.status !== "offline";
    return {
      label: online ? "内置已启用" : "已停用",
      color: online ? "var(--green)" : "var(--fg-3)",
      bg: online ? "var(--green-muted)" : "var(--surface-soft)",
      title: online ? "内置 Bot 使用专用 adapter，不依赖 Bot 的 LLM 绑定" : "Bot 状态为 offline",
    };
  }
  const isWs = (bot.binding_type || "http") === "agent_bridge";
  if (!isWs) {
    const online = bot.is_online !== false && bot.status !== "offline";
    return {
      label: online ? "HTTP 已启用" : "已停用",
      color: online ? "var(--green)" : "var(--fg-3)",
      bg: online ? "var(--green-muted)" : "var(--surface-soft)",
      title: online ? "HTTP Bot 无需长连接；可点击测试连通验证模型 API" : "Bot 状态为 offline",
    };
  }
  if (bot.connection_status === "online" && bot.is_online) {
    return {
      label: "Bridge 在线",
      color: "var(--green)",
      bg: "var(--green-muted)",
      title: "control/data 连接均在线",
    };
  }
  if (bot.connection_status === "partial") {
    return {
      label: "Bridge 部分连接",
      color: "var(--yellow)",
      bg: "rgba(251, 191, 36, 0.16)",
      title: `control: ${bot.control_connected ? "在线" : "离线"} · data: ${bot.data_connected ? "在线" : "离线"}`,
    };
  }
  return {
    label: "Bridge 离线",
    color: "var(--red)",
    bg: "var(--red-muted)",
    title: "Agent Bridge provider 未连接",
  };
}

export function BotOnlineBadge({ bot }: { bot: BotRow }) {
  const meta = botOnlineMeta(bot);
  return (
    <span
      title={meta.title}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 5,
        padding: "3px 7px",
        borderRadius: 999,
        background: meta.bg,
        color: meta.color,
        fontSize: 11,
        fontWeight: 650,
        whiteSpace: "nowrap",
      }}
    >
      <span
        style={{
          width: 6,
          height: 6,
          borderRadius: 999,
          background: meta.color,
          flexShrink: 0,
        }}
      />
      {meta.label}
    </span>
  );
}
