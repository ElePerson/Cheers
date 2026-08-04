import { describe, expect, it } from "vitest";
import {
  parseGitStatusResult,
  parseToolPresentation,
  toolPresentationFromTrace,
} from "./toolPresentation";

describe("ToolPresentation v1", () => {
  it("parses one canonical file descriptor", () => {
    expect(parseToolPresentation({
      v: 2,
      event_type: "file_read",
      family: "file",
      operation: "read",
      confidence: "explicit",
      matched_by: "tool_name",
      path: "/repo/README.md",
    })).toMatchObject({
      family: "file",
      operation: "read",
      path: "/repo/README.md",
    });
  });

  it("rejects unknown versions and families", () => {
    expect(parseToolPresentation({ v: 1, event_type: "git_status", family: "git", operation: "status" })).toBeNull();
    expect(parseToolPresentation({ v: 2, event_type: "mystery", family: "git", operation: "status" })).toBeNull();
    expect(parseToolPresentation({ v: 2, event_type: "search_results", family: "calendar", operation: "list" })).toBeNull();
  });

  it("drops malformed optional routing hints", () => {
    expect(parseToolPresentation({
      v: 2,
      event_type: "git_remote",
      family: "git",
      operation: "push",
      risk: "delete_everything",
      compound: "yes",
      command: "   ",
    })).not.toHaveProperty("risk");
    expect(parseToolPresentation({
      v: 2,
      event_type: "git_remote",
      family: "git",
      operation: "push",
      risk: "delete_everything",
      compound: "yes",
      command: "   ",
    })).not.toHaveProperty("command");
  });

  it("reads the descriptor only from TraceEvent.data.presentation", () => {
    expect(toolPresentationFromTrace({
      data: {
        presentation: {
          v: 2,
          event_type: "shell_command",
          family: "shell",
          operation: "run",
        },
      },
    })).toMatchObject({ family: "shell", operation: "run" });
  });

  it("normalizes a git status result for every web surface", () => {
    const presentation = parseToolPresentation({
      v: 2,
      event_type: "git_status",
      family: "git",
      operation: "status",
      result: {
        kind: "git_status",
        branch: "feature/tool-presentation",
        clean: false,
        counts: { staged: 2, unstaged: 1, untracked: 1, conflicted: 0 },
        files: [{ path: "frontend/src/App.tsx", index: "M", worktree: " ", state: "staged" }],
        truncated: false,
      },
    });
    expect(parseGitStatusResult(presentation)).toMatchObject({
      branch: "feature/tool-presentation",
      counts: { staged: 2, unstaged: 1, untracked: 1, conflicted: 0 },
      files: [{ path: "frontend/src/App.tsx", state: "staged" }],
    });
  });
});
