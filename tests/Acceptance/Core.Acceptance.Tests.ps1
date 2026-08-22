$script:coreRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script:specificationPath = Join-Path $script:coreRoot 'CORE.md'
# Without CORE.md, acceptanceLabels stays empty and the meta-test may pass
# trivially (empty foreach). That is intentional until the specification lands.
$script:acceptanceLabels = @(
    if (Test-Path -LiteralPath $script:specificationPath) {
        Select-String -Path $script:specificationPath -Pattern '^\- \[[ x]\] (.+)$' |
            ForEach-Object { $_.Matches[0].Groups[1].Value }
    }
)
$script:registeredAcceptanceLabels = @()

function Get-Label {
    param([Parameter(Mandatory)][string]$Match)

    $normalizedMatch = $Match.Replace('`', '')
    $hit = @($script:acceptanceLabels | Where-Object { $_.Replace('`', '') -like "*$normalizedMatch*" })
    if ($hit.Count -ne 1) { throw "Spec label '$Match' matched $($hit.Count) checkboxes" }
    $script:registeredAcceptanceLabels += $hit[0]
    $hit[0]
}

BeforeAll {
    if (-not $script:coreRoot) {
        $script:coreRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    }
    if (-not $script:specificationPath) {
        $script:specificationPath = Join-Path $script:coreRoot 'CORE.md'
    }
    # No module import until src/ exists. Acceptance Its that need the module
    # will fail loudly when CORE.md checkboxes require them.
    function Assert-ManualSignOff {
        # Sign-off cannot equal HEAD after the file is committed (hash moves).
        # Ancestry + committed drift: Commit must be a real commit; git diff
        # Commit HEAD may list only docs/SIGNOFF.json.
        # Working-tree drift is deliberately not checked - a sign-off records a
        # commit, not a working copy. CI has a clean tree; local dirt is transient.
        $signoffPath = Join-Path $script:coreRoot 'docs/SIGNOFF.json'
        $signoff = Get-Content -LiteralPath $signoffPath -Raw | ConvertFrom-Json
        $signoff.Commit | Should -Not -BeNullOrEmpty
        $commitType = git -C $script:coreRoot cat-file -t $signoff.Commit 2>$null
        $commitType | Should -Be 'commit'
        git -C $script:coreRoot merge-base --is-ancestor $signoff.Commit HEAD
        $LASTEXITCODE | Should -Be 0 -Because "sign-off Commit must be an ancestor of HEAD"

        # Working-tree drift is deliberately not checked (sign-off = commit, not WT).
        $committedDrift = @(
            git -C $script:coreRoot diff --name-only $signoff.Commit HEAD |
                Where-Object { $_ -and ($_ -ne 'docs/SIGNOFF.json') }
        )
        $committedDrift | Should -BeNullOrEmpty -Because "signed commit $($signoff.Commit) must match HEAD except docs/SIGNOFF.json; drifted: $($committedDrift -join ', ')"

        $signoff.Items | Should -Not -BeNullOrEmpty
        foreach ($item in @($signoff.Items)) {
            $item.Signed | Should -BeTrue -Because "sign-off item '$($item.Label)' must be Signed"
            $item.Signer | Should -Not -BeNullOrEmpty -Because "sign-off item '$($item.Label)' must name a Signer"
            $item.Date | Should -Not -BeNullOrEmpty -Because "sign-off item '$($item.Label)' must have a Date"
        }
    }
}

Describe 'PS.DrawIO.Core acceptance' -Tag Acceptance {
    # Checkbox-backed It blocks are added when CORE.md Definition of Done exists.
    # Get-Label matches both '- [ ]' and '- [x]' via the discovery pattern above.

    It 'has one acceptance It block for every CORE.md checkbox' -Tag Acceptance {
        # Without CORE.md the label list is empty and this It only confirms that
        # empty state - intentional until the specification lands. Once CORE.md
        # exists, empty labels are a defect (pattern mismatch or missing checkboxes).
        # Resolve path at run time: Pester 5 discovery/run scopes do not share
        # all discovery-time $script: assignments reliably.
        $coreRoot = if ($script:coreRoot) {
            $script:coreRoot
        }
        else {
            (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        }
        $specificationPath = Join-Path $coreRoot 'CORE.md'
        $labels = @(
            if (Test-Path -LiteralPath $specificationPath) {
                Select-String -Path $specificationPath -Pattern '^\- \[[ x]\] (.+)$' |
                    ForEach-Object { $_.Matches[0].Groups[1].Value }
            }
        )
        if (Test-Path -LiteralPath $specificationPath) {
            $labels |
                Should -Not -BeNullOrEmpty -Because 'CORE.md exists so acceptance labels must be non-empty'
        }
        $registered = @($script:registeredAcceptanceLabels)
        foreach ($label in $labels) {
            $registered | Should -Contain $label
        }
    }
}
