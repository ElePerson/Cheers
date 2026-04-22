/**
 * outbound.sendMedia + sendText drain 行为单测。
 *
 * 模拟 OpenClaw gateway 的调用序列：
 *   1. gateway 抽 MEDIA 行 → 对每个媒体文件调 plugin.sendMedia({ to, filePath })
 *   2. gateway 把清洗后文本调 plugin.sendText({ to, text })
 * 预期 sendText 调用 session.reply / session.send 时带上 sendMedia 攒下的 file_ids。
 */
import { writeFile, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { __testonly } from "../src/plugin.js";
import type { InboundMessage } from "../src/session.js";

const { sessionRegistry, sendText, sendMedia, pendingMediaByTo } = __testonly;

const ACCOUNT_ID = "acc-test";
const BOT_TOKEN = "ocw_test_token";
const DATA_URL = "ws://127.0.0.1:0/ws/openclaw/data";  // 只用来推导 httpBase

function fakeInbound(taskId: string, channelId: string): InboundMessage {
  return {
    channelId,
    text: "hi",
    attachments: [],
    event: {
      type: "message",
      task_id: taskId,
      bot_id: "bot-x",
      channel_id: channelId,
      placeholder_msg_id: `ph-${taskId}`,
      trigger_message: { user: "u1", text: "@ws-bot do it", timestamp: "2026-04-21T00:00:00Z" },
      memory_context: {},
      attachments: [],
      binding_config: {},
    } as unknown as InboundMessage["event"],
  };
}

interface FakeSession {
  reply: ReturnType<typeof vi.fn>;
  send: ReturnType<typeof vi.fn>;
  membership: { channelIds: Set<string> };
}

function installFakeEntry(taskId: string, channelId: string): FakeSession {
  const inbound = fakeInbound(taskId, channelId);
  const session: FakeSession = {
    reply: vi.fn(async () => ({ ok: true, messageId: "msg-reply" })),
    send: vi.fn(async () => ({ ok: true, messageId: "msg-send" })),
    membership: { channelIds: new Set([channelId]) },
  };
  sessionRegistry.set(ACCOUNT_ID, {
    // 只填 sendMedia / sendText 路径真正读到的字段；其余断言用不到。
    session: session as never,
    account: {
      accountId: ACCOUNT_ID,
      enabled: true,
      botToken: BOT_TOKEN,
      controlUrl: DATA_URL,
      dataUrl: DATA_URL,
      advanced: {
        reconnectBaseMs: 1000,
        reconnectMaxMs: 30000,
        heartbeatIntervalMs: 30000,
        sendAckTimeoutMs: 10000,
      },
      allowFrom: [],
    },
    lastInboundBySessionKey: new Map([[`agentnexus:${ACCOUNT_ID}:${channelId}`, inbound]]),
    lastInboundByTaskId: new Map([[taskId, inbound]]),
    bindingStore: new Map(),
    bindingAdapter: {} as never,
  });
  return session;
}

describe("outbound.sendMedia + sendText drain", () => {
  let originalFetch: typeof globalThis.fetch;
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
    fetchMock = vi.fn();
    globalThis.fetch = fetchMock as unknown as typeof fetch;
    sessionRegistry.clear();
    pendingMediaByTo.clear();
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    sessionRegistry.clear();
    pendingMediaByTo.clear();
  });

  it("uploads local file and attaches file_id on subsequent sendText", async () => {
    const session = installFakeEntry("task-1", "C1");

    // 准备一个真实本地文件给 readMediaSource 读
    const dir = await mkdtemp(join(tmpdir(), "agentnexus-media-"));
    const filePath = join(dir, "chart.png");
    const payload = Buffer.from("\x89PNG\r\n\x1a\npayload");
    await writeFile(filePath, payload);

    // bridge upload-binary 的 fetch 响应
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ data: { file_id: "f-media-1" } }),
    } as Response);

    await sendMedia({
      to: "task-1", filePath, contentType: "image/png", accountId: ACCOUNT_ID,
    });

    // fetch 被调用：正确的 URL / header / body
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toMatch(/\/api\/v1\/openclaw\/bridge\/files\/upload-binary$/);
    const headers = init.headers as Record<string, string>;
    expect(headers["Authorization"]).toBe(`Bearer ${BOT_TOKEN}`);
    expect(headers["Content-Type"]).toBe("image/png");
    expect(headers["X-Channel-Id"]).toBe("C1");
    expect(headers["X-Filename"]).toBe("chart.png");
    expect(init.method).toBe("POST");

    // pendingMedia 里应有 f-media-1
    expect(pendingMediaByTo.get("task-1")?.fileIds).toEqual(["f-media-1"]);
    // 还没触发 session.reply —— drain 只在 sendText 时发生
    expect(session.reply).not.toHaveBeenCalled();

    // 现在 sendText 触发 drain
    await sendText({ to: "task-1", text: "这是图", accountId: ACCOUNT_ID });
    expect(session.reply).toHaveBeenCalledTimes(1);
    const replyArg = session.reply.mock.calls[0][0];
    expect(replyArg.text).toBe("这是图");
    expect(replyArg.fileIds).toEqual(["f-media-1"]);
    // pending 清空
    expect(pendingMediaByTo.get("task-1")).toBeUndefined();
  });

  it("accumulates multiple sendMedia calls and drains them all on sendText", async () => {
    const session = installFakeEntry("task-2", "C1");

    const dir = await mkdtemp(join(tmpdir(), "agentnexus-media-"));
    const f1 = join(dir, "a.png"); await writeFile(f1, "a");
    const f2 = join(dir, "b.pdf"); await writeFile(f2, "b");

    fetchMock.mockResolvedValueOnce({
      ok: true, status: 200, json: async () => ({ data: { file_id: "f-A" } }),
    } as Response);
    fetchMock.mockResolvedValueOnce({
      ok: true, status: 200, json: async () => ({ data: { file_id: "f-B" } }),
    } as Response);

    await sendMedia({ to: "task-2", filePath: f1, contentType: "image/png", accountId: ACCOUNT_ID });
    await sendMedia({ to: "task-2", filePath: f2, contentType: "application/pdf", accountId: ACCOUNT_ID });

    expect(pendingMediaByTo.get("task-2")?.fileIds).toEqual(["f-A", "f-B"]);

    await sendText({ to: "task-2", text: "两个文件", accountId: ACCOUNT_ID });
    expect(session.reply).toHaveBeenCalledTimes(1);
    expect(session.reply.mock.calls[0][0].fileIds).toEqual(["f-A", "f-B"]);
  });

  it("skips sendMedia silently when upload fails (no file_id buffered)", async () => {
    installFakeEntry("task-3", "C1");

    const dir = await mkdtemp(join(tmpdir(), "agentnexus-media-"));
    const filePath = join(dir, "bad.png"); await writeFile(filePath, "bad");

    fetchMock.mockResolvedValueOnce({
      ok: false, status: 500, json: async () => ({}),
    } as Response);

    await sendMedia({ to: "task-3", filePath, accountId: ACCOUNT_ID });
    expect(pendingMediaByTo.get("task-3")).toBeUndefined();
  });

  it("downloads URL refs and uploads the body", async () => {
    installFakeEntry("task-4", "C1");

    // 1) fetch URL 下载 2) fetch bridge upload-binary
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      headers: new Map([["content-type", "application/pdf"]]) as unknown as Headers,
      arrayBuffer: async () => new ArrayBuffer(42),
    } as unknown as Response);
    fetchMock.mockResolvedValueOnce({
      ok: true, status: 200, json: async () => ({ data: { file_id: "f-url" } }),
    } as Response);

    await sendMedia({
      to: "task-4", filePath: "https://example.com/report.pdf", accountId: ACCOUNT_ID,
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    // 第二次调用是 upload-binary；X-Filename 应为 URL 末段
    const [, uploadInit] = fetchMock.mock.calls[1] as [string, RequestInit];
    const uploadHeaders = uploadInit.headers as Record<string, string>;
    expect(uploadHeaders["X-Filename"]).toBe("report.pdf");
    expect(uploadHeaders["Content-Type"]).toBe("application/pdf");
    expect(pendingMediaByTo.get("task-4")?.fileIds).toEqual(["f-url"]);
  });

  it("sendText without preceding sendMedia sends no file_ids", async () => {
    const session = installFakeEntry("task-5", "C1");

    await sendText({ to: "task-5", text: "纯文本", accountId: ACCOUNT_ID });
    expect(session.reply).toHaveBeenCalledTimes(1);
    const arg = session.reply.mock.calls[0][0];
    expect(arg.text).toBe("纯文本");
    expect(arg.fileIds).toBeUndefined();
  });

  it("orphan sendMedia flushes via session.reply after debounce when no sendText follows", async () => {
    vi.useFakeTimers();
    try {
      const session = installFakeEntry("task-6", "C1");

      const dir = await mkdtemp(join(tmpdir(), "agentnexus-media-"));
      const filePath = join(dir, "orphan.png"); await writeFile(filePath, "x");

      fetchMock.mockResolvedValueOnce({
        ok: true, status: 200, json: async () => ({ data: { file_id: "f-orphan" } }),
      } as Response);

      await sendMedia({ to: "task-6", filePath, accountId: ACCOUNT_ID });
      expect(session.reply).not.toHaveBeenCalled();

      // debounce 阈值是 3000ms
      await vi.advanceTimersByTimeAsync(3100);

      expect(session.reply).toHaveBeenCalledTimes(1);
      const arg = session.reply.mock.calls[0][0];
      expect(arg.text).toBe("");
      expect(arg.fileIds).toEqual(["f-orphan"]);
      expect(pendingMediaByTo.get("task-6")).toBeUndefined();
    } finally {
      vi.useRealTimers();
    }
  });
});
