Set-StrictMode -Version Latest

function Resolve-SymphonyConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
        [Parameter(Mandatory = $true)] [string] $Compiler
    )

    $defaultConfiguration = Join-Path $RepositoryRoot 'symphony.ecf'
    if (-not [string]::IsNullOrWhiteSpace($env:SYMPHONY_ECF)) {
        if (-not (Test-Path -LiteralPath $env:SYMPHONY_ECF -PathType Leaf)) {
            throw "SYMPHONY_ECF does not name a file: $($env:SYMPHONY_ECF)"
        }
        return (Resolve-Path -LiteralPath $env:SYMPHONY_ECF).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ISE_LIBRARY)) {
        $iseRoot = $env:ISE_LIBRARY
    } else {
        $compilerDirectory = (Get-Item -LiteralPath $Compiler).Directory
        for ($level = 0; $level -lt 4; $level += 1) {
            if ($null -eq $compilerDirectory.Parent) {
                throw "Cannot derive ISE_LIBRARY from compiler path: $Compiler"
            }
            $compilerDirectory = $compilerDirectory.Parent
        }
        $iseRoot = $compilerDirectory.FullName
    }

    $stockBaseProcess = Join-Path $iseRoot 'library/process/base/base_process.ecf'
    try {
        $null = Get-Content -LiteralPath $stockBaseProcess -Raw -ErrorAction Stop
        return $defaultConfiguration
    } catch {
        # Some installations have a missing, damaged, or EFS-encrypted base_process library.
    }

    $processSourceRoot = $null
    if (-not [string]::IsNullOrWhiteSpace($env:SYMPHONY_PROCESS_SOURCE_ROOT)) {
        $processSourceRoot = $env:SYMPHONY_PROCESS_SOURCE_ROOT
    } elseif ($env:OS -eq 'Windows_NT') {
        $eiffelUserRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Eiffel User Files'
        if (Test-Path -LiteralPath $eiffelUserRoot -PathType Container) {
            $candidate = Get-ChildItem -LiteralPath $eiffelUserRoot -Directory |
                Sort-Object -Property Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'iron/packages/process' } |
                Where-Object {
                    (Test-Path -LiteralPath (Join-Path $_ 'process.e') -PathType Leaf) -and
                    (Test-Path -LiteralPath (Join-Path $_ 'base/base_process.e') -PathType Leaf)
                } |
                Select-Object -First 1
            if ($null -ne $candidate) {
                $processSourceRoot = $candidate
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($processSourceRoot)) {
        throw "The stock base_process.ecf is unreadable. Repair EiffelStudio or set SYMPHONY_PROCESS_SOURCE_ROOT to a readable process package source tree."
    }
    $processSourceRoot = (Resolve-Path -LiteralPath $processSourceRoot).Path
    foreach ($requiredRelativePath in @('process.e', 'base/base_process.e')) {
        $requiredPath = Join-Path $processSourceRoot $requiredRelativePath
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Process source tree is incomplete; missing $requiredPath"
        }
    }

    $overlayRoot = Join-Path $RepositoryRoot '.build/dependency-overrides'
    New-Item -ItemType Directory -Path $overlayRoot -Force | Out-Null
    $processConfiguration = Join-Path $overlayRoot 'process.ecf'
    $testingConfiguration = Join-Path $overlayRoot 'testing.ecf'
    $projectConfiguration = Join-Path $overlayRoot 'symphony.ecf'
    $separator = [IO.Path]::DirectorySeparatorChar

    function Escape-Xml([string] $Value) {
        return [Security.SecurityElement]::Escape($Value)
    }

    $escapedIse = Escape-Xml $iseRoot
    $escapedProcess = Escape-Xml $processSourceRoot
    $escapedProcessConfiguration = Escape-Xml $processConfiguration
    $baseRoot = "$escapedProcess$separator" + 'base' + "$separator"
    $processRootWithSeparator = "$escapedProcess$separator"
    $processXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<system xmlns="http://www.eiffel.com/developers/xml/configuration-1-23-0" name="symphony_process_overlay" uuid="A3F5E189-599C-4BD1-9601-8868517BD2E0" library_target="process">
  <target name="process">
    <root all_classes="true"/>
    <option warning="error" namespace="EiffelSoftware.Library"/>
    <setting name="dotnet_naming_convention" value="true"/>
    <capability><concurrency support="thread"/></capability>
    <library name="base" location="$escapedIse${separator}library${separator}base${separator}base.ecf"/>
    <library name="thread" location="$escapedIse${separator}library${separator}thread${separator}thread.ecf"/>
    <library name="wel" location="$escapedIse${separator}library${separator}wel${separator}wel.ecf"><condition><platform value="windows"/></condition></library>
    <external_include location="${baseRoot}platform${separator}windows${separator}include"><condition><platform value="windows"/></condition></external_include>
    <external_include location="${baseRoot}platform${separator}unix${separator}include"><condition><platform excluded_value="windows"/></condition></external_include>
    <cluster name="base_process_mswin" location="${baseRoot}platform${separator}windows$separator" recursive="true"><condition><platform value="windows"/><dotnet value="false"/></condition><file_rule><exclude>^/include</exclude></file_rule></cluster>
    <cluster name="base_process_unix" location="${baseRoot}platform${separator}unix$separator" recursive="true"><condition><platform excluded_value="windows"/><dotnet value="false"/></condition><file_rule><exclude>^/Clib</exclude></file_rule></cluster>
    <cluster name="base_process" location="$baseRoot"/>
    <cluster name="classic_mswin" location="${processRootWithSeparator}classic${separator}windows$separator" recursive="true"><condition><platform value="windows"/><dotnet value="false"/></condition></cluster>
    <cluster name="classic_unix" location="${processRootWithSeparator}classic${separator}unix$separator" recursive="true"><condition><platform excluded_value="windows"/><dotnet value="false"/></condition><file_rule><exclude>^/Clib</exclude></file_rule></cluster>
    <cluster name="process" location="$processRootWithSeparator"/>
  </target>
</system>
"@
    [IO.File]::WriteAllText($processConfiguration, $processXml, [Text.UTF8Encoding]::new($false))

    $testingRoot = Escape-Xml (Join-Path $iseRoot 'library/testing')
    $testingRootWithSeparator = "$testingRoot$separator"
    $testingXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<system xmlns="http://www.eiffel.com/developers/xml/configuration-1-22-0" name="symphony_testing_overlay" uuid="F664B754-A146-4B1F-B85E-D8BC5A4F8D2D" library_target="testing">
  <target name="testing">
    <root all_classes="true"/>
    <file_rule><exclude>/EIFGENs$</exclude><exclude>/\.svn$</exclude><exclude>/tests$</exclude></file_rule>
    <option warning="error" namespace="EiffelSoftware.Library"/>
    <capability><concurrency support="scoop" use="thread"/></capability>
    <library name="base" location="$escapedIse${separator}library${separator}base${separator}base.ecf"/>
    <library name="diff" location="$escapedIse${separator}library${separator}diff${separator}diff.ecf"/>
    <library name="net" location="$escapedIse${separator}library${separator}net${separator}net.ecf"/>
    <library name="process" location="$escapedProcessConfiguration"><condition><concurrency value="thread"/></condition></library>
    <library name="time" location="$escapedIse${separator}library${separator}time${separator}time.ecf"/>
    <cluster name="etf" location="${testingRootWithSeparator}etf$separator" recursive="true"/>
    <cluster name="testing" location="$testingRootWithSeparator" recursive="true">
      <file_rule><exclude>/etf$</exclude></file_rule>
      <file_rule><exclude>/eqa_execution.e$</exclude><exclude>/eqa_system_execution.e$</exclude><exclude>/eqa_system_execution_process.e$</exclude><exclude>/eqa_system_output_processor.e$</exclude><exclude>/eqa_system_test_set.e$</exclude><condition><concurrency excluded_value="thread"/></condition></file_rule>
    </cluster>
  </target>
</system>
"@
    [IO.File]::WriteAllText($testingConfiguration, $testingXml, [Text.UTF8Encoding]::new($false))

    [xml] $projectDocument = Get-Content -LiteralPath $defaultConfiguration -Raw
    $processNode = $projectDocument.SelectSingleNode("//*[local-name()='target' and @name='symphony']/*[local-name()='library' and @name='process']")
    $testingNode = $projectDocument.SelectSingleNode("//*[local-name()='target' and @name='tests']/*[local-name()='library' and @name='testing']")
    $sourceNode = $projectDocument.SelectSingleNode("//*[local-name()='cluster' and @name='source']")
    $testsNode = $projectDocument.SelectSingleNode("//*[local-name()='tests' and @name='test_source']")
    $includeNode = $projectDocument.SelectSingleNode("//*[local-name()='external_include']")
    $processNode.SetAttribute('location', $processConfiguration)
    $testingNode.SetAttribute('location', $testingConfiguration)
    $sourceNode.SetAttribute('location', (Join-Path $RepositoryRoot 'src'))
    $testsNode.SetAttribute('location', (Join-Path $RepositoryRoot 'tests'))
    $includeNode.SetAttribute('location', (Join-Path $RepositoryRoot 'src/platform'))
    $projectDocument.Save($projectConfiguration)

    Write-Warning "Stock base_process.ecf is unreadable; using generated overlay from $processSourceRoot"
    return $projectConfiguration
}
