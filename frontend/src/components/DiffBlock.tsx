import { useMemo } from "react";
import { parseDiff } from "../utils/diff";
import { highlightLine } from "../utils/syntax";

type DiffBlockProps = {
  diff: string;
  language?: string | null;
  showLineNumbers?: boolean;
};

export function DiffBlock({
  diff,
  language,
  showLineNumbers = true,
}: DiffBlockProps) {
  const parsed = useMemo(() => parseDiff(diff), [diff]);
  return (
    <div>
      {parsed.map((line, index) => {
        const shouldHighlight =
          line.type === "add" || line.type === "del" || line.type === "context";
        const html = highlightLine(line.text, shouldHighlight ? language : null);
        return (
          <div key={index} className={`diff-line diff-line-${line.type}`}>
            {showLineNumbers && (
              <div className="diff-gutter">
                <span className="diff-line-number">{line.oldLine ?? ""}</span>
                <span className="diff-line-number">{line.newLine ?? ""}</span>
              </div>
            )}
            <div
              className="diff-line-content"
              dangerouslySetInnerHTML={{ __html: html }}
            />
          </div>
        );
      })}
    </div>
  );
}
