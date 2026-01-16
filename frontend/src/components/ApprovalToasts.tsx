import type { ApprovalRequest, WorkspaceInfo } from "../types";

type ApprovalToastsProps = {
  approvals: ApprovalRequest[];
  workspaces: WorkspaceInfo[];
  onDecision: (request: ApprovalRequest, decision: "accept" | "decline") => void;
};

export function ApprovalToasts({
  approvals,
  workspaces,
  onDecision,
}: ApprovalToastsProps) {
  if (!approvals.length) {
    return null;
  }

  const workspaceLabels = new Map(
    workspaces.map((workspace) => [workspace.id, workspace.name]),
  );

  return (
    <div className="approval-toasts" role="region" aria-live="assertive">
      {approvals.map((request) => {
        const workspaceName = workspaceLabels.get(request.workspace_id);
        return (
          <div key={request.request_id} className="approval-toast" role="alert">
            <div className="approval-toast-header">
              <div className="approval-toast-title">Approval needed</div>
              {workspaceName ? (
                <div className="approval-toast-workspace">{workspaceName}</div>
              ) : null}
            </div>
            <div className="approval-toast-method">{request.method}</div>
            <div className="approval-toast-body">
              {JSON.stringify(request.params, null, 2)}
            </div>
            <div className="approval-toast-actions">
              <button
                className="secondary"
                onClick={() => onDecision(request, "decline")}
              >
                Decline
              </button>
              <button
                className="primary"
                onClick={() => onDecision(request, "accept")}
              >
                Approve
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
