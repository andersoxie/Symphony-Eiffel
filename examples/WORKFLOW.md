---
# Credential-free local JSON profile; see README.md for tracker configuration.
# For authenticated GitHub Issues polling, use examples/github/WORKFLOW.md.
# Eligible JSON records start real Codex sessions. Set dispatchable to false
# to poll without dispatch, or move work to Review for operator handoff.
# Preserve workspace results before moving an issue into a terminal state.
tracker:
  kind: json_file
  provider:
    path: ./issues.json
  required_labels: [symphony]
  active_states:
    - Todo
    - In Progress
  terminal_states: [Done, Canceled]

polling:
  interval_ms: 30000

# Omit workspace.root to use the system temporary directory. A relative path would
# resolve from this examples directory, for example: ../.workspaces

hooks:
  timeout_ms: 60000
  # This starter initializes an empty repository. For a real checkout, clone into
  # a subdirectory; the workspace root contains an initialization marker.
  after_create: |-
    git init
  before_run: |-
    git status --short
  after_run: |-
    git status --short

agent:
  max_concurrent_agents: 1
  max_turns: 1
  max_retry_backoff_ms: 300000
  max_concurrent_agents_by_state:
    In Progress: 1

codex:
  command: codex app-server
  approval_policy: on-request
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
    networkAccess: false
  turn_timeout_ms: 3600000
  read_timeout_ms: 5000
  stall_timeout_ms: 300000
---
You are working on {{ issue.identifier }}: {{ issue.title }}.

{% if issue.description %}
Issue description:
{{ issue.description | strip }}
{% else %}
No issue description was supplied.
{% endif %}

Attempt: {{ attempt | default: 0 }}
Labels: {{ issue.labels | json }}
Branch hint: {{ issue.branch_name | default: "not supplied" }}

Work only inside the current issue workspace. Inspect the repository before editing, make the
smallest coherent change that satisfies the issue, and run the most relevant available checks.
Summarize the files changed, verification performed, and any remaining blocker. Do not claim the
issue is complete when verification failed.

