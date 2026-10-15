Use it as a **local task queue for Codex**:

`issues.json → Symphony → separate workspace per issue → Codex edits and tests files`

[WORKFLOW.md](C:/Users/ander/Documents/ChatGPT/Symphonyh/examples/WORKFLOW.md) defines configuration and agent instructions. [issues.json](C:/Users/ander/Documents/ChatGPT/Symphonyh/examples/issues.json) supplies the tasks.

**1. Start with the included demo**

You already have a compiled executable, and I verified that its example configuration passes validation. From this repository’s PowerShell terminal:

```powershell
$symphony = ".\.build\eiffel\EIFGENs\symphony\W_code\symphony.exe"

# Check configuration without starting Codex
& $symphony --validate .\examples\WORKFLOW.md

# Run one scheduling cycle and wait for its work to finish
& $symphony --once .\examples\WORKFLOW.md
```

The second command starts a real Codex session. The example asks it to create `GREETING.md`, normally under:

```text
%TEMP%\symphony_workspaces\DEMO-1\
```

**One compatibility check first:** your installed Codex is `0.117.0`; the repository documents protocol validation against `0.130.0-alpha.5`. Compatibility with your installed version remains unverified. Configuration validation does not check Codex authentication or protocol compatibility.

To rebuild and run the repository’s checks:

```powershell
.\scripts\build.ps1
.\scripts\test.ps1
.\scripts\integration-test.ps1
```

The integration test uses a mock Codex server.

**2. Configure it for your own project**

Copy the two example files into a configuration directory, then adjust:

- **Workspace root:** choose a dedicated directory for disposable issue workspaces.
- **`after_create` hook:** populate each workspace with your project. Clone into a child folder such as `repo`, and update the prompt and other hooks to work there. Cloning into `.` fails because Symphony places an initialization marker there.
- **Prompt:** specify the project’s build/test commands, acceptance criteria, and expected output.
- **Issues:** supply unique IDs and identifiers, clear descriptions, an active state such as `Todo`, the required `symphony` label, and `dispatchable: true`.

Keep the example’s concurrency of one while establishing this workflow. `branch_name` is only a prompt hint; Symphony does not automatically create that branch.

**3. Review and preserve results before closing an issue**

A practical first workflow is:

1. Run `--once`.
2. Inspect the workspace, diff, tests, and JSONL logs.
3. Set `dispatchable: false` while reviewing.
4. Push or copy the results somewhere outside the disposable workspace.
5. Set the issue’s state to `Done`.

**Marking an issue terminal can cause its workspace to be deleted.** A commit stored only inside that workspace is not sufficient preservation.

When ready, omit `--once` for continuous polling:

```powershell
& $symphony .\examples\WORKFLOW.md
```

Continuous mode can repeatedly run an issue that remains eligible—even after a successful attempt. You or an external process must update the JSON tracker. This implementation does not automatically update GitHub/Linear issues or open PRs, and `max_turns` limits each attempt rather than the issue’s total lifetime.
