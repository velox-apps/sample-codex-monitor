import { useEffect, useRef } from "react";
import type { KeyboardEvent, RefObject } from "react";
import type { AutocompleteItem } from "../hooks/useComposerAutocomplete";

type ComposerInputProps = {
  text: string;
  disabled: boolean;
  sendLabel: string;
  canStop: boolean;
  onStop: () => void;
  onSend: () => void;
  onTextChange: (next: string, selectionStart: number | null) => void;
  onSelectionChange: (selectionStart: number | null) => void;
  onKeyDown: (event: KeyboardEvent<HTMLTextAreaElement>) => void;
  textareaRef: RefObject<HTMLTextAreaElement | null>;
  suggestionsOpen: boolean;
  suggestions: AutocompleteItem[];
  highlightIndex: number;
  onHighlightIndex: (index: number) => void;
  onSelectSuggestion: (item: AutocompleteItem) => void;
};

export function ComposerInput({
  text,
  disabled,
  sendLabel,
  canStop,
  onStop,
  onSend,
  onTextChange,
  onSelectionChange,
  onKeyDown,
  textareaRef,
  suggestionsOpen,
  suggestions,
  highlightIndex,
  onHighlightIndex,
  onSelectSuggestion,
}: ComposerInputProps) {
  const suggestionListRef = useRef<HTMLDivElement | null>(null);
  const suggestionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const isFileSuggestion = (item: AutocompleteItem) =>
    item.label.includes("/") || item.label.includes("\\");
  const fileTitle = (path: string) => {
    const normalized = path.replace(/\\/g, "/");
    const parts = normalized.split("/").filter(Boolean);
    return parts.length ? parts[parts.length - 1] : path;
  };

  useEffect(() => {
    if (!suggestionsOpen) {
      return;
    }
    const list = suggestionListRef.current;
    const item = suggestionRefs.current[highlightIndex];
    if (!list || !item) {
      return;
    }
    const listRect = list.getBoundingClientRect();
    const itemRect = item.getBoundingClientRect();
    if (itemRect.top < listRect.top) {
      item.scrollIntoView({ block: "nearest" });
      return;
    }
    if (itemRect.bottom > listRect.bottom) {
      item.scrollIntoView({ block: "nearest" });
    }
  }, [highlightIndex, suggestionsOpen, suggestions.length]);

  return (
    <div className="composer-input">
      <div className="composer-input-area">
        <textarea
          ref={textareaRef}
          placeholder={
            disabled
              ? "Review in progress. Chat will re-enable when it completes."
              : "Ask Codex to do something..."
          }
          value={text}
          onChange={(event) =>
            onTextChange(event.target.value, event.target.selectionStart)
          }
          onSelect={(event) =>
            onSelectionChange(
              (event.target as HTMLTextAreaElement).selectionStart,
            )
          }
          disabled={disabled}
          onKeyDown={onKeyDown}
        />
        {suggestionsOpen && (
          <div className="composer-suggestions" role="listbox" ref={suggestionListRef}>
            {suggestions.map((item, index) => (
              <button
                key={item.id}
                type="button"
                className={`composer-suggestion${
                  index === highlightIndex ? " is-active" : ""
                }`}
                role="option"
                aria-selected={index === highlightIndex}
                ref={(node) => {
                  suggestionRefs.current[index] = node;
                }}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => onSelectSuggestion(item)}
                onMouseEnter={() => onHighlightIndex(index)}
              >
                {isFileSuggestion(item) ? (
                  <>
                    <span className="composer-suggestion-title">
                      {fileTitle(item.label)}
                    </span>
                    <span className="composer-suggestion-description">
                      {item.label}
                    </span>
                  </>
                ) : (
                  <>
                    <span className="composer-suggestion-title">{item.label}</span>
                    {item.description && (
                      <span className="composer-suggestion-description">
                        {item.description}
                      </span>
                    )}
                  </>
                )}
              </button>
            ))}
          </div>
        )}
      </div>
      <button
        className="composer-stop"
        onClick={onStop}
        disabled={disabled || !canStop}
        aria-label="Stop"
      >
        <span className="composer-stop-square" aria-hidden />
      </button>
      <button
        className="composer-send"
        onClick={onSend}
        disabled={disabled}
        aria-label={sendLabel}
      >
        <svg viewBox="0 0 24 24" fill="none" aria-hidden>
          <path
            d="M12 5l6 6m-6-6L6 11m6-6v14"
            stroke="currentColor"
            strokeWidth="1.7"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </button>
    </div>
  );
}
