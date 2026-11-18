export interface WorkspaceInfo {
  name: string;
  nodeVersion: string;
  status: "ready";
}

export function getWorkspaceInfo(): WorkspaceInfo {
  return {
    name: "ai-workspace",
    nodeVersion: process.version,
    status: "ready",
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(JSON.stringify(getWorkspaceInfo(), null, 2));
}
