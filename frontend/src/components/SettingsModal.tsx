import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { CurrentUser } from "../types";

type Density = "comfy" | "compact";
type AccentId = "indigo" | "teal" | "amber" | "rose" | "blue";

const ACCENTS: { id: AccentId; c: string; label: string }[] = [
  { id: "indigo", c: "#7c6cf5", label: "Indigo" },
  { id: "teal", c: "#3ecf8e", label: "Teal" },
  { id: "amber", c: "#f5a623", label: "Amber" },
  { id: "rose", c: "#f05478", label: "Rose" },
  { id: "blue", c: "#56a7ff", label: "Blue" },
];

const DENSITY_KEY = "agentnexus-density";
const ACCENT_KEY = "agentnexus-accent";

export function getStoredDensity(): Density {
  if (typeof window === "undefined") return "comfy";
  const v = localStorage.getItem(DENSITY_KEY);
  return v === "compact" ? "compact" : "comfy";
}

export function getStoredAccent(): AccentId {
  if (typeof window === "undefined") return "indigo";
  const v = localStorage.getItem(ACCENT_KEY) as AccentId | null;
  return ACCENTS.some((a) => a.id === v) ? (v as AccentId) : "indigo";
}

export function applyAccent(id: AccentId) {
  const hit = ACCENTS.find((a) => a.id === id) || ACCENTS[0];
  const root = document.documentElement.style;
  root.setProperty("--accent", hit.c);
  root.setProperty("--accent-hover", hit.c);
  root.setProperty("--accent-muted", hit.c + "24");
  root.setProperty("--accent-ring", hit.c + "66");
  root.setProperty("--border-focus", hit.c + "99");
}

export function applyDensity(d: Density) {
  document.documentElement.setAttribute("data-density", d);
}

interface SettingsModalProps {
  open: boolean;
  onClose: () => void;
  isDark: boolean;
  setTheme: (t: "light" | "dark") => void;

  currentUser: CurrentUser;
  onOpenUserProfile: () => void;
  onOpenKeychain: () => void;
  onOpenNotifications: () => void;
  onOpenFriends: () => void;
  onOpenQuickConnect: () => void;
  onOpenHelp: () => void;
  onLogout: () => void;
}

type Tab = "appearance" | "shortcuts" | "account" | "about";

export function SettingsModal({
  open,
  onClose,
  isDark,
  setTheme,
  currentUser,
  onOpenUserProfile,
  onOpenKeychain,
  onOpenNotifications,
  onOpenFriends,
  onOpenQuickConnect,
  onOpenHelp,
  onLogout,
}: SettingsModalProps) {
  const [tab, setTab] = useState<Tab>("appearance");
  const [density, setDensityState] = useState<Density>(() => getStoredDensity());
  const [accent, setAccentState] = useState<AccentId>(() => getStoredAccent());
  const navigate = useNavigate();

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  const changeDensity = (d: Density) => {
    setDensityState(d);
    localStorage.setItem(DENSITY_KEY, d);
    applyDensity(d);
  };

  const changeAccent = (id: AccentId) => {
    setAccentState(id);
    localStorage.setItem(ACCENT_KEY, id);
    applyAccent(id);
  };

  const go = (path: string) => {
    onClose();
    navigate(path);
  };

  const openAndClose = (fn: () => void) => {
    onClose();
    fn();
  };

  if (!open) return null;

  return (
    <div className="an-modal-overlay" onClick={onClose}>
      <div className="an-modal" onClick={(e) => e.stopPropagation()}>
        <div className="an-modal-head">
          <div className="an-modal-title">设置 · Settings</div>
          <button
            type="button"
            className="an-modal-close"
            onClick={onClose}
            aria-label="关闭"
          >
            ✕
          </button>
        </div>
        <div className="an-modal-body">
          <div className="an-settings-nav">
            <button
              type="button"
              className={`an-sn-item ${tab === "appearance" ? "on" : ""}`}
              onClick={() => setTab("appearance")}
            >
              <span className="an-sn-ico">◐</span> 外观
            </button>
            <button
              type="button"
              className={`an-sn-item ${tab === "shortcuts" ? "on" : ""}`}
              onClick={() => setTab("shortcuts")}
            >
              <span className="an-sn-ico">⌘</span> 快捷方式
            </button>
            <button
              type="button"
              className={`an-sn-item ${tab === "account" ? "on" : ""}`}
              onClick={() => setTab("account")}
            >
              <span className="an-sn-ico">◉</span> 账户
            </button>
            <button
              type="button"
              className={`an-sn-item ${tab === "about" ? "on" : ""}`}
              onClick={() => setTab("about")}
            >
              <span className="an-sn-ico">◎</span> 关于
            </button>
          </div>
          <div className="an-settings-pane">
            {tab === "appearance" && (
              <AppearancePane
                isDark={isDark}
                setTheme={setTheme}
                density={density}
                setDensity={changeDensity}
                accent={accent}
                setAccent={changeAccent}
              />
            )}
            {tab === "shortcuts" && (
              <ShortcutsPane
                onOpenNotifications={() => openAndClose(onOpenNotifications)}
                onOpenFriends={() => openAndClose(onOpenFriends)}
                onOpenKeychain={() => openAndClose(onOpenKeychain)}
                onOpenQuickConnect={() => openAndClose(onOpenQuickConnect)}
                onOpenHelp={() => openAndClose(onOpenHelp)}
                goAdmin={() => go("/admin")}
                goDocs={() => go("/docs")}
                goBulletin={() => go("/bulletin")}
              />
            )}
            {tab === "account" && (
              <AccountPane
                currentUser={currentUser}
                onOpenUserProfile={() => openAndClose(onOpenUserProfile)}
                onLogout={() => {
                  onClose();
                  onLogout();
                }}
              />
            )}
            {tab === "about" && <AboutPane />}
          </div>
        </div>
      </div>
    </div>
  );
}

function AppearancePane({
  isDark,
  setTheme,
  density,
  setDensity,
  accent,
  setAccent,
}: {
  isDark: boolean;
  setTheme: (t: "light" | "dark") => void;
  density: Density;
  setDensity: (d: Density) => void;
  accent: AccentId;
  setAccent: (id: AccentId) => void;
}) {
  return (
    <div>
      <div className="an-pane-head">
        <div>
          <div className="an-pane-title">外观</div>
          <div className="an-pane-sub">主题、密度与主色。</div>
        </div>
      </div>
      <div className="an-list-table">
        <div className="an-row-card" style={{ justifyContent: "space-between" }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="an-rc-title">主题</div>
            <div className="an-rc-sub">整体亮度。</div>
          </div>
          <div className="an-seg">
            <button
              type="button"
              className={isDark ? "on" : ""}
              onClick={() => setTheme("dark")}
            >
              深色
            </button>
            <button
              type="button"
              className={!isDark ? "on" : ""}
              onClick={() => setTheme("light")}
            >
              浅色
            </button>
          </div>
        </div>
        <div className="an-row-card" style={{ justifyContent: "space-between" }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="an-rc-title">密度</div>
            <div className="an-rc-sub">消息间距。</div>
          </div>
          <div className="an-seg">
            <button
              type="button"
              className={density === "comfy" ? "on" : ""}
              onClick={() => setDensity("comfy")}
            >
              舒适
            </button>
            <button
              type="button"
              className={density === "compact" ? "on" : ""}
              onClick={() => setDensity("compact")}
            >
              紧凑
            </button>
          </div>
        </div>
        <div className="an-row-card" style={{ justifyContent: "space-between" }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="an-rc-title">主色</div>
            <div className="an-rc-sub">按钮、高亮与链接的主色。</div>
          </div>
          <div className="an-swatch-row">
            {ACCENTS.map((a) => (
              <button
                key={a.id}
                type="button"
                className={`an-sw ${accent === a.id ? "on" : ""}`}
                style={{ background: a.c }}
                onClick={() => setAccent(a.id)}
                aria-label={a.label}
                title={a.label}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function ShortcutRow({
  ico,
  title,
  sub,
  action,
  onClick,
  danger,
}: {
  ico: string;
  title: string;
  sub?: string;
  action: string;
  onClick: () => void;
  danger?: boolean;
}) {
  return (
    <button
      type="button"
      className="an-row-card"
      style={{
        width: "100%",
        textAlign: "left",
        cursor: "pointer",
        fontFamily: "inherit",
      }}
      onClick={onClick}
    >
      <span
        className="an-mi-ico"
        style={{
          width: 28,
          height: 28,
          borderRadius: 7,
          background: "var(--surface-soft)",
          color: danger ? "var(--red)" : "var(--accent)",
          fontSize: 14,
          flexShrink: 0,
        }}
      >
        {ico}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          className="an-rc-title"
          style={{ color: danger ? "var(--red)" : "var(--fg-1)" }}
        >
          {title}
        </div>
        {sub && <div className="an-rc-sub">{sub}</div>}
      </div>
      <span
        style={{
          color: "var(--fg-3)",
          fontSize: 12,
          flexShrink: 0,
        }}
      >
        {action} ›
      </span>
    </button>
  );
}

function ShortcutsPane({
  onOpenNotifications,
  onOpenFriends,
  onOpenKeychain,
  onOpenQuickConnect,
  onOpenHelp,
  goAdmin,
  goDocs,
  goBulletin,
}: {
  onOpenNotifications: () => void;
  onOpenFriends: () => void;
  onOpenKeychain: () => void;
  onOpenQuickConnect: () => void;
  onOpenHelp: () => void;
  goAdmin: () => void;
  goDocs: () => void;
  goBulletin: () => void;
}) {
  return (
    <div>
      <div className="an-pane-head">
        <div>
          <div className="an-pane-title">快捷方式</div>
          <div className="an-pane-sub">
            从侧栏移入此处的常用入口。
          </div>
        </div>
      </div>
      <div className="an-list-table">
        <ShortcutRow
          ico="◉"
          title="通知消息"
          sub="Bot 回复、提及、审批请求"
          action="打开"
          onClick={onOpenNotifications}
        />
        <ShortcutRow
          ico="◎"
          title="好友"
          sub="联系人与跨工作空间私信"
          action="打开"
          onClick={onOpenFriends}
        />
        <ShortcutRow
          ico="⌘"
          title="密钥链"
          sub="管理插入到消息里的 $secret{...}"
          action="管理"
          onClick={onOpenKeychain}
        />
        <ShortcutRow
          ico="⚡"
          title="接入 OpenClaw"
          sub="快速连接外部 Bot / 代理"
          action="配置"
          onClick={onOpenQuickConnect}
        />
        <ShortcutRow
          ico="⚙"
          title="管理后台"
          sub="模型、提示词、工作空间、Bot、日志"
          action="前往"
          onClick={goAdmin}
        />
        <ShortcutRow
          ico="📄"
          title="文档"
          sub="使用说明与集成文档"
          action="打开"
          onClick={goDocs}
        />
        <ShortcutRow
          ico="💬"
          title="留言板"
          sub="内部反馈与变更记录"
          action="打开"
          onClick={goBulletin}
        />
        <ShortcutRow
          ico="?"
          title="帮助"
          sub="常见问题与键盘快捷键"
          action="查看"
          onClick={onOpenHelp}
        />
      </div>
    </div>
  );
}

function AccountPane({
  currentUser,
  onOpenUserProfile,
  onLogout,
}: {
  currentUser: CurrentUser;
  onOpenUserProfile: () => void;
  onLogout: () => void;
}) {
  const initial = currentUser?.display_name?.slice(0, 1)?.toUpperCase() || "?";
  return (
    <div>
      <div className="an-pane-head">
        <div>
          <div className="an-pane-title">账户</div>
          <div className="an-pane-sub">当前登录信息与个人设置。</div>
        </div>
      </div>
      <div className="an-list-table">
        <div className="an-row-card">
          <span
            className="an-mi-ico"
            style={{
              width: 36,
              height: 36,
              borderRadius: 8,
              background: "var(--accent)",
              color: "#fff",
              fontWeight: 700,
              fontSize: 14,
              flexShrink: 0,
            }}
          >
            {initial}
          </span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="an-rc-title">
              {currentUser?.display_name || "未登录"}
            </div>
            <div className="an-rc-sub">
              {currentUser?.user_id
                ? `UUID · ${currentUser.user_id}`
                : "登录以同步你的工作空间与记忆"}
            </div>
          </div>
          {currentUser && (
            <button
              type="button"
              className="an-sn-item"
              style={{
                width: "auto",
                padding: "6px 12px",
                border: "1px solid var(--border)",
              }}
              onClick={onOpenUserProfile}
            >
              编辑资料
            </button>
          )}
        </div>
        {currentUser && (
          <ShortcutRow
            ico="↗"
            title="退出登录"
            sub="清除本地令牌并返回登录界面"
            action="执行"
            onClick={onLogout}
            danger
          />
        )}
      </div>
    </div>
  );
}

function AboutPane() {
  return (
    <div>
      <div className="an-pane-head">
        <div>
          <div className="an-pane-title">关于</div>
          <div className="an-pane-sub">AgentNexus · 智枢协作平台</div>
        </div>
      </div>
      <div className="an-list-table">
        <div className="an-row-card">
          <div style={{ flex: 1 }}>
            <div className="an-rc-title">设计系统</div>
            <div className="an-rc-sub">
              Haowei / Parallel — 深色底、indigo 主色、紧凑栅格。
            </div>
          </div>
        </div>
        <div className="an-row-card">
          <div style={{ flex: 1 }}>
            <div className="an-rc-title">反馈与问题</div>
            <div className="an-rc-sub">
              通过「留言板」或管理后台提交反馈。
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
