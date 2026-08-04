# Tool Presentation Contract

> Status: v1 implemented in the Gateway and the shared Web/macOS trace panel.
> iOS is the next consumer and must reuse this descriptor without porting the
> classifier regexes.

ACP agents expose tool calls with different names and payload shapes. Rendering
`rawInput` and `rawOutput` as generic JSON loses the important part of the action,
especially for Git. Cheers therefore adds a small presentation descriptor under
`TraceEvent.data.presentation`.

## Design rules

1. **Structured producer data wins.** A connector or agent may send
   `data.presentation` directly. The Gateway never replaces it.
2. **The Gateway is the compatibility boundary.** For older producers it derives
   the descriptor once, before live fan-out and again during durable replay. All
   clients therefore consume the same classification.
3. **Regular expressions classify; they do not execute or authorize.** Matching
   changes display only. Permission policy continues to use the original ACP
   tool call and full command.
4. **Unknown calls remain inspectable.** Clients fall back to raw input/output.
5. **The original command is never hidden.** Compound shell commands are marked
   with `compound: true` and always show the complete command.

No database migration is required: the descriptor lives inside the existing
JSON `data` field, and old rows are enriched by the read-time normalizer.

## v1 shape

```json
{
  "v": 1,
  "family": "git",
  "operation": "commit",
  "renderer": "git_commit",
  "target": "-m 'Improve tool traces'",
  "command": "git commit -m 'Improve tool traces'",
  "cwd": "/repo",
  "risk": "write",
  "compound": false,
  "confidence": "pattern",
  "matched_by": "command.git"
}
```

Stable routing fields are `v`, `family`, `operation`, and `renderer`. The other
fields are optional display hints. Clients must ignore unknown additive fields.

### Families and initial renderers

| Family | Operations | Renderers |
| --- | --- | --- |
| `file` | `read`, `edit`, `write`, `access` | `file_read`, `diff`, `file_write`, `file` |
| `shell` | `run` | `terminal` |
| `web` | `search` | `web_search` |
| `search` | `grep`, `glob`, `find_files` | `search_results` |
| `git` | `status`, `diff`, `show`, `log`, `commit`, `add`, `push`, `pull`, `fetch`, `branch`, and other common verbs | operation-specific Git renderers or `git_command` |

Git also carries a display-only `risk`: `read`, `write`, `network_read`, or
`network_write`. This is not a security verdict.

## Matching pipeline

```text
producer presentation
        ↓ absent
explicit tool_name alias (Read/Edit/Write/Bash/WebSearch/...)
        ↓ insufficient
anchored command/input regex (Git before generic shell)
        ↓ no match
generic path/query/command fallback
        ↓ no match
raw event inspector
```

The order matters: `Bash({ command: "git commit ..." })` becomes `git.commit`,
not generic shell. Regexes are anchored and intentionally conservative. New
aliases and Git verbs must include classifier tests before clients route them to
a specialized renderer.

## Responsive rendering

- **Web and macOS:** one compact row (`icon + operation + target + status`) and a
  popover with command context, diff/terminal output, risk hint, and raw data.
  macOS hosts this exact frontend inside its Tauri webview.
- **Next: iOS:** a 44-point activity row and a pushed detail screen. Command,
  working directory, diff, and input/output use separate sections so horizontal
  command text does not make the timeline itself unreadable.
- **Future Android:** consume the same descriptor; do not port the regex table.

## Git renderer roadmap

1. `git_status`: group staged, unstaged, untracked, conflicted files.
2. `diff` / `git_show`: per-file diff navigation and addition/deletion totals.
3. `git_log`: commit rows with hash, subject, author, and relative time.
4. `git_commit`: commit summary plus the staged diff captured at approval time.
5. `git_remote`: remote, refspec, ahead/behind, and rejected/non-fast-forward state.

Output parsers should be added to the Gateway descriptor as structured optional
fields when formats are stable. Clients should not independently regex raw Git
output; that would recreate the cross-platform drift this contract removes.
