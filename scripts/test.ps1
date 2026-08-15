[CmdletBinding()]
param(
    [switch] $Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectPath = Join-Path $repositoryRoot '.build/eiffel-tests'

function Resolve-EiffelCompiler {
    $command = Get-Command 'ec' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ISE_EIFFEL)) {
        $executableName = if ($env:OS -eq 'Windows_NT') { 'ec.exe' } else { 'ec' }
        if (-not [string]::IsNullOrWhiteSpace($env:ISE_PLATFORM)) {
            $candidate = Join-Path $env:ISE_EIFFEL "studio/spec/$($env:ISE_PLATFORM)/bin/$executableName"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }

        $specRoot = Join-Path $env:ISE_EIFFEL 'studio/spec'
        if (Test-Path -LiteralPath $specRoot -PathType Container) {
            foreach ($platformDirectory in Get-ChildItem -LiteralPath $specRoot -Directory) {
                $candidate = Join-Path $platformDirectory.FullName "bin/$executableName"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
    }

    throw 'Cannot find the EiffelStudio ec compiler. Put ec on PATH or set ISE_EIFFEL and ISE_PLATFORM.'
}

function Assert-SupportedEiffelVersion([string] $Compiler) {
    $versionText = (& $Compiler -version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query EiffelStudio version from $Compiler."
    }
    if ($versionText -notmatch '(?<major>[0-9]+)\.(?<minor>[0-9]+)') {
        throw "Cannot parse EiffelStudio version: $versionText"
    }
    $major = [int] $Matches.major
    $minor = [int] $Matches.minor
    if ($major -lt 25 -or ($major -eq 25 -and $minor -lt 2)) {
        throw "Symphony Eiffel requires EiffelStudio 25.02 or newer; found $major.$minor."
    }
    Write-Host $versionText
}

$compiler = Resolve-EiffelCompiler
Assert-SupportedEiffelVersion -Compiler $compiler
. (Join-Path $PSScriptRoot 'resolve-ecf.ps1')
$configuration = Resolve-SymphonyConfiguration -RepositoryRoot $repositoryRoot -Compiler $compiler
New-Item -ItemType Directory -Path $projectPath -Force | Out-Null

$arguments = @(
    '-batch',
    '-config', $configuration,
    '-target', 'test_runner',
    '-project_path', $projectPath
)
if ($Clean) {
    $arguments += '-clean'
}
$arguments += @('-freeze', '-c_compile')

$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$compilerOutput = @(& $compiler @arguments 2>&1)
$compilerExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$compilerLines = @($compilerOutput | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$compilerLines | ForEach-Object { Write-Host $_ }
$compilerText = $compilerLines -join [Environment]::NewLine
if ($compilerExitCode -ne 0) {
    exit $compilerExitCode
}
if ($compilerText -match '(?im)(fatal error|NMAKE\s*:\s*fatal error|C compilation failed)') {
    Write-Error 'Eiffel generated C code, but the native compiler failed.'
    exit 1
}

$testExecutableName = if ($env:OS -eq 'Windows_NT') { 'symphony_tests.exe' } else { 'symphony_tests' }
$testExecutable = Join-Path $projectPath "EIFGENs/test_runner/W_code/$testExecutableName"
if (-not (Test-Path -LiteralPath $testExecutable -PathType Leaf)) {
    throw "Compilation succeeded, but the test executable was not found at $testExecutable."
}

& $testExecutable
exit $LASTEXITCODE
