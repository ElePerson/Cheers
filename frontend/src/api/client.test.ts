import { describe, expect, it } from "vitest";
import { errorMessage } from "./client";

describe("errorMessage", () => {
  it("preserves Error messages", () => {
    expect(errorMessage(new Error("Server rejected the handoff"), "fallback"))
      .toBe("Server rejected the handoff");
  });

  it("preserves plain-string Tauri command errors", () => {
    expect(errorMessage("Could not reach the Cheers server", "fallback"))
      .toBe("Could not reach the Cheers server");
  });

  it("uses the fallback for unsafe or empty values", () => {
    expect(errorMessage({ detail: "secret" }, "OAuth login failed"))
      .toBe("OAuth login failed");
    expect(errorMessage("   ", "OAuth login failed")).toBe("OAuth login failed");
  });
});
