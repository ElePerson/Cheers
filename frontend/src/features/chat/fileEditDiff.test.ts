import { describe, expect, it } from "vitest";
import {
  aggregateDiffStats,
  diffStats,
  fileDiffPreview,
  fileDiffsFromData,
  formatDiffDelta,
  pathBasename,
} from "./fileEditDiff";

describe("fileDiffsFromData", () => {
  it("keeps only real content diffs and skips identical sides", () => {
    const diffs = fileDiffsFromData({
      content: [
        { type: "diff", path: "/work/a.ts", oldText: "a\n", newText: "A\n" },
        { type: "diff", path: "/work/same.ts", oldText: "s\n", newText: "s\n" },
        { type: "text", text: "ignore me" },
      ],
    });
    expect(diffs).toEqual([
      { path: "/work/a.ts", oldText: "a\n", newText: "A\n" },
    ]);
  });
});

describe("fileDiffPreview", () => {
  it("emits a context hunk instead of dumping the whole file", () => {
    const head = Array.from({ length: 12 }, (_, i) => `head${i}`);
    const tail = Array.from({ length: 12 }, (_, i) => `tail${i}`);
    const oldText = [...head, "MARKER = before", ...tail].join("\n");
    const newText = oldText.replace("before", "after");
    const preview = fileDiffPreview({
      path: "/work/big.ts",
      oldText,
      newText,
    });
    expect(preview).toContain("diff --git a//work/big.ts b//work/big.ts");
    expect(preview).toContain("-MARKER = before");
    expect(preview).toContain("+MARKER = after");
    // Far-away unchanged lines stay out of the hunk.
    expect(preview).not.toContain(" head0\n");
    expect(preview).not.toContain(" tail11");
    // Nearby context is kept.
    expect(preview).toContain(" head11");
    expect(preview).toContain(" tail0");
  });

  it("reports stats for additions and deletions", () => {
    const stats = diffStats({
      path: "a.ts",
      oldText: "a\nb\n",
      newText: "a\nc\n",
    });
    expect(stats).toEqual({ additions: 1, deletions: 1 });
    expect(formatDiffDelta(aggregateDiffStats([{
      path: "a.ts",
      oldText: "a\nb\n",
      newText: "a\nc\nd\n",
    }]))).toBe("+2 −1");
  });
});

describe("pathBasename", () => {
  it("strips directory prefixes", () => {
    expect(pathBasename("/work/src/MessageItem.tsx")).toBe("MessageItem.tsx");
    expect(pathBasename("MessageItem.tsx")).toBe("MessageItem.tsx");
  });
});
