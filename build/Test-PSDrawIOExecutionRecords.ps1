function Test-PSDrawIOExecutionRecords {
    <#
    .SYNOPSIS
        Warn when .agent/EXECUTION_RECORDS has untracked or modified files.
    .DESCRIPTION
        Opt-in archive integrity check for build scripts. Never throws - a
        missing or modified record must not fail a build or CI run. Records are
        append-only by convention; this makes tampering visible.
    .PARAMETER Root
        Repository root that may contain .agent/EXECUTION_RECORDS.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $recordsDir = Join-Path $Root '.agent/EXECUTION_RECORDS'
    if (-not (Test-Path -LiteralPath $recordsDir)) {
        return
    }

    Push-Location $Root
    try {
        $untracked = @(
            git -c core.quotepath=false ls-files --others --exclude-standard -- .agent/EXECUTION_RECORDS 2>$null
        ) | Where-Object { $_ -and $_.Trim() }

        foreach ($path in $untracked) {
            Write-Warning "EXECUTION_RECORDS untracked (will be lost if not committed): $path"
        }

        $modified = @(
            git -c core.quotepath=false diff --name-only -- .agent/EXECUTION_RECORDS 2>$null
        ) | Where-Object { $_ -and $_.Trim() }

        $staged = @(
            git -c core.quotepath=false diff --cached --name-only -- .agent/EXECUTION_RECORDS 2>$null
        ) | Where-Object { $_ -and $_.Trim() }

        foreach ($path in @($modified + $staged | Select-Object -Unique)) {
            Write-Warning "EXECUTION_RECORDS modified (records are write-once): $path"
        }
    } finally {
        Pop-Location
    }
}
