import type { TraceEvent } from "@/types";

export const TOOL_PRESENTATION_VERSION = 2;

export type ToolFamily = "file" | "shell" | "web" | "search" | "git";
export type ToolRisk = "read" | "write" | "network_read" | "network_write";
export type ToolEventType =
  | "file_read"
  | "file_edit"
  | "file_write"
  | "file_delete"
  | "file_move"
  | "file_access"
  | "shell_command"
  | "web_search"
  | "web_fetch"
  | "search_results"
  | "git_status"
  | "git_diff"
  | "git_show"
  | "git_log"
  | "git_commit"
  | "git_remote"
  | "git_command";

export interface ToolPresentation extends Record<string, unknown> {
  v: typeof TOOL_PRESENTATION_VERSION;
  event_type: ToolEventType;
  family: ToolFamily;
  operation: string;
  confidence: "explicit" | "pattern";
  matched_by: string;
  target?: string;
  path?: string;
  command?: string;
  query?: string;
  cwd?: string;
  args?: string;
  risk?: ToolRisk;
  compound?: boolean;
  result?: unknown;
}

export type GitFileState =
  | "staged"
  | "unstaged"
  | "untracked"
  | "conflicted"
  | "mixed";

export interface GitStatusFile {
  path: string;
  index: string;
  worktree: string;
  state: GitFileState;
}

export interface GitStatusResult {
  kind: "git_status";
  branch: string | null;
  clean: boolean;
  counts: {
    staged: number;
    unstaged: number;
    untracked: number;
    conflicted: number;
  };
  files: GitStatusFile[];
  truncated: boolean;
}

const FAMILIES = new Set<ToolFamily>(["file", "shell", "web", "search", "git"]);
const RISKS = new Set<ToolRisk>(["read", "write", "network_read", "network_write"]);
const EVENT_TYPES = new Set<ToolEventType>([
  "file_read", "file_edit", "file_write", "file_delete", "file_move", "file_access",
  "shell_command", "web_search", "web_fetch", "search_results", "git_status",
  "git_diff", "git_show", "git_log", "git_commit", "git_remote", "git_command",
]);
const GIT_FILE_STATES = new Set<GitFileState>([
  "staged",
  "unstaged",
  "untracked",
  "conflicted",
  "mixed",
]);

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

/**
 * Parse the Gateway-owned presentation descriptor once at the client boundary.
 * Components consume this typed result and never regex raw tool payloads.
 */
export function parseToolPresentation(value: unknown): ToolPresentation | null {
  const raw = asRecord(value);
  const eventType = optionalString(raw?.event_type) as ToolEventType | undefined;
  const family = optionalString(raw?.family) as ToolFamily | undefined;
  const operation = optionalString(raw?.operation);
  if (
    raw?.v !== TOOL_PRESENTATION_VERSION ||
    !eventType ||
    !EVENT_TYPES.has(eventType) ||
    !family ||
    !FAMILIES.has(family) ||
    !operation
  ) return null;

  const confidence = raw.confidence === "explicit" ? "explicit" : "pattern";
  const risk = optionalString(raw.risk) as ToolRisk | undefined;
  const parsed: ToolPresentation = {
    ...raw,
    v: TOOL_PRESENTATION_VERSION,
    event_type: eventType,
    family,
    operation,
    confidence,
    matched_by: optionalString(raw.matched_by) ?? "producer",
  };
  for (const key of ["target", "path", "command", "query", "cwd", "args"] as const) {
    const value = optionalString(raw[key]);
    if (value) parsed[key] = value;
    else delete parsed[key];
  }
  if (risk && RISKS.has(risk)) parsed.risk = risk;
  else delete parsed.risk;
  if (typeof raw.compound === "boolean") parsed.compound = raw.compound;
  else delete parsed.compound;
  return parsed;
}

export function toolPresentationFromTrace(
  event: Pick<TraceEvent, "data">,
): ToolPresentation | null {
  return parseToolPresentation(asRecord(event.data)?.presentation);
}

export function parseGitStatusResult(
  presentation: ToolPresentation | null,
): GitStatusResult | null {
  if (presentation?.event_type !== "git_status") {
    return null;
  }
  const raw = asRecord(presentation.result);
  const rawCounts = asRecord(raw?.counts);
  if (raw?.kind !== "git_status" || !rawCounts || !Array.isArray(raw.files)) return null;

  const files = raw.files.flatMap((value): GitStatusFile[] => {
    const file = asRecord(value);
    const path = optionalString(file?.path);
    const state = optionalString(file?.state) as GitFileState | undefined;
    if (!path || !state || !GIT_FILE_STATES.has(state)) return [];
    return [{
      path,
      state,
      index: typeof file?.index === "string" ? file.index : " ",
      worktree: typeof file?.worktree === "string" ? file.worktree : " ",
    }];
  });
  const count = (key: string) => {
    const value = rawCounts[key];
    return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
  };
  return {
    kind: "git_status",
    branch: optionalString(raw.branch) ?? null,
    clean: raw.clean === true,
    counts: {
      staged: count("staged"),
      unstaged: count("unstaged"),
      untracked: count("untracked"),
      conflicted: count("conflicted"),
    },
    files,
    truncated: raw.truncated === true,
  };
}
