---
# Deterministic fixture: memory starts empty; no gh, authentication, or network.
# For real GitHub Issues polling, use examples/github/WORKFLOW.md from the
# repository root and follow README.md for host authentication and configuration.
tracker:
  kind: memory
  active_states: [Todo]
  terminal_states: [Done]
polling:
  interval_ms: 50
agent:
  max_concurrent_agents: 1
  max_turns: 1
---
Work on {{ issue.identifier }}: {{ issue.title }}.

