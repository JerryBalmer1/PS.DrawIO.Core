function Test-PSDrawIOHooksPath {
    <#
    .SYNOPSIS
        Warn when .githooks/commit-msg exists but core.hooksPath is not .githooks.
    .DESCRIPTION
        Opt-in commit-msg hook check for build scripts. Never throws - missing
        hook config must not fail a build or CI run.
    .PARAMETER Root
        Repository root that may contain .githooks/commit-msg.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $commitMsgHook = Join-Path $Root '.githooks/commit-msg'
    if (-not (Test-Path -LiteralPath $commitMsgHook)) {
        return
    }

    Push-Location $Root
    try {
        $hooksPath = git config --get core.hooksPath 2>$null
    } finally {
        Pop-Location
    }

    $normalized = if ($hooksPath) { ($hooksPath -replace '\\', '/').TrimEnd('/') } else { '' }
    if ($normalized -ne '.githooks') {
        Write-Warning "core.hooksPath is not set to .githooks. Run: git config core.hooksPath .githooks"
    }
}
