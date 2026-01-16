type HomeProps = {
  onOpenProject: () => void;
  onAddWorkspace: () => void;
  onCloneRepository: () => void;
};

export function Home({
  onOpenProject,
  onAddWorkspace,
  onCloneRepository,
}: HomeProps) {
  return (
    <div className="home">
      <div className="home-title">Codex Monitor</div>
      <div className="home-subtitle">
        Orchestrate agents across your local projects.
      </div>
      <div className="home-actions">
        <button
          className="home-button primary"
          onClick={onOpenProject}
          data-tauri-drag-region="false"
        >
          <span className="home-icon" aria-hidden>
            ⌘
          </span>
          Open Project
        </button>
        <button
          className="home-button secondary"
          onClick={onAddWorkspace}
          data-tauri-drag-region="false"
        >
          <span className="home-icon" aria-hidden>
            +
          </span>
          Add Workspace
        </button>
        <button
          className="home-button ghost"
          onClick={onCloneRepository}
          disabled
          data-tauri-drag-region="false"
        >
          <span className="home-icon" aria-hidden>
            ⤓
          </span>
          Clone Repository
        </button>
      </div>
    </div>
  );
}
