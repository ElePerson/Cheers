import { describe, expect, it } from "vitest";
import { resolvePlacement } from "./floating-layer";

describe("resolvePlacement", () => {
  it("keeps the preferred side when both sides are ample", () => {
    expect(resolvePlacement("down", 400, 400)).toBe("down");
    expect(resolvePlacement("up", 400, 400)).toBe("up");
  });

  it("flips down→up when space below is cramped and above is roomier", () => {
    expect(resolvePlacement("down", 500, 100)).toBe("up");
  });

  it("flips up→down when space above is cramped and below is roomier", () => {
    expect(resolvePlacement("up", 100, 500)).toBe("down");
  });

  it("stays preferred when the other side is not roomier", () => {
    expect(resolvePlacement("down", 80, 100)).toBe("down");
    expect(resolvePlacement("up", 100, 80)).toBe("up");
  });

  it("stays preferred when the preferred side is still comfortable", () => {
    expect(resolvePlacement("down", 800, 300)).toBe("down");
    expect(resolvePlacement("up", 300, 800)).toBe("up");
  });
});
