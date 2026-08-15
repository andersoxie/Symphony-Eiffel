[CmdletBinding()]
param(
    [string] $Executable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($Executable)) {
    $executableName = if ($env:OS -eq 'Windows_NT') { 'symphony.exe' } else { 'symphony' }
    $Executable = Join-Path $repositoryRoot ".build/eiffel/EIFGENs/symphony/W_code/$executableName"
}
$Executable = (Resolve-Path -LiteralPath $Executable -ErrorAction Stop).Path
$workflow = Join-Path $repositoryRoot 'tests/fixtures/integration/WORKFLOW.md'
$descendantPidFile = Join-Path $repositoryRoot 'tests/fixtures/integration/workspaces/MOCK-1/.fake-descendant.pid'

$rawLines = @(& $Executable --once $workflow 2>&1)
$applicationExitCode = $LASTEXITCODE
$lines = @($rawLines | ForEach-Object { $_.ToString() })
$lines | ForEach-Object { Write-Host $_ }

if ($applicationExitCode -ne 0) {
    throw "Symphony integration run exited $applicationExitCode."
}

$events = @($lines | Where-Object { $_.TrimStart().StartsWith('{') } | ForEach-Object { $_ | ConvertFrom-Json })
$sessions = @($events | Where-Object { $_.event -eq 'session_started' })
$toolCalls = @($events | Where-Object { $_.event -eq 'unsupported_tool_call' })
$unclassified = @($events | Where-Object { $_.event -eq 'other_message' })
$usageEvents = @($events | Where-Object { $_.message -eq 'thread/tokenUsage/updated' })
$rateLimitEvents = @($events | Where-Object { $_.message -eq 'account/rateLimits/updated' })
$completed = @($events | Where-Object { $_.event -eq 'worker_completed' })
$pids = @($sessions | ForEach-Object { $_.fields.codex_app_server_pid } | Select-Object -Unique)

if ($sessions.Count -ne 2) { throw "Expected two continuation turns; observed $($sessions.Count)." }
if ($pids.Count -ne 1) { throw "Expected both turns to reuse one app-server process." }
if ($toolCalls.Count -ne 1) { throw 'Expected one structured unsupported dynamic-tool response.' }
if ($unclassified.Count -ne 1) { throw 'Expected one safely summarized unclassified protocol message.' }
if ($rateLimitEvents.Count -ne 1) { throw 'Expected one rate-limit update event.' }
if ($usageEvents.Count -ne 2 -or $usageEvents[-1].fields.input_tokens -ne 2 -or
    $usageEvents[-1].fields.output_tokens -ne 2 -or $usageEvents[-1].fields.total_tokens -ne 4) {
    throw 'Expected cumulative tokenUsage.total counters from the current app-server schema.'
}
if (($lines -join "`n") -match 'SYMPHONY_PROTOCOL_SECRET_SENTINEL') {
    throw 'An unclassified app-server payload was copied into application logs.'
}
if ($completed.Count -ne 1) { throw 'Expected a successful worker completion.' }
if (@($events | Where-Object { $_.issue_identifier -eq 'MOCK-1' }).Count -eq 0) {
    throw 'Expected the tracker issue identifier spelling to be preserved.'
}
if (-not (Test-Path -LiteralPath $descendantPidFile -PathType Leaf)) {
    throw 'Fake app-server did not record its descendant process.'
}
$descendantProcessId = [int](Get-Content -LiteralPath $descendantPidFile -Raw).Trim()
if ($null -ne (Get-Process -Id $descendantProcessId -ErrorAction SilentlyContinue)) {
    throw "App-server descendant process $descendantProcessId survived session shutdown."
}

Write-Host 'Mock app-server integration passed: two turns, one process, descendant containment, structured tool rejection.'
