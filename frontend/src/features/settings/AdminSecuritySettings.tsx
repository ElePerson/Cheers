import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import toast from "react-hot-toast";
import { Shield } from "lucide-react";
import { useIsAdmin } from "@/stores/authStore";
import {
  getSecuritySettings,
  putSecuritySettings,
  type SecuritySettings,
} from "@/api/adminSettings";

// Admin-only: controls whether remote agent access requires TOTP 2FA.
export function AdminSecuritySettings() {
  const isAdmin = useIsAdmin();
  const [require2fa, setRequire2fa] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!isAdmin) return;
    getSecuritySettings()
      .then((s) => {
        setRequire2fa(s.require_2fa_for_remote_agent_access);
        setLoaded(true);
      })
      .catch((e) =>
        toast.error(e instanceof Error ? e.message : "Failed to load security settings")
      );
  }, [isAdmin]);

  if (!isAdmin) return null;

  async function save() {
    setBusy(true);
    try {
      const s = await putSecuritySettings({
        require_2fa_for_remote_agent_access: require2fa,
      });
      setRequire2fa(s.require_2fa_for_remote_agent_access);
      toast.success("Security settings saved");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to save");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <h2 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-4 flex items-center gap-2">
        <Shield className="w-3.5 h-3.5" />
        Security
      </h2>

      <div className="bg-zinc-900 rounded-2xl p-6">
        <div className="grid gap-3 max-w-lg">
          <label className="flex items-center gap-2 text-sm text-zinc-200">
            <input
              type="checkbox"
              checked={require2fa}
              onChange={(e) => setRequire2fa(e.target.checked)}
              disabled={!loaded || busy}
              className="h-4 w-4 accent-indigo-500"
            />
            Require 2FA for remote agent access
          </label>

          <p className="text-xs text-zinc-400">
            When enabled, users must set up TOTP two-factor authentication before
            they can create a bot or start a bot session.
          </p>

          <div className="flex items-center gap-2 pt-1">
            <Button onClick={() => void save()} disabled={busy || !loaded}>
              {busy ? "Saving…" : "Save"}
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
