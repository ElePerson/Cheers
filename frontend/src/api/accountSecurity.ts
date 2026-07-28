import { apiJson } from "./client";

export interface AuthSessionSummary {
  session_id: string;
  client: string;
  device_name: string | null;
  authenticated_at: string;
  last_seen_at: string;
  expires_at: string;
  current: boolean;
}

export async function listAuthSessions(): Promise<AuthSessionSummary[]> {
  return apiJson("/auth/sessions");
}

export async function revokeAuthSession(sessionId: string): Promise<void> {
  await apiJson(`/auth/sessions/${sessionId}`, { method: "DELETE" });
}

export interface StoredAIConsent {
  channel_id: string;
  channel_name: string;
  bot_id: string;
  bot_name: string;
  provider_name: string | null;
  privacy_url: string | null;
  data_use: string | null;
  policy_version: string;
}

export async function listAIConsents(): Promise<StoredAIConsent[]> {
  return apiJson("/users/me/ai-consents");
}

export async function revokeAIConsent(
  channelId: string,
  botId: string
): Promise<void> {
  await apiJson(`/channels/${channelId}/bots/${botId}/ai-consent`, {
    method: "DELETE",
  });
}
