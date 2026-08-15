---
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

