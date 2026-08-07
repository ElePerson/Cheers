import { describe, expect, it } from "vitest";
import { groupMessagesByReply, messageSessionId } from "./messageTree";
import type { Message } from "@/types";

function msg(
  partial: Partial<Message> & Pick<Message, "msg_id" | "sender_id">,
): Message {
  return {
    sender_type: "user",
    content: "",
    ...partial,
  };
}

describe("groupMessagesByReply", () => {
  it("keeps messages without reply_to as roots", () => {
    const a = msg({ msg_id: "a", sender_id: "u1", channel_seq: 1 });
    const b = msg({ msg_id: "b", sender_id: "u2", channel_seq: 2 });
    const { roots, childrenByParent } = groupMessagesByReply([a, b]);
    expect(roots.map((m) => m.msg_id)).toEqual(["a", "b"]);
    expect(childrenByParent.size).toBe(0);
  });

  it("nests replies under their parent when parent is loaded", () => {
    const root = msg({ msg_id: "root", sender_id: "u1", channel_seq: 1 });
    const bot = msg({
      msg_id: "bot1",
      sender_id: "b1",
      sender_type: "bot",
      reply_to_msg_id: "root",
      channel_seq: 2,
    });
    const reply = msg({
      msg_id: "r1",
      sender_id: "u1",
      reply_to_msg_id: "bot1",
      channel_seq: 3,
    });
    const { roots, childrenByParent } = groupMessagesByReply([root, bot, reply]);
    expect(roots.map((m) => m.msg_id)).toEqual(["root"]);
    expect(childrenByParent.get("root")?.map((m) => m.msg_id)).toEqual(["bot1"]);
    expect(childrenByParent.get("bot1")?.map((m) => m.msg_id)).toEqual(["r1"]);
  });

  it("treats orphan replies as roots when parent is missing", () => {
    const orphan = msg({
      msg_id: "o1",
      sender_id: "u1",
      reply_to_msg_id: "missing",
      channel_seq: 1,
    });
    const { roots } = groupMessagesByReply([orphan]);
    expect(roots.map((m) => m.msg_id)).toEqual(["o1"]);
  });

  it("folds anchored permissions out of the tree", () => {
    const bot = msg({
      msg_id: "bot1",
      sender_id: "b1",
      sender_type: "bot",
      channel_seq: 1,
    });
    const perm = msg({
      msg_id: "p1",
      sender_id: "b1",
      sender_type: "bot",
      msg_type: "permission",
      content_data: { source_msg_id: "bot1", request_id: "req1" },
      channel_seq: 2,
    });
    const { roots, byId } = groupMessagesByReply([bot, perm]);
    expect(roots.map((m) => m.msg_id)).toEqual(["bot1"]);
    expect(byId.has("p1")).toBe(false);
  });
});

describe("messageSessionId", () => {
  it("reads session_id from content_data", () => {
    const m = msg({
      msg_id: "b",
      sender_id: "bot",
      content_data: { session_id: "sid-1" },
    });
    expect(messageSessionId(m)).toBe("sid-1");
  });

  it("returns null when absent", () => {
    expect(messageSessionId(msg({ msg_id: "b", sender_id: "bot" }))).toBeNull();
  });
});
