import { useCallback, useMemo } from "react";
import type { AutocompleteItem } from "./useComposerAutocomplete";
import { useComposerAutocomplete } from "./useComposerAutocomplete";

type Skill = { name: string; description?: string };

type UseComposerAutocompleteStateArgs = {
  text: string;
  selectionStart: number | null;
  disabled: boolean;
  skills: Skill[];
  files: string[];
  textareaRef: React.RefObject<HTMLTextAreaElement | null>;
  setText: (next: string) => void;
  setSelectionStart: (next: number | null) => void;
};

export function useComposerAutocompleteState({
  text,
  selectionStart,
  disabled,
  skills,
  files,
  textareaRef,
  setText,
  setSelectionStart,
}: UseComposerAutocompleteStateArgs) {
  const skillItems = useMemo<AutocompleteItem[]>(
    () =>
      skills.map((skill) => ({
        id: skill.name,
        label: skill.name,
        description: skill.description,
        insertText: skill.name,
      })),
    [skills],
  );

  const fileItems = useMemo<AutocompleteItem[]>(
    () =>
      files.map((path) => ({
        id: path,
        label: path,
        insertText: path,
      })),
    [files],
  );

  const triggers = useMemo(
    () => [
      { trigger: "$", items: skillItems },
      { trigger: "@", items: fileItems },
    ],
    [fileItems, skillItems],
  );

  const {
    active: isAutocompleteOpen,
    matches: autocompleteMatches,
    highlightIndex,
    setHighlightIndex,
    moveHighlight,
    range: autocompleteRange,
    close: closeAutocomplete,
  } = useComposerAutocomplete({
    text,
    selectionStart,
    triggers,
  });

  const applyAutocomplete = useCallback(
    (item: AutocompleteItem) => {
      if (!autocompleteRange) {
        return;
      }
      const triggerIndex = Math.max(0, autocompleteRange.start - 1);
      const triggerChar = text[triggerIndex] ?? "";
      const before =
        triggerChar === "@"
          ? text.slice(0, triggerIndex)
          : text.slice(0, autocompleteRange.start);
      const after = text.slice(autocompleteRange.end);
      const insert = item.insertText ?? item.label;
      const actualInsert = triggerChar === "@"
        ? insert.replace(/^@+/, "")
        : insert;
      const needsSpace = after.length === 0 ? true : !/^\s/.test(after);
      const nextText = `${before}${actualInsert}${needsSpace ? " " : ""}${after}`;
      setText(nextText);
      closeAutocomplete();
      requestAnimationFrame(() => {
        const textarea = textareaRef.current;
        if (!textarea) {
          return;
        }
        const cursor =
          before.length + actualInsert.length + (needsSpace ? 1 : 0);
        textarea.focus();
        textarea.setSelectionRange(cursor, cursor);
        setSelectionStart(cursor);
      });
    },
    [autocompleteRange, closeAutocomplete, setSelectionStart, setText, text, textareaRef],
  );

  const handleTextChange = useCallback(
    (next: string, cursor: number | null) => {
      setText(next);
      setSelectionStart(cursor);
    },
    [setSelectionStart, setText],
  );

  const handleSelectionChange = useCallback(
    (cursor: number | null) => {
      setSelectionStart(cursor);
    },
    [setSelectionStart],
  );

  const handleInputKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (disabled) {
        return;
      }
      if (isAutocompleteOpen) {
        if (event.key === "ArrowDown") {
          event.preventDefault();
          moveHighlight(1);
          return;
        }
        if (event.key === "ArrowUp") {
          event.preventDefault();
          moveHighlight(-1);
          return;
        }
        if (event.key === "Enter" && !event.shiftKey) {
          event.preventDefault();
          const selected =
            autocompleteMatches[highlightIndex] ?? autocompleteMatches[0];
          if (selected) {
            applyAutocomplete(selected);
          }
          return;
        }
        if (event.key === "Tab") {
          event.preventDefault();
          const selected =
            autocompleteMatches[highlightIndex] ?? autocompleteMatches[0];
          if (selected) {
            applyAutocomplete(selected);
          }
          return;
        }
        if (event.key === "Escape") {
          event.preventDefault();
          closeAutocomplete();
          return;
        }
      }
    },
    [
      applyAutocomplete,
      autocompleteMatches,
      closeAutocomplete,
      disabled,
      highlightIndex,
      isAutocompleteOpen,
      moveHighlight,
    ],
  );

  return {
    isAutocompleteOpen,
    autocompleteMatches,
    highlightIndex,
    setHighlightIndex,
    applyAutocomplete,
    handleInputKeyDown,
    handleTextChange,
    handleSelectionChange,
  };
}
