import { useState } from "react";
import { ModelListSubPane } from "../models/ModelListSubPane";
import { TemplateListSubPane } from "../templates/TemplateListSubPane";
import { BotListSubPane } from "./BotListSubPane";
import type { BotRow } from "./types";

export type { BotRow } from "./types";

type BotSubTab = "bots" | "templates" | "models";

export function BotPane({
  bots,
  authToken,
  onChanged,
}: {
  bots: BotRow[];
  authToken: string | null;
  onChanged: () => void;
}) {
  const [tab, setTab] = useState<BotSubTab>("bots");

  return (
    <div className="an-pane">
      <div
        className="an-seg"
        style={{ marginBottom: 16, display: "inline-flex" }}
        role="tablist"
      >
        <button
          type="button"
          className={tab === "bots" ? "on" : ""}
          onClick={() => setTab("bots")}
          role="tab"
          aria-selected={tab === "bots"}
        >
          Bot
        </button>
        <button
          type="button"
          className={tab === "templates" ? "on" : ""}
          onClick={() => setTab("templates")}
          role="tab"
          aria-selected={tab === "templates"}
        >
          消息模板
        </button>
        <button
          type="button"
          className={tab === "models" ? "on" : ""}
          onClick={() => setTab("models")}
          role="tab"
          aria-selected={tab === "models"}
        >
          LLM 模型
        </button>
      </div>
      {tab === "bots" && (
        <BotListSubPane bots={bots} authToken={authToken} onChanged={onChanged} />
      )}
      {tab === "templates" && <TemplateListSubPane authToken={authToken} />}
      {tab === "models" && <ModelListSubPane authToken={authToken} />}
    </div>
  );
}
