import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

type MarkdownProps = {
  value: string;
  className?: string;
  codeBlock?: boolean;
};

export function Markdown({ value, className, codeBlock }: MarkdownProps) {
  const content = codeBlock ? `\`\`\`\n${value}\n\`\`\`` : value;
  return (
    <div className={className}>
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
    </div>
  );
}
