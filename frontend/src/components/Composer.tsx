import { useCallback, useEffect, useRef, useState } from "react";
import type { QueuedMessage, ThreadTokenUsage } from "../types";
import { useComposerAutocompleteState } from "../hooks/useComposerAutocompleteState";
import { ComposerInput } from "./ComposerInput";
import { ComposerMetaBar } from "./ComposerMetaBar";
import { ComposerQueue } from "./ComposerQueue";

type ComposerProps = {
  onSend: (text: string) => void;
  onStop: () => void;
  canStop: boolean;
  disabled?: boolean;
  models: { id: string; displayName: string; model: string }[];
  selectedModelId: string | null;
  onSelectModel: (id: string) => void;
  reasoningOptions: string[];
  selectedEffort: string | null;
  onSelectEffort: (effort: string) => void;
  accessMode: "read-only" | "current" | "full-access";
  onSelectAccessMode: (mode: "read-only" | "current" | "full-access") => void;
  skills: { name: string; description?: string }[];
  files: string[];
  contextUsage?: ThreadTokenUsage | null;
  queuedMessages?: QueuedMessage[];
  onEditQueued?: (item: QueuedMessage) => void;
  onDeleteQueued?: (id: string) => void;
  sendLabel?: string;
  prefillDraft?: QueuedMessage | null;
  onPrefillHandled?: (id: string) => void;
};

export function Composer({
  onSend,
  onStop,
  canStop,
  disabled = false,
  models,
  selectedModelId,
  onSelectModel,
  reasoningOptions,
  selectedEffort,
  onSelectEffort,
  accessMode,
  onSelectAccessMode,
  skills,
  files,
  contextUsage = null,
  queuedMessages = [],
  onEditQueued,
  onDeleteQueued,
  sendLabel = "Send",
  prefillDraft = null,
  onPrefillHandled,
}: ComposerProps) {
  const [text, setText] = useState("");
  const [selectionStart, setSelectionStart] = useState<number | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);

  const handleSend = useCallback(() => {
    if (disabled) {
      return;
    }
    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }
    onSend(trimmed);
    setText("");
  }, [disabled, onSend, text]);

  const {
    isAutocompleteOpen,
    autocompleteMatches,
    highlightIndex,
    setHighlightIndex,
    applyAutocomplete,
    handleInputKeyDown,
    handleTextChange,
    handleSelectionChange,
  } = useComposerAutocompleteState({
    text,
    selectionStart,
    disabled,
    skills,
    files,
    textareaRef,
    setText,
    setSelectionStart,
  });

  useEffect(() => {
    if (!prefillDraft) {
      return;
    }
    setText(prefillDraft.text);
    onPrefillHandled?.(prefillDraft.id);
  }, [prefillDraft, onPrefillHandled]);

  return (
    <footer className={`composer${disabled ? " is-disabled" : ""}`}>
      <ComposerQueue
        queuedMessages={queuedMessages}
        onEditQueued={onEditQueued}
        onDeleteQueued={onDeleteQueued}
      />
      <ComposerInput
        text={text}
        disabled={disabled}
        sendLabel={sendLabel}
        canStop={canStop}
        onStop={onStop}
        onSend={handleSend}
        onTextChange={handleTextChange}
        onSelectionChange={handleSelectionChange}
        onKeyDown={(event) => {
          handleInputKeyDown(event);
          if (event.defaultPrevented) {
            return;
          }
          if (event.key === "Enter" && !event.shiftKey) {
            event.preventDefault();
            handleSend();
          }
        }}
        textareaRef={textareaRef}
        suggestionsOpen={isAutocompleteOpen}
        suggestions={autocompleteMatches}
        highlightIndex={highlightIndex}
        onHighlightIndex={setHighlightIndex}
        onSelectSuggestion={applyAutocomplete}
      />
      <ComposerMetaBar
        disabled={disabled}
        models={models}
        selectedModelId={selectedModelId}
        onSelectModel={onSelectModel}
        reasoningOptions={reasoningOptions}
        selectedEffort={selectedEffort}
        onSelectEffort={onSelectEffort}
        accessMode={accessMode}
        onSelectAccessMode={onSelectAccessMode}
        contextUsage={contextUsage}
      />
    </footer>
  );
}
