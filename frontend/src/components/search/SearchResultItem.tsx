import type { ReactNode } from "react";
import type { SearchSelection } from "../../types";
import { FileTypeIcon } from "../icons/FileTypeIcon";
import { MemberListItem } from "../members";
import { SearchHighlight } from "./SearchHighlight";
import { itemKey, labelFor, sigilFor, subFor } from "./searchResultUtils";

export function SearchResultItem({
  selection,
  query,
  action,
  onSelect,
}: {
  selection: SearchSelection;
  query: string;
  action?: ReactNode;
  onSelect: (selection: SearchSelection) => void;
}) {
  const rich =
    selection.type === "file" ||
    selection.type === "message" ||
    selection.type === "todo" ||
    selection.type === "task";
  const sub = subFor(selection);

  if (selection.type === "user" || selection.type === "bot") {
    const label = labelFor(selection);
    return (
      <MemberListItem
        key={itemKey(selection)}
        id={selection.type === "user" ? selection.item.user_id : selection.item.bot_id}
        kind={selection.type}
        username={selection.item.username}
        displayName={label}
        name={<SearchHighlight text={label} query={query} />}
        avatarUrl={selection.item.avatar_url}
        subtitle={sub}
        variant="panel"
        compact
        asButton
        className="an-search-hit an-search-member-hit"
        onClick={() => onSelect(selection)}
        actions={action ? <span className="an-search-action">{action}</span> : undefined}
      />
    );
  }

  return (
    <button
      key={itemKey(selection)}
      type="button"
      className={`an-search-hit ${rich ? "is-rich" : ""}`}
      onClick={() => onSelect(selection)}
    >
      {selection.type === "file" ? (
        <span className="an-search-file-ico">
          <FileTypeIcon
            contentType={selection.item.content_type}
            filename={selection.item.original_filename || selection.item.file_id}
            size={18}
          />
        </span>
      ) : (
        <span className="an-search-sigil">{sigilFor(selection.type)}</span>
      )}
      <span className="an-search-main">
        <span className="an-search-name">
          <SearchHighlight text={labelFor(selection)} query={query} />
        </span>
        {sub && <span className="an-search-sub">{sub}</span>}
        {selection.type === "file" && selection.item.snippet && (
          <span className="an-search-meta">
            <SearchHighlight text={selection.item.snippet} query={query} />
          </span>
        )}
        {selection.type === "task" && selection.item.snippet && (
          <span className="an-search-meta">
            <SearchHighlight text={selection.item.snippet} query={query} />
          </span>
        )}
        {selection.type === "message" && (
          <span className="an-search-meta">
            <SearchHighlight text={selection.item.snippet} query={query} />
          </span>
        )}
      </span>
      {action && <span className="an-search-action">{action}</span>}
    </button>
  );
}
