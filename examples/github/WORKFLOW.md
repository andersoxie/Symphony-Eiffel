---
# Read-only GitHub Issues profile; see README.md for configuration and lifecycle.
# Authenticate gh on the host; polling uses gh api --paginate --slurp.
# GitHub uses native open/closed states. Eligible open issues can run again
# while they retain every required label, including after a successful turn.
# Remove the symphony label for review; preserve workspace results before closing.
# Polling does not post comments, publish pull requests, or close issues.
# --validate checks local configuration only; --once can start real Codex sessions.
tracker:
  kind: github
  provider:
    repository: YOUR-OWNER/YOUR-REPO
    hostname: github.com
    request_timeout_ms: 30000
  required_labels: [symphony]
  active_states: [open]
  terminal_states: [closed]

polling:
  interval_ms: 30000

# Omit workspace.root to use the system temporary directory.
# Replace YOUR-OWNER/YOUR-REPO in both the provider and clone hook.
# For Enterprise, set provider.hostname and change the clone URL host too.
# Clone into a subdirectory; the workspace root contains an initialization marker.
hooks:
  timeout_ms: 60000
  after_create: |-
    git clone https://github.com/YOUR-OWNER/YOUR-REPO.git repository
  before_run: |-
    git -C repository status --short
  after_run: |-
    git -C repository status --short

agent:
  max_concurrent_agents: 1
  max_turns: 1
  max_retry_backoff_ms: 300000

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
You are working on GitHub issue {{ issue.identifier }}: {{ issue.title }}.

{% if issue.description %}
Issue description:
{{ issue.description | strip }}
{% else %}
No issue description was supplied.
{% endif %}

Issue URL: {{ issue.url | default: "not supplied" }}
Attempt: {{ attempt | default: 0 }}
Labels: {{ issue.labels | json }}

Review the issue and repository instructions before editing. The checkout is in the repository
subdirectory of the current issue workspace; make changes and run checks there. Make the smallest
coherent change that satisfies the issue and run the most relevant available checks. Summarize the
files changed, verification performed, and any remaining blocker.
Do not claim the issue is complete when verification failed. Leave GitHub comments, issue closure,
and pull-request publication to the operator.
