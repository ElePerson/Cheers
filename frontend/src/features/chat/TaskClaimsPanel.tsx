import { useCallback, useEffect, useState } from "react";
import { Bot, Check, X } from "lucide-react";
import toast from "react-hot-toast";
import {
  cancelTaskClaim,
  listTaskClaims,
  resolveTaskClaim,
  type TaskClaim,
} from "@/api/taskClaims";
import { Button } from "@/components/ui/button";

export function TaskClaimsPanel({
  channelId,
  canManage,
  refreshKey = 0,
}: {
  channelId: string;
  canManage: boolean;
  refreshKey?: number;
}) {
  const [claims, setClaims] = useState<TaskClaim[]>([]);
  const [busy, setBusy] = useState("");
  const refresh = useCallback(
    () => listTaskClaims(channelId, "pending").then(setClaims).catch(() => {}),
    [channelId],
  );
  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), 10_000);
    return () => window.clearInterval(timer);
  }, [refresh]);
  useEffect(() => {
    void refresh();
  }, [refresh, refreshKey]);

  if (!claims.length) return null;

  const resolve = async (c: TaskClaim, decision: "accept" | "reject") => {
    setBusy(c.claim_id);
    try {
      await resolveTaskClaim(channelId, c.claim_id, decision);
      setClaims((v) => v.filter((x) => x.claim_id !== c.claim_id));
      toast.success(
        decision === "accept"
          ? `${c.bot_name} started the task`
          : "Claim rejected",
      );
    } catch (e) {
      toast.error(
        e instanceof Error ? e.message : "Could not resolve claim",
      );
      await refresh();
    } finally {
      setBusy("");
    }
  };

  const cancel = async (c: TaskClaim) => {
    setBusy(c.claim_id);
    try {
      await cancelTaskClaim(channelId, c.claim_id);
      setClaims((v) => v.filter((x) => x.claim_id !== c.claim_id));
      toast.success("Claim cancelled");
    } catch (e) {
      toast.error(
        e instanceof Error ? e.message : "Could not cancel claim",
      );
    } finally {
      setBusy("");
    }
  };

  return (
    <div className="mx-4 mb-2 max-h-72 space-y-2 overflow-y-auto">
      <p className="px-1 text-[11px] font-semibold uppercase tracking-wide text-indigo-300/80">
        Task claim requests · {claims.length}
      </p>
      {claims.map((c) => (
        <div
          key={c.claim_id}
          className="flex max-w-[92%] gap-2 rounded-2xl rounded-tl-md border border-indigo-500/30 bg-indigo-500/10 px-3 py-2.5 shadow-sm"
        >
          <Bot className="mt-0.5 h-4 w-4 shrink-0 text-indigo-400" />
          <div className="min-w-0 flex-1">
            <p className="text-[11px] font-medium text-indigo-300">{c.bot_name} wants to claim a task</p>
            <p className="mt-0.5 text-sm font-medium text-zinc-100">{c.summary}</p>
            <p className="mt-1 text-xs leading-relaxed text-zinc-400">{c.proposed_action}</p>
            <p className="mt-1 text-[11px] text-zinc-500">
              {Math.round(c.confidence * 100)}% confidence · {c.impact} impact
            </p>
            {canManage && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                <Button
                  size="sm"
                  variant="secondary"
                  className="h-7 px-2 text-xs"
                  disabled={busy === c.claim_id}
                  onClick={() => void cancel(c)}
                >
                  <X className="h-3 w-3" />
                  Cancel
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  className="h-7 px-2 text-xs"
                  disabled={busy === c.claim_id}
                  onClick={() => void resolve(c, "reject")}
                >
                  <X className="h-3 w-3" />
                  Reject
                </Button>
                <Button
                  size="sm"
                  className="h-7 px-2 text-xs"
                  loading={busy === c.claim_id}
                  onClick={() => void resolve(c, "accept")}
                >
                  <Check className="h-3 w-3" />
                  Approve &amp; run
                </Button>
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
