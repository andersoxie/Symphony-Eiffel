# Symphony Eiffel

Symphony Eiffel is a native Eiffel implementation of OpenAI's draft
[Symphony service specification](https://github.com/openai/symphony/blob/main/SPEC.md). It reads a
repository-owned `WORKFLOW.md`, polls a tracker, creates a contained workspace per issue, and drives
Codex through the app-server JSONL protocol.

This repository targets a practical local-production profile: a read-only JSON file is the tracker,
workspaces and hooks run on the local host, and structured JSON Lines are the operator surface. It is
not a general distributed workflow engine or a hosted control plane.

## Supported profile

| Area | Included |
| --- | --- |
| Workflow | Markdown plus native YAML front matter, typed defaults, strict prompt rendering, reload support |
| Trackers | `json_file` for local production/automation; `memory` for deterministic tests |
| Execution | Per-issue local workspaces, lifecycle hooks, Codex app-server over stdio JSONL |
| Policy | Active/terminal states, required labels, global/per-state concurrency, retry backoff |
| Observability | Structured JSONL events with issue and session context; secret-looking fields redacted |

The native YAML reader intentionally supports the workflow-oriented subset: indented maps and
lists, inline `[]`/`{}`, quoted and plain scalars, booleans, null, decimal integers, comments, and
literal/folded block strings with chomping. Anchors, aliases, tags, timestamps, floating-point
coercion, complex keys, and multiline flow collections are not supported. The front-matter root
must be a map and duplicate keys are rejected.

## Requirements

- EiffelStudio 25.02 or newer, using the classic native compiler.
- A supported C toolchain configured for EiffelStudio (Visual Studio C++ on Windows, or the
  platform toolchain on Unix-like hosts).
- The EiffelStudio `base`, `time`, `process`, `thread`, and `testing` libraries, plus the bundled
  contributed `json` and `eel` libraries. `symphony.ecf` resolves them through `$ISE_LIBRARY`.
- PowerShell 5.1 or PowerShell 7+ to use the helper scripts.
- `bash` for launching Codex. On Windows, Git for Windows is the usual provider; set
  `SYMPHONY_BASH` to an explicit `bash.exe` when it is not discoverable.
- A separately installed and authenticated Codex CLI whose `app-server` protocol matches this
  client.

Check the two main tools before building:

```powershell
ec -version
codex --version
```

## Build and test

From the repository root:

```powershell
./scripts/build.ps1
./scripts/test.ps1
```

`build.ps1` creates a workbench build below `.build/eiffel`. Use `-Clean` for a fresh Eiffel project
or `-Finalize` for an optimized final build:

```powershell
./scripts/build.ps1 -Clean
./scripts/build.ps1 -Finalize
```

The script prints the executable path. Typical Windows outputs are:

- Workbench: `.build/eiffel/EIFGENs/symphony/W_code/symphony.exe`
- Finalized: `.build/eiffel/EIFGENs/symphony/F_code/symphony.exe`

The equivalent compiler commands are:

```powershell
ec -batch -config symphony.ecf -target symphony `
  -project_path .build/eiffel -freeze -c_compile

ec -batch -config symphony.ecf -target test_runner `
  -project_path .build/eiffel-tests -freeze -c_compile
.build/eiffel-tests/EIFGENs/test_runner/W_code/symphony_tests.exe
```

The test command runs the serial EQA assertion harness and returns nonzero for compilation or test
failures, including native C compiler failures that some Eiffel driver versions do not propagate in
their exit code. The `tests` target can also be opened in EiffelStudio and run from the AutoTest
tool.

After building, run the credential-free app-server integration fixture with:

```powershell
./scripts/integration-test.ps1
```

It verifies two continuation turns on one app-server process, current-schema cumulative token
events, rate-limit telemetry, safe handling of an unclassified payload, a structured response to an
unsupported dynamic-tool request with a string request ID, and descendant-process containment even
when the mock app-server leader exits first.

If configuration loading fails with `VD00` before Eiffel source is checked, verify that every
library referenced by `symphony.ecf` exists and is readable. In particular, a damaged,
permission-restricted, or OS-encrypted `process` library configuration can look like a project XML
error. The helper scripts detect an unreadable stock `base_process.ecf` and, when available, build
an ignored configuration overlay from the readable IRON `process` package under Eiffel User Files.
Set `SYMPHONY_PROCESS_SOURCE_ROOT` to that package's source directory when it is installed in a
nonstandard location, or set `SYMPHONY_ECF` to a complete alternate project configuration. Opening
`symphony.ecf` directly in EiffelStudio still requires repairing the installation or file
permissions; no machine-specific paths are stored in the checked-in configuration.

## Quick start

The example uses a local JSON tracker and creates a small Git repository for each new issue
workspace. Inspect both files before running because workflow hooks are executable host commands.

```powershell
# Parse the workflow and validate configuration without polling, hooks, workspaces, or Codex.
& ./.build/eiffel/EIFGENs/symphony/W_code/symphony.exe `
  --validate ./examples/WORKFLOW.md

# Perform one reconciliation/dispatch cycle, finish work started by that cycle, then exit.
& ./.build/eiffel/EIFGENs/symphony/W_code/symphony.exe `
  --once ./examples/WORKFLOW.md

# Run continuously. WORKFLOW.md is used from the current directory when no path is supplied.
& ./.build/eiffel/EIFGENs/symphony/W_code/symphony.exe ./examples/WORKFLOW.md
```

An eligible issue in `examples/issues.json` causes `--once` to launch a real Codex session. Set its
`dispatchable` field to `false` if you only want to exercise tracker polling.

### CLI modes

```text
symphony [--validate | --once] [path-to-WORKFLOW.md]
```

- With no path, Symphony selects `./WORKFLOW.md` in the process working directory.
- `--validate` loads the workflow, checks the typed configuration and selected tracker profile, and
  exits. It deliberately does not create/remove workspaces, run hooks, poll for dispatch, or launch
  Codex.
- `--once` performs one scheduler reconciliation and dispatch pass instead of starting the recurring
  polling loop. Work accepted during that pass reaches orderly completion before shutdown.
- With neither flag, Symphony starts the long-running polling service.
- A clean validation or normal shutdown exits `0`; startup, validation, test, or abnormal host
  failures exit nonzero.

## `json_file` tracker

Use `tracker.kind: json_file`. This is a local, read-only adapter with one recognized provider key:

| Provider key | Required | Default | Behavior |
| --- | --- | --- | --- |
| `path` | yes | none | Nonblank local JSON-file path; relative paths resolve from the directory containing `WORKFLOW.md` |

`path` supports `~`, a leading `$VAR`, and a suffix after the variable such as
`$TRACKER_DATA/issues.json`. A missing or empty referenced variable is invalid configuration.
Additional provider keys are ignored. This profile has no credential fields, secret environment
names, or adapter-owned environment fallbacks. It makes no network requests: the complete file is
the configured scope, with no narrower scope selector, pagination, or provider request limits.

The file is re-read on every nonempty state or ID refresh, so an external process may replace it
atomically while Symphony is running. An empty state or ID request returns an empty result without
reading the file.

The root may be an array or an object containing an `issues` array. Every issue record must contain:

```json
{
  "id": "stable-opaque-id",
  "identifier": "TEAM-123",
  "title": "Human-readable title",
  "state": "Todo",
  "dispatchable": true
}
```

`id` maps directly to Symphony's opaque dispatch ID and is compared exactly. `identifier` maps
directly to the human/workspace identifier. `dispatchable` is the adapter-owned safety gate and
remains required even when it is `false`.

Optional fields are `native_ref`, `description`, `priority`, `branch_name`, `url`, `assignee_id`,
`labels`, `blocked_by`, `created_at`, and `updated_at`. Normalization is deterministic:

- Optional scalar values with unusable types become null. Timestamps are parsed as RFC 3339 or
  become null.
- Labels are trimmed and lowercased; blanks and duplicates are removed, and a missing or unusable
  labels value becomes an empty list. State spelling is retained, while scheduler state comparisons
  trim and lowercase.
- Priorities `1` through `4` sort first; other integers and null share the default bucket.
- A missing or unusable blocker list becomes empty, and non-object blocker entries are dropped.
  `native_ref` must be an object; it is otherwise null.
- A valid `native_ref` object is preserved verbatim unless any nested object or array contains a
  conventionally secret-looking key such as `authorization`, `password`, `api_key`, `token`,
  `private_key`, or the corresponding common suffixes. In that case the whole `native_ref`
  normalizes to null so it cannot enter prompt context.

Each nonempty operation validates the complete file before returning results. A malformed root or
record, duplicate `id`, duplicate identifier, identifiers that differ only by case on Windows or
macOS, or identifiers that resolve to the same workspace key (case-insensitively on those hosts)
fails the whole operation with `tracker_response`; no partial list is returned. ID refresh input is
treated as a set and each dispatch ID appears at most once.

Public error categories are:

| Category | Meaning |
| --- | --- |
| `unsupported_tracker_kind` | Adapter was asked to validate a kind other than `json_file` |
| `invalid_tracker_config` | `provider.path` is missing/blank or its leading `~`/environment variable cannot be resolved |
| `tracker_request` | File is missing, not a readable regular file, or an unexpected file-read failure occurs |
| `tracker_response` | JSON/root/issue normalization or identity-integrity validation fails |

This adapter is read-only. State transitions, comments, and pull-request links must be performed by
an external process, then reflected in the JSON file. It exposes no provider-native agent tools.

## `memory` tracker profile

`tracker.kind: memory` selects the deterministic in-process test adapter. It recognizes no
`tracker.provider` keys, has no defaults, credentials, secret environment names, environment
fallbacks, network scope, pagination, request limits, or provider-native tools. A workflow-created
instance starts empty; tests and embedded Eiffel harnesses populate it programmatically, and its
contents do not survive process exit.

The supplied `SYM_ISSUE` fields map directly to the normalized model. IDs use exact matching; states
use trimmed, case-insensitive matching. Programmatic callers are responsible for supplying valid,
non-secret normalized optional data because this profile does not run objects through the JSON-file
codec. Before any nonempty fetch, it rejects duplicate IDs, duplicate identifiers, identifiers that
differ only by case on Windows or macOS, and workspace-key collisions atomically with
`tracker_response`. `put` replaces an existing issue with the same ID. The only other public
validation error is
`unsupported_tracker_kind`; empty fetch inputs return an empty result without inspecting stored
issues.

## `WORKFLOW.md`

The file is Markdown with optional YAML front matter delimited by exact `---` lines. The Markdown
body is the prompt template. Unknown top-level YAML keys are ignored for forward compatibility.

### Configuration fields and defaults

| Field | Default | Notes |
| --- | --- | --- |
| `tracker.kind` | none | Required; `json_file` or `memory` |
| `tracker.provider` | `{}` | `json_file` requires nonblank `path` with relative, `~`, and leading `$VAR` forms |
| `tracker.required_labels` | `[]` | Every label must match, ignoring case/outer whitespace |
| `tracker.active_states` | none | Required, provider-native state names |
| `tracker.terminal_states` | none | Required, provider-native state names |
| `polling.interval_ms` | `30000` | Must be positive |
| `workspace.root` | `<system-temp>/symphony_workspaces` | Must be nonblank; `~`, leading `$VAR`, and relative paths are supported, relative to the workflow directory |
| `hooks.after_create` | absent | Runs once, only for a newly created workspace; failure aborts creation |
| `hooks.before_run` | absent | Runs before each attempt; failure aborts the attempt |
| `hooks.after_run` | absent | Runs after each attempt; failure emits a structured event and is ignored |
| `hooks.before_remove` | absent | Runs before terminal cleanup; failure emits a structured event and cleanup continues |
| `hooks.timeout_ms` | `60000` | Positive timeout shared by all hooks |
| `agent.max_concurrent_agents` | `10` | Positive global cap |
| `agent.max_turns` | `20` | Positive per-worker session cap |
| `agent.max_retry_backoff_ms` | `300000` | Positive exponential-backoff cap |
| `agent.max_concurrent_agents_by_state` | `{}` | Positive per-state caps; invalid entries are ignored |
| `codex.command` | `codex app-server` | Nonblank command launched through `bash -lc` in the issue workspace |
| `codex.approval_policy` | `on-request` | Passed through to the targeted Codex schema |
| `codex.thread_sandbox` | `workspace-write` | Passed through to `thread/start` |
| `codex.turn_sandbox_policy` | `{type: workspaceWrite, networkAccess: false}` | Workspace root is narrowed to the issue workspace when no writable roots are supplied |
| `codex.turn_timeout_ms` | `3600000` | Positive turn/message timeout |
| `codex.read_timeout_ms` | `5000` | Positive handshake/read timeout |
| `codex.stall_timeout_ms` | `300000` | Inactivity threshold used by the host policy; non-positive disables stall detection |

Hook scripts run in the issue workspace. Windows uses noninteractive Windows PowerShell; other hosts
use `sh -lc`. Keep cross-platform hooks to commands available in both shells, or maintain a
platform-specific workflow.

### Prompt syntax

The strict Liquid-style renderer exposes `issue` and `attempt`. Unknown variables and filters fail
the affected run rather than silently rendering empty text. Supported constructs include:

- `{{ issue.identifier }}` and array indexes such as `issue.labels[0]`
- `{% if expression %}...{% else %}...{% endif %}`
- `{% for label in issue.labels %}...{% endfor %}`
- `default`, `strip`, `downcase`, `upcase`, and `json` filters

`issue` contains every normalized field documented under the JSON tracker. `attempt` is null on the
first run and a positive integer on retries or continuations.

## Codex app-server compatibility

Symphony uses the default stdio transport: one JSON object per line. It performs `initialize`, sends
`initialized`, starts a thread, starts turns, consumes streaming notifications, and waits for a
terminal turn event. See the official
[Codex app-server documentation](https://developers.openai.com/codex/app-server/).

The checked-in defaults and fixtures were validated against the generated v2 schema from
`codex-cli 0.130.0-alpha.5`. That schema spells the thread-level enum values `on-request` and
`workspace-write`, while the turn sandbox policy uses `workspaceWrite`. These values are sent
unchanged; regenerate the schema and update the workflow if a different Codex version uses other
spellings.

The app-server protocol evolves with the Codex CLI; this project does not claim compatibility with
every Codex release. For a deployment:

1. Pin the Codex CLI version you validated and record `codex --version` with release artifacts.
2. Generate that exact version's schema:

   ```powershell
   codex app-server generate-json-schema --out .codex-schema
   ```

3. Check `v2/ThreadStartParams.json` and `v2/TurnStartParams.json`, especially approval and sandbox
   values, against the selected `WORKFLOW.md`.
4. Rebuild and run unit tests, `--validate`, and a disposable `--once` integration issue before
   upgrading production.

Generated schemas are version-specific; do not copy values from a different Codex release. The
client currently opts into the experimental API capability but intentionally rejects interactive
input and unsupported dynamic/provider tool calls so a headless run cannot hang waiting for an
operator or an unimplemented tool.

## Safety posture

- Each issue identifier is sanitized into a collision-resistant workspace key. Tracker reads reject
  duplicate IDs, duplicate identifiers, identifiers that differ only by case on Windows or macOS,
  and workspace-key collisions (also compared case-insensitively on those hosts). Windows-ambiguous
  keys such as trailing-dot and reserved device names receive a stable hash suffix.
  Creation, reuse, hook execution, Codex launch, cleanup, and recursive deletion require the issue
  path to be a real, non-link directory directly below the configured root. Symbolic-link and
  reparse-link workspaces are rejected. Paths are rechecked after `after_create` and
  `before_run`, and after `before_remove` immediately before deletion.
- Newly created workspaces are marked incomplete until `after_create` succeeds. A later attempt
  resets a directory that still has the marker rather than silently reusing partial initialization.
- Never configure `workspace.root` as a repository root, home directory, drive root, or shared data
  directory. Terminal-issue reconciliation may delete an issue workspace recursively.
- `WORKFLOW.md` is trusted executable configuration. Hooks run on the host, outside the Codex
  sandbox, and can perform any action available to the Symphony process account. Review workflow
  changes like code changes. Hook stdout and stderr capture is bounded to 65536 bytes per stream and
  is never copied into propagated errors or log messages. Hook lifecycle events contain only the
  hook name, status, and a stable error category; best-effort `after_run` and `before_remove`
  failures are observable without exposing their output.
- Codex approval and sandbox objects are passed through to app-server. The default turn policy is
  workspace-write with network disabled and is narrowed to the current issue workspace. Verify the
  generated Codex schema before changing it.
- Under the default `on-request` posture, an unexpected approval request is canceled and fails the
  headless run. A `never` policy is suitable only when the configured sandbox and environment make
  unattended execution acceptable.
- Tracker adapters may declare secret environment-variable names. Those names are removed from the
  Codex child environment and logs redact conventionally secret keys. The included adapters declare
  none. The JSON-file codec normalizes a `native_ref` containing a nested secret-looking key to null.
  Do not put credentials in prompts, other issue fields, command strings, or unrecognized
  environment variables.
- App-server lines are bounded, malformed protocol objects fail the session, and interactive input
  requests are rejected.
- App-server subprocesses are tracked through the launched root process and, when attachment
  succeeds, a POSIX process group or Windows kill-on-close Job Object. Startup fails before the
  protocol handshake if group attachment cannot be established. Cleanup and graceful shutdown
  retain the issue claim until the attached group is confirmed empty, preventing a retry or
  workspace deletion from racing a child that remains in that group.
- Process-group ownership is lifecycle containment, not a security sandbox. A deliberately
  detached POSIX session, or a Windows child created in the short launch-to-job-attachment window,
  is outside that guarantee. Use the Codex sandbox and approval policy to prevent untrusted
  breakaway or daemon behavior.

Structured logs are JSONL on stdout and include `timestamp`, `level`, `event`, `message`,
`issue_id`, `issue_identifier`, `session_id`, and sanitized `fields`. Redirect stdout to a collector
or append-only file appropriate for the host. Log sink failure does not change scheduling state.

## Deliberately unimplemented extensions

The following are optional or provider-specific Symphony SPEC surfaces and are not included here:

- Human-oriented dashboard or terminal status UI beyond structured logs
- HTTP status/control server, `server.port`, and CLI `--port`
- SSH/remote worker pools and per-host scheduling
- Provider-native app-server tools or tracker write tools
- Network tracker adapters such as Linear, GitHub, Jira, or other hosted services
- WebSocket or Unix-socket app-server transports
- Durable retry/session state across Symphony process restarts

Add these as adapters or extensions without moving provider-specific behavior into the core
orchestrator. In particular, keep tracker credentials host-side and out of the Codex child
environment.
