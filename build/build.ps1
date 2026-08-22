[CmdletBinding()]
param(
    [ValidateSet('All', 'Clean', 'Analyze', 'Test', 'Package')]
    [string]$Task = 'All'
)

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root 'src/PS.DrawIO.Core.psd1'
$packagePath = Join-Path $root 'dist/PS.DrawIO.Core'

. (Join-Path $PSScriptRoot 'Test-PSDrawIOHooksPath.ps1')
. (Join-Path $PSScriptRoot 'Assert-PSDrawIOPesterContainers.ps1')
Test-PSDrawIOHooksPath -Root $root

if ($Task -in 'All', 'Clean') {
    if (Test-Path $packagePath) { Remove-Item $packagePath -Recurse -Force }
}
if ($Task -in 'All', 'Analyze') {
    # TEMPORARY: remove this missing-src branch the moment src/ lands.
    # Reason: CI run #2 failed on both runners because Analyze targeted a
    # non-existent src/ and never reached the intentional meta-test failure.
    # See docs/DECISIONS/0002-analyze-skips-missing-source.md.
    $srcPath = Join-Path $root 'src'
    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Warning 'ScriptAnalyzer did NOT run: src/ is absent. This skip is temporary until src/ exists; remove this branch when source lands.'
    }
    else {
        $analysis = @(Invoke-ScriptAnalyzer -Path $srcPath -Recurse -Severity Error, Warning)
        if ($analysis.Count -gt 0) { $analysis | Format-List; throw 'ScriptAnalyzer reported errors or warnings.' }
    }
}
if ($Task -in 'All', 'Test') {
    $isCI = [bool]$env:CI -or [bool]$env:TF_BUILD -or [bool]$env:GITHUB_ACTIONS
    $result = Invoke-Pester (Join-Path $root 'tests') -PassThru
    if ($result.FailedCount -gt 0) {
        if ($isCI) { exit 1 }
        throw "Pester: $($result.FailedCount) test(s) failed."
    }
    try {
        Assert-PSDrawIOPesterContainers -Result $result
    } catch {
        if ($isCI) { exit 1 }
        throw
    }
}
if ($Task -in 'All', 'Package') {
    Test-ModuleManifest $manifestPath | Out-Null
    New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
    Copy-Item (Join-Path $root 'src/*') $packagePath -Recurse -Force
    Write-Output "Packaged module at $packagePath"
}
