---
# Deterministic integration fixture: read-only local JSON plus fake Codex.
# This profile requires no live GitHub access, gh login, or tracker credentials.
# The production GitHub Issues profile is examples/github/WORKFLOW.md; see
# README.md for setup. Switching tracker.kind to github requires host
# authentication and a configured repository, changing this fixture behavior.
tracker:
  kind: json_file
  provider:
    path: ./issues.json
  required_labels: [symphony]
  active_states: [Todo]
  terminal_states: [Done]
workspace:
  root: ./workspaces
agent:
  max_concurrent_agents: 1
  max_turns: 2
codex:
  command: bash ../../fake_codex.sh
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
    networkAccess: false
  read_timeout_ms: 5000
  turn_timeout_ms: 5000
  stall_timeout_ms: 5000
---
Handle {{ issue.identifier }}: {{ issue.title }} (attempt {{ attempt | default: 0 }}).

