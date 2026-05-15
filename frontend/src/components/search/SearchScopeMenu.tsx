type ScopeOption = {
  value: string;
  label: string;
  title?: string;
  marker?: string;
};

export function SearchScopeMenu({
  options,
  value,
  onSelect,
}: {
  options: ScopeOption[];
  value?: string;
  onSelect: (value: string) => void;
}) {
  return (
    <div className="an-search-scope-pop" role="menu">
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <button
            key={option.value || "__all__"}
            type="button"
            role="menuitemradio"
            aria-checked={selected}
            className="an-search-scope-option"
            data-active={selected ? "1" : undefined}
            title={option.title || option.label}
            onClick={() => onSelect(option.value)}
          >
            <span className="an-search-scope-option-mark">{option.marker || "∗"}</span>
            <span className="an-search-scope-option-text">
              <span className="an-search-scope-option-name">{option.label}</span>
              {option.title && (
                <span className="an-search-scope-option-sub">{option.title}</span>
              )}
            </span>
          </button>
        );
      })}
    </div>
  );
}
