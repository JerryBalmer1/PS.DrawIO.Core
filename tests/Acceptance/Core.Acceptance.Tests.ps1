[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'T-005: Pester 5 discovery/run are separate scopes; label registrations must survive re-exec via a process-global list cleared on each file load.'
)]
[CmdletBinding()]
param()
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
# T-005: Pester 5 re-executes the file for discovery then run; $script: is reset

# between those passes. Persist registrations in a process-global list and clear

# on each file load so the active pass owns the list.

if (-not $global:PSDrawIOCoreRegisteredAcceptanceLabels) {

    # PSScriptAnalyzer PSAvoidGlobalVars: required for discovery/run scope bridge (T-005)

    $global:PSDrawIOCoreRegisteredAcceptanceLabels = [System.Collections.Generic.List[string]]::new()

}

else {

    $global:PSDrawIOCoreRegisteredAcceptanceLabels.Clear()

}

$script:registeredAcceptanceLabels = $global:PSDrawIOCoreRegisteredAcceptanceLabels



function Get-Label {

    param([Parameter(Mandatory)][string]$Match)



    $normalizedMatch = $Match.Replace('`', '')

    $hit = @($script:acceptanceLabels | Where-Object { $_.Replace('`', '') -like "*$normalizedMatch*" })

    if ($hit.Count -ne 1) { throw "Spec label '$Match' matched $($hit.Count) checkboxes" }

    if ($global:PSDrawIOCoreRegisteredAcceptanceLabels -notcontains $hit[0]) {

        $null = $global:PSDrawIOCoreRegisteredAcceptanceLabels.Add($hit[0])

    }

    # Sanitize It display name only: Pester expands <x> as testcases; quotes/backticks break names

    $hit[0].

        Replace([string][char]34, [string][char]39).

        Replace([string][char]96, '').

        Replace('<', '[').

        Replace('>', ']')

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

    function Get-CoreRoot {
        if ($script:coreRoot) { return $script:coreRoot }
        return (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    }

    function Get-CoreManifestPath {
        Join-Path (Get-CoreRoot) 'src/PS.DrawIO.Core.psd1'
    }

    function Assert-CoreModuleAvailable {
        $manifest = Get-CoreManifestPath
        Test-Path -LiteralPath $manifest | Should -BeTrue -Because 'src/PS.DrawIO.Core.psd1 must exist'
        Import-Module $manifest -Force
    }

    # Minimal provider graph shaped like what Core is expected to consume.
    # Uses PSCustomObject so it can cross module boundaries without class identity.
    function Get-AcceptanceProviderGraph {
        param(
            [string]$Provider = 'PowerShell',
            [switch]$WithMissingEdgeEndpoint,
            [switch]$WithHtmlLabel,
            [switch]$WithGroup
        )

        $nodes = [System.Collections.Generic.List[object]]::new()
        $edges = [System.Collections.Generic.List[object]]::new()

        $nodes.Add([PSCustomObject]@{
                PSTypeName = 'PS.DrawIO.ProviderNode'
                Id         = "${Provider}:PSFunction:Get-Foo"
                Type       = 'PSFunction'
                Name       = 'Get-Foo'
                Label      = if ($WithHtmlLabel) { '<b>Get-Foo</b>' } else { 'Get-Foo' }
                Visibility = 'Public'
            })
        $nodes.Add([PSCustomObject]@{
                PSTypeName = 'PS.DrawIO.ProviderNode'
                Id         = "${Provider}:PSFunction:Set-Foo"
                Type       = 'PSFunction'
                Name       = 'Set-Foo'
                Label      = 'Set-Foo'
                Visibility = 'Public'
            })

        if ($WithGroup) {
            $groupId = "${Provider}:PSModule:Demo"
            $nodes.Add([PSCustomObject]@{
                    PSTypeName = 'PS.DrawIO.ProviderNode'
                    Id         = $groupId
                    Type       = 'PSModule'
                    Name       = 'Demo'
                    Label      = 'Demo'
                    IsGroup    = $true
                })
            # Nested child so parent-relative layout assertions have a non-empty set.
            # Only used when -WithGroup is set (currently one acceptance It).
            $nodes.Add([PSCustomObject]@{
                    PSTypeName = 'PS.DrawIO.ProviderNode'
                    Id         = "${Provider}:PSFunction:Invoke-Nested"
                    Type       = 'PSFunction'
                    Name       = 'Invoke-Nested'
                    Label      = 'Invoke-Nested'
                    Visibility = 'Private'
                    ParentId   = $groupId
                })
        }

        $to = if ($WithMissingEdgeEndpoint) {
            "${Provider}:PSFunction:Missing-Target"
        }
        else {
            "${Provider}:PSFunction:Set-Foo"
        }

        $edges.Add([PSCustomObject]@{
                PSTypeName = 'PS.DrawIO.ProviderEdge'
                From       = "${Provider}:PSFunction:Get-Foo"
                To         = $to
                Type       = 'Internal'
            })

        [PSCustomObject]@{
            PSTypeName  = 'PS.DrawIO.ProviderGraph'
            Provider    = $Provider
            Nodes       = @($nodes)
            Edges       = @($edges)
            LayoutHints = @(
                [PSCustomObject]@{
                    Kind    = 'Stack'
                    Targets = @("${Provider}:PSFunction:Get-Foo", "${Provider}:PSFunction:Set-Foo")
                }
            )
            LinkTemplate = 'vscode://file/{Path}:{Line}'
        }
    }

    function Get-EmittedDiagramXml {
        param([Parameter(Mandatory)]$IR, [string]$Path)

        if (-not $Path) {
            $Path = Join-Path $TestDrive ("core-accept-{0}.drawio" -f [guid]::NewGuid().ToString('N'))
        }
        Export-PSDrawIODiagram -IR $IR -Path $Path | Out-Null
        Test-Path -LiteralPath $Path | Should -BeTrue -Because 'Export-PSDrawIODiagram must write a file'
        return [pscustomobject]@{
            Path = $Path
            Text = Get-Content -LiteralPath $Path -Raw
        }
    }

    function Get-MxCellElement {
        param([Parameter(Mandatory)][string]$XmlText)
        $doc = [xml]$XmlText
        return @($doc.SelectNodes('//mxCell'))
    }
}

Describe 'PS.DrawIO.Core acceptance' -Tag Acceptance {
    # Checkbox-backed It blocks keyed to CORE.md §9 via Get-Label.
    # Get-Label matches both '- [ ]' and '- [x]' via the discovery pattern above.

    # -------------------------------------------------------------------------
    # Contract consumption
    # -------------------------------------------------------------------------

    It (Get-Label 'Resolves each semantic type through an injected resolver') -Tag Acceptance {
        # Seam only (ADR 0004): Core accepts an injected resolver and applies
        # whatever declaration is returned. No live registry; no invented style.
        Assert-CoreModuleAvailable

        $convert = Get-Command -Name ConvertTo-PSDrawIOIR -ErrorAction Stop
        $convert.Parameters.Keys | Should -Contain 'Resolver' -Because 'ConvertTo-PSDrawIOIR must accept an injected resolver'

        $graph = Get-AcceptanceProviderGraph
        $knownStyle = 'rounded=1;whiteSpace=wrap;html=1;'
        $resolverWithStyle = {
            param($Provider, $Type)
            [pscustomobject]@{
                Style        = $knownStyle
                LinkTemplate = 'vscode://file/{path}:{line}'
            }
        }
        $irStyled = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider -Resolver $resolverWithStyle
        $irStyled | Should -Not -BeNullOrEmpty
        $styled = @($irStyled.Nodes | Where-Object {
                ($null -ne $_.PSObject.Properties['Style'] -and [string]$_.Style -eq $knownStyle) -or
                ($null -ne $_.PSObject.Properties['ResolvedStyle'] -and [string]$_.ResolvedStyle -eq $knownStyle) -or
                ($null -ne $_.PSObject.Properties['ShapeStyle'] -and [string]$_.ShapeStyle -eq $knownStyle)
            })
        $styled.Count | Should -BeGreaterThan 0 -Because 'declaration content returned by the resolver must appear on the IR node'

        $resolverNoStyle = {
            param($Provider, $Type)
            [pscustomobject]@{
                LinkTemplate = 'vscode://file/{path}:{line}'
            }
        }
        $irBare = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider -Resolver $resolverNoStyle
        $invented = @($irBare.Nodes | Where-Object {
                ($null -ne $_.PSObject.Properties['Style'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Style)) -or
                ($null -ne $_.PSObject.Properties['ResolvedStyle'] -and -not [string]::IsNullOrWhiteSpace([string]$_.ResolvedStyle)) -or
                ($null -ne $_.PSObject.Properties['ShapeStyle'] -and -not [string]::IsNullOrWhiteSpace([string]$_.ShapeStyle))
            })
        $invented | Should -BeNullOrEmpty -Because 'a declaration with no Style must not produce an invented style, and that is not an error'
    }

    It (Get-Label 'A resolver failure surfaces as a terminating error') -Tag Acceptance {
        # Seam only (ADR 0004): Core surfaces resolver throw/null as a terminating
        # error naming type and provider. No live registry; no registration check.
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $typeName = [string]$graph.Nodes[0].Type
        $providerName = [string]$graph.Provider

        $throwingResolver = {
            param($Provider, $Type)
            throw "resolver double refused type $Type"
        }
        { ConvertTo-PSDrawIOIR -Graph $graph -Provider $providerName -Resolver $throwingResolver -ErrorAction Stop } |
            Should -Throw -Because 'a resolver that throws must surface as a terminating error'
        try {
            ConvertTo-PSDrawIOIR -Graph $graph -Provider $providerName -Resolver $throwingResolver -ErrorAction Stop
        }
        catch {
            $_.Exception.Message | Should -Match ([regex]::Escape($typeName)) -Because 'throw path must name the type'
            $_.Exception.Message | Should -Match ([regex]::Escape($providerName)) -Because 'throw path must name the provider'
        }

        $nullResolver = {
            param($Provider, $Type)
            $null
        }
        { ConvertTo-PSDrawIOIR -Graph $graph -Provider $providerName -Resolver $nullResolver -ErrorAction Stop } |
            Should -Throw -Because 'a resolver that returns null must not be silently skipped'
        try {
            ConvertTo-PSDrawIOIR -Graph $graph -Provider $providerName -Resolver $nullResolver -ErrorAction Stop
        }
        catch {
            $_.Exception.Message | Should -Match ([regex]::Escape($typeName)) -Because 'null path must name the type'
            $_.Exception.Message | Should -Match ([regex]::Escape($providerName)) -Because 'null path must name the provider'
        }
    }

    It (Get-Label 'LinkTemplate') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $template = [string]$graph.LinkTemplate
        $template | Should -Not -BeNullOrEmpty -Because 'fixture must supply a LinkTemplate value to assert'
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $emitted = Get-EmittedDiagramXml -IR $ir
        $emitted.Text | Should -Match 'UserObject' -Because 'LinkTemplate emission wraps vertices in UserObject'
        # Emit resolves {Path}/{Line}; assert the fixture template's value survives that path.
        $expectedLink = $template -replace '\{Path\}', '' -replace '\{Line\}', ''
        $emitted.Text | Should -Match ([regex]::Escape($expectedLink)) -Because 'emitted link must carry the fixture LinkTemplate value'
    }

    It (Get-Label 'LayoutHints') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $ir.LayoutHints | Should -Not -BeNullOrEmpty -Because 'LayoutHints must be carried into IR for the layout strategy'

        # Convert must not interpret geometry — coordinates belong to the layout pass only.
        $preLayoutWithGeometry = @($ir.Nodes | Where-Object {
                ($null -ne $_.PSObject.Properties['X'] -and $null -ne $_.X) -or
                ($null -ne $_.PSObject.Properties['Y'] -and $null -ne $_.Y) -or
                ($null -ne $_.PSObject.Properties['Width'] -and $null -ne $_.Width) -or
                ($null -ne $_.PSObject.Properties['Height'] -and $null -ne $_.Height)
            })
        $preLayoutWithGeometry | Should -BeNullOrEmpty -Because 'convert must not stamp geometry; layout strategy owns coordinates'

        # Prove LayoutHints are handed to the layout strategy (not merely present on IR).
        $layoutCmd = Get-Command -Name 'Invoke-PSDrawIOLayout' -ErrorAction SilentlyContinue
        $layoutCmd | Should -Not -BeNullOrEmpty -Because 'LayoutHints hand-off requires the named layout strategy seam'
        $hintBox = [pscustomobject]@{ Received = $null }
        $spy = {
            param($IR)
            $hintBox.Received = @($IR.LayoutHints)
            foreach ($n in @($IR.Nodes)) {
                $n | Add-Member -NotePropertyName X -NotePropertyValue 1 -Force
                $n | Add-Member -NotePropertyName Y -NotePropertyValue 1 -Force
                $n | Add-Member -NotePropertyName Width -NotePropertyValue 10 -Force
                $n | Add-Member -NotePropertyName Height -NotePropertyValue 10 -Force
            }
            $IR
        }.GetNewClosure()
        $null = Invoke-PSDrawIOLayout -IR $ir -Strategy $spy
        $hintBox.Received | Should -Not -BeNullOrEmpty -Because 'layout strategy must receive LayoutHints from the IR'
    }

    It (Get-Label 'No provider vocabulary') -Tag Acceptance {
        $root = Get-CoreRoot
        $src = Join-Path $root 'src'
        Test-Path -LiteralPath $src | Should -BeTrue -Because 'src/ must exist to enforce no hardcoded provider vocabulary'
        # Provider-specific type names must not be hardcoded as Core domain vocabulary.
        $hits = @(
            Get-ChildItem -LiteralPath $src -Recurse -Include *.ps1, *.psm1, *.psd1 |
                Select-String -Pattern '\bPSFunction\b|\bPSClass\b|\bPSEnum\b|\bPSModuleGraph\b' |
                Where-Object { $_.Path -notmatch '\\(tests|docs)\\' }
        )
        $hits | Should -BeNullOrEmpty -Because ("Core must not hardcode provider vocabulary; hits: {0}" -f (
                ($hits | ForEach-Object { '{0}:{1}' -f $_.Path, $_.LineNumber }) -join '; '))
    }

    # -------------------------------------------------------------------------
    # Intermediate representation
    # -------------------------------------------------------------------------

    It (Get-Label 'ConvertTo-PSDrawIOIR') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $ir | Should -Not -BeNullOrEmpty
        @($ir.Nodes).Count | Should -BeGreaterThan 0
        @($ir.Edges).Count | Should -BeGreaterThan 0
    }

    It (Get-Label 'provider-qualified') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        foreach ($node in @($ir.Nodes)) {
            $node.Id | Should -Match '^[^:]+:[^:]+:.+$' -Because "IR node Id '$($node.Id)' must be Provider:Type:Name"
        }
    }

    It (Get-Label 'names a node absent') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph -WithMissingEdgeEndpoint
        { ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider -ErrorAction Stop } |
            Should -Throw -Because 'edges naming absent nodes must be rejected, not dropped'
    }

    It (Get-Label 'PSTypeName') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $ir -is [PSCustomObject] | Should -BeTrue -Because 'IR must cross boundaries as PSCustomObject, not a class instance'
        @($ir.PSObject.TypeNames) | Should -Not -BeNullOrEmpty
        $ir.PSObject.TypeNames[0] | Should -Not -Be 'System.Management.Automation.PSCustomObject'
        $ir.GetType().FullName | Should -Be 'System.Management.Automation.PSCustomObject'
    }

    It (Get-Label 'round-trips through JSON') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $json = $ir | ConvertTo-Json -Depth 20
        $round = $json | ConvertFrom-Json
        ($round | ConvertTo-Json -Depth 20) | Should -Be ($ir | ConvertTo-Json -Depth 20)
    }

    # -------------------------------------------------------------------------
    # Layout
    # -------------------------------------------------------------------------

    It (Get-Label 'named strategy interface') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $cmd = Get-Command -Name 'Invoke-PSDrawIOLayout' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty -Because 'layout must be invoked through a named strategy interface (Invoke-PSDrawIOLayout)'
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $laidOut | Should -Not -BeNullOrEmpty
    }

    It (Get-Label 'One built-in strategy') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $vertices = @($laidOut.Nodes | Where-Object { -not $_.IsEdge })
        $vertices.Count | Should -BeGreaterThan 0
        foreach ($v in $vertices) {
            $null -ne $v.X -or $null -ne $v.Geometry.X | Should -BeTrue -Because "vertex $($v.Id) must receive coordinates"
            $null -ne $v.Y -or $null -ne $v.Geometry.Y | Should -BeTrue -Because "vertex $($v.Id) must receive coordinates"
        }
    }

    It (Get-Label 'test double strategy') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $double = {
            param($IR)
            foreach ($n in @($IR.Nodes)) {
                $n | Add-Member -NotePropertyName X -NotePropertyValue 42 -Force
                $n | Add-Member -NotePropertyName Y -NotePropertyValue 42 -Force
                $n | Add-Member -NotePropertyName Width -NotePropertyValue 10 -Force
                $n | Add-Member -NotePropertyName Height -NotePropertyValue 10 -Force
            }
            $IR
        }
        $laidOut = Invoke-PSDrawIOLayout -IR $ir -Strategy $double
        $first = @($laidOut.Nodes)[0]
        $x = if ($null -ne $first.X) { $first.X } else { $first.Geometry.X }
        $x | Should -Be 42 -Because 'substituting a test double must prove the layout seam is real'
    }

    It (Get-Label 'non-zero') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $cells = Get-MxCellElement -XmlText $emitted.Text | Where-Object { $_.vertex -eq '1' }
        $cells.Count | Should -BeGreaterThan 0
        foreach ($cell in $cells) {
            $geo = $cell.mxGeometry
            [double]$geo.width | Should -BeGreaterThan 0 -Because "vertex cell $($cell.id) width must be non-zero"
            [double]$geo.height | Should -BeGreaterThan 0 -Because "vertex cell $($cell.id) height must be non-zero"
        }
    }

    It (Get-Label 'sibling vertices overlap') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $vertices = @(Get-MxCellElement -XmlText $emitted.Text | Where-Object { $_.vertex -eq '1' })
        $vertices.Count | Should -BeGreaterThan 1 -Because 'overlap check needs at least two siblings'
        for ($i = 0; $i -lt $vertices.Count; $i++) {
            for ($j = $i + 1; $j -lt $vertices.Count; $j++) {
                if ($vertices[$i].parent -ne $vertices[$j].parent) { continue }
                $a = $vertices[$i].mxGeometry
                $b = $vertices[$j].mxGeometry
                $aRight = [double]$a.x + [double]$a.width
                $aBottom = [double]$a.y + [double]$a.height
                $bRight = [double]$b.x + [double]$b.width
                $bBottom = [double]$b.y + [double]$b.height
                $overlap = -not ([double]$a.x -ge $bRight -or [double]$b.x -ge $aRight -or [double]$a.y -ge $bBottom -or [double]$b.y -ge $aBottom)
                $overlap | Should -BeFalse -Because "sibling cells $($vertices[$i].id) and $($vertices[$j].id) must not overlap"
            }
        }
    }

    It (Get-Label 'relative to the parent') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph -WithGroup
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $cells = Get-MxCellElement -XmlText $emitted.Text
        $group = @($cells | Where-Object { $_.id -match 'PSModule:Demo' -or $_.value -eq 'Demo' }) | Select-Object -First 1
        $group | Should -Not -BeNullOrEmpty -Because 'group vertex must be emitted'
        $parentX = [double]$group.mxGeometry.x
        $parentY = [double]$group.mxGeometry.y
        # Parent must sit at a non-zero canvas origin so relative vs absolute can differ.
        # Relative children are measured from the parent origin (small pad); absolute
        # children include the parent's canvas offset and are therefore not smaller
        # than the parent on both axes.
        $parentX | Should -BeGreaterThan 0 -Because 'group must be placed at a non-zero canvas X so relative/absolute can be distinguished'
        $parentY | Should -BeGreaterThan 0 -Because 'group must be placed at a non-zero canvas Y so relative/absolute can be distinguished'
        $children = @($cells | Where-Object { $_.parent -eq $group.id -and $_.vertex -eq '1' })
        $children.Count | Should -BeGreaterThan 0 -Because 'group must contain child vertices'
        foreach ($child in $children) {
            $cx = [double]$child.mxGeometry.x
            $cy = [double]$child.mxGeometry.y
            $cx | Should -BeLessThan $parentX -Because "child X ($cx) must be parent-relative (smaller than parent canvas X $parentX); absolute placement is not"
            $cy | Should -BeLessThan $parentY -Because "child Y ($cy) must be parent-relative (smaller than parent canvas Y $parentY); absolute placement is not"
        }
    }

    It (Get-Label 'Zero geometry constants') -Tag Acceptance {
        $root = Get-CoreRoot
        $src = Join-Path $root 'src'
        Test-Path -LiteralPath $src | Should -BeTrue -Because 'src/ must exist to enforce zero geometry constants outside layout'
        $layoutPaths = @(
            Get-ChildItem -LiteralPath $src -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Layout' } |
                ForEach-Object FullName
        )
        $layoutPaths.Count | Should -BeGreaterThan 0 -Because 'a layout pass must exist under src/'
        # Heuristic: absolute geometry literals (width/height/x/y assignments with numeric literals)
        # outside paths that contain 'Layout' are forbidden.
        $pattern = '(?i)(\bwidth\b|\bheight\b|\bgeometry\b|\bmxGeometry\b).{0,40}(-?\d{2,})'
        $hits = @(
            Get-ChildItem -LiteralPath $src -Recurse -Include *.ps1, *.psm1 |
                Where-Object { $_.FullName -notmatch 'Layout' } |
                Select-String -Pattern $pattern
        )
        $hits | Should -BeNullOrEmpty -Because ("geometry constants must stay in the layout pass; hits: {0}" -f (
                ($hits | ForEach-Object { '{0}:{1}' -f $_.Path, $_.LineNumber }) -join '; '))
    }

    # -------------------------------------------------------------------------
    # Emission
    # -------------------------------------------------------------------------

    It (Get-Label 'Export-PSDrawIODiagram') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $path = Join-Path $TestDrive 'export-basic.drawio'
        Export-PSDrawIODiagram -IR $laidOut -Path $path
        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Item -LiteralPath $path).Length | Should -BeGreaterThan 0
    }

    It (Get-Label 'mxCell id="0"') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $emitted.Text | Should -Match '<mxCell\s+id="0"\s*/>'
        $emitted.Text | Should -Match '<mxCell\s+id="1"[^>]*parent="0"'
    }

    It (Get-Label 'uncompressed XML') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $emitted.Text | Should -Match '<mxfile\b'
        $emitted.Text | Should -Match '<mxGraphModel\b'
        $emitted.Text | Should -Not -Match 'compressed="true"'
        # Compressed diagrams typically base64-deflate the diagram body; reject that shape.
        $emitted.Text | Should -Not -Match '(?s)<diagram[^>]*>\s*[A-Za-z0-9+/]{80,}={0,2}\s*</diagram>'
    }

    It (Get-Label 'no XML comments') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $emitted.Text | Should -Not -Match '<!--'
    }

    It (Get-Label 'Cell ids are unique') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $ids = @(Get-MxCellElement -XmlText $emitted.Text | ForEach-Object { $_.id })
        $ids.Count | Should -BeGreaterThan 0
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It (Get-Label 'never appear on the same cell') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $both = @(Get-MxCellElement -XmlText $emitted.Text | Where-Object { $_.vertex -eq '1' -and $_.edge -eq '1' })
        $both | Should -BeNullOrEmpty -Because 'vertex=1 and edge=1 must never appear on the same cell'
    }

    It (Get-Label 'HTML in a') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph -WithHtmlLabel
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $emitted.Text | Should -Not -Match 'value="[^"]*<b>'
        $emitted.Text | Should -Match '&lt;b&gt;|value="&lt;'
    }

    It (Get-Label 'perimeter=') -Tag Acceptance {
        Assert-CoreModuleAvailable
        # Non-rectangular shape: ellipse (or any shape whose Registry style declares a perimeter).
        $graph = Get-AcceptanceProviderGraph
        $graph.Nodes[0].Type = 'PSFunction'
        $graph.Nodes[0] | Add-Member -NotePropertyName Shape -NotePropertyValue 'ellipse' -Force
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $emitted.Text | Should -Match 'perimeter='
    }

    # -------------------------------------------------------------------------
    # Correctness gates
    # -------------------------------------------------------------------------

    It (Get-Label 'mxfile.xsd') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $root = Get-CoreRoot
        $xsd = Get-ChildItem -LiteralPath $root -Recurse -Filter 'mxfile.xsd' -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        $xsd | Should -Not -BeNullOrEmpty -Because 'mxfile.xsd must be available in-repo for in-process validation'
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut

        $schemaSet = [System.Xml.Schema.XmlSchemaSet]::new()
        $null = $schemaSet.Add('', $xsd)
        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.ValidationType = [System.Xml.ValidationType]::Schema
        $settings.Schemas = $schemaSet
        $validationErrors = [System.Collections.Generic.List[string]]::new()
        $handler = [System.Xml.Schema.ValidationEventHandler] {
            param($eventSender, $validationEvent)
            $null = $eventSender
            $validationErrors.Add($validationEvent.Message)
        }
        $settings.add_ValidationEventHandler($handler)
        $reader = [System.Xml.XmlReader]::Create($emitted.Path, $settings)
        try {
            while ($reader.Read()) { }
        }
        finally {
            $reader.Dispose()
        }
        $validationErrors | Should -BeNullOrEmpty -Because ("emission must validate against mxfile.xsd; errors: {0}" -f ($validationErrors -join '; '))
    }

    It (Get-Label 'fails schema validation') -Tag Acceptance {
        Assert-CoreModuleAvailable
        # Schema-failure naming is a distinct seam. Do not substitute IR identity rejection (T-015).
        $validator = Get-Command -Name 'Test-PSDrawIODiagramSchema' -ErrorAction SilentlyContinue
        $validator | Should -Not -BeNullOrEmpty -Because 'schema-failure naming requires Test-PSDrawIODiagramSchema; do not substitute IR identity rejection'
        { Test-PSDrawIODiagramSchema -Content '<not-valid-mxfile/>' -ErrorAction Stop } |
            Should -Throw
        try {
            Test-PSDrawIODiagramSchema -Content '<not-valid-mxfile/>' -ErrorAction Stop
        }
        catch {
            # \bschema\b — checkbox language; rejects IR identity noise (invalid/node/mxfile).
            # Prefer over XmlSchema: that is a .NET type name, not the user-facing contract word.
            $_.Exception.Message | Should -Match '\bschema\b'
        }
    }

    It (Get-Label 'file Core wrote') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $path = Join-Path $TestDrive 'roundtrip-core.drawio'
        Export-PSDrawIODiagram -IR $laidOut -Path $path
        $parseCmd = Get-Command -Name 'Import-PSDrawIODiagram' -ErrorAction SilentlyContinue
        $parseCmd | Should -Not -BeNullOrEmpty -Because 'parse→emit→parse requires Import-PSDrawIODiagram'
        $parsed1 = Import-PSDrawIODiagram -Path $path
        $path2 = Join-Path $TestDrive 'roundtrip-core-2.drawio'
        Export-PSDrawIODiagram -IR $parsed1 -Path $path2
        $parsed2 = Import-PSDrawIODiagram -Path $path2
        ($parsed2 | ConvertTo-Json -Depth 20) | Should -Be ($parsed1 | ConvertTo-Json -Depth 20)
    }

    It (Get-Label 'hand-edited') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $parseCmd = Get-Command -Name 'Import-PSDrawIODiagram' -ErrorAction SilentlyContinue
        $parseCmd | Should -Not -BeNullOrEmpty -Because 'parse→emit→parse requires Import-PSDrawIODiagram'
        $hand = @'
<mxfile host="app.diagrams.net">
  <diagram id="hand" name="Page-1">
    <mxGraphModel dx="1" dy="1" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <mxCell id="hand-1" value="Hand" style="rounded=0;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="80" height="40" as="geometry"/>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
'@
        $path = Join-Path $TestDrive 'hand-edited.drawio'
        Set-Content -LiteralPath $path -Value $hand -Encoding utf8
        $parsed1 = Import-PSDrawIODiagram -Path $path
        $path2 = Join-Path $TestDrive 'hand-edited-2.drawio'
        Export-PSDrawIODiagram -IR $parsed1 -Path $path2
        $parsed2 = Import-PSDrawIODiagram -Path $path2
        ($parsed2 | ConvertTo-Json -Depth 20) | Should -Be ($parsed1 | ConvertTo-Json -Depth 20)
    }

    It (Get-Label 'Unknown attributes') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $parseCmd = Get-Command -Name 'Import-PSDrawIODiagram' -ErrorAction SilentlyContinue
        $parseCmd | Should -Not -BeNullOrEmpty
        $hand = @'
<mxfile host="app.diagrams.net" agent="accept-test">
  <diagram id="u" name="Page-1">
    <mxGraphModel>
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <mxCell id="u1" value="X" style="whiteSpace=wrap;" vertex="1" parent="1" customAttr="keep-me">
          <mxGeometry x="10" y="10" width="40" height="20" as="geometry"/>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
'@
        $path = Join-Path $TestDrive 'unknown-attr.drawio'
        Set-Content -LiteralPath $path -Value $hand -Encoding utf8
        $parsed = Import-PSDrawIODiagram -Path $path
        $out = Join-Path $TestDrive 'unknown-attr-out.drawio'
        Export-PSDrawIODiagram -IR $parsed -Path $out
        (Get-Content -LiteralPath $out -Raw) | Should -Match 'customAttr="keep-me"'
    }

    It (Get-Label 'golden-file corpus') -Tag Acceptance {
        $root = Get-CoreRoot
        $goldenDir = Join-Path $root 'tests/Fixtures/Golden'
        Test-Path -LiteralPath $goldenDir | Should -BeTrue -Because 'a golden-file corpus directory must exist'
        $goldens = @(Get-ChildItem -LiteralPath $goldenDir -Filter '*.drawio' -File -ErrorAction SilentlyContinue)
        $goldens.Count | Should -BeGreaterThan 0 -Because 'golden-file corpus must contain at least one .drawio file'
        Assert-CoreModuleAvailable
        foreach ($g in $goldens) {
            $ir = Import-PSDrawIODiagram -Path $g.FullName
            $actualPath = Join-Path $TestDrive ("golden-actual-{0}" -f $g.Name)
            Export-PSDrawIODiagram -IR $ir -Path $actualPath
            $expected = Get-Content -LiteralPath $g.FullName -Raw
            $actual = Get-Content -LiteralPath $actualPath -Raw
            $actual | Should -Be $expected -Because "golden file $($g.Name) must match re-emission; a change fails the suite"
        }
    }

    # -------------------------------------------------------------------------
    # Proof
    # -------------------------------------------------------------------------

    It (Get-Label 'Provider.PowerShell') -Tag Acceptance, ManualSignOff {

        # Machine half: end-to-end render must produce a .drawio file.

        # Human half: "opens in draw.io" is countersigned in docs/SIGNOFF.json.

        Assert-CoreModuleAvailable

        $providerRoot = Join-Path (Split-Path (Get-CoreRoot) -Parent) 'PS.DrawIO.Provider.PowerShell'

        Test-Path -LiteralPath $providerRoot | Should -BeTrue -Because 'Provider.PowerShell checkout is required for the end-to-end proof'

        Import-Module (Join-Path $providerRoot 'src/PS.DrawIO.Provider.PowerShell.psd1') -Force

        $session = New-PSDrawIOPSAnalysis -Path (Join-Path $providerRoot 'src')

        $graph = Build-PSDrawIOPSGraph -Session $session

        $ir = ConvertTo-PSDrawIOIR -Graph $graph

        $laidOut = Invoke-PSDrawIOLayout -IR $ir

        $path = Join-Path $TestDrive 'provider-powershell-self.drawio'

        Export-PSDrawIODiagram -IR $laidOut -Path $path

        Test-Path -LiteralPath $path | Should -BeTrue

        $text = Get-Content -LiteralPath $path -Raw

        $text | Should -Match '<mxfile\b'

        $text | Should -Match '<mxGraphModel\b'

        $text | Should -Match '<mxCell\s+id="0"'

        $text | Should -Match '<mxCell\s+id="1"'

        { [xml]$text } | Should -Not -Throw

        Assert-ManualSignOff

    }

    It (Get-Label 'pile at the origin') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $graph = Get-AcceptanceProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $emitted = Get-EmittedDiagramXml -IR $laidOut
        $vertices = @(Get-MxCellElement -XmlText $emitted.Text | Where-Object { $_.vertex -eq '1' })
        $vertices.Count | Should -BeGreaterThan 1
        $origins = @($vertices | Where-Object {
                [double]$_.mxGeometry.x -eq 0 -and [double]$_.mxGeometry.y -eq 0
            })
        $origins.Count | Should -BeLessThan $vertices.Count -Because 'not every vertex may sit at the origin (pile)'
        $points = @($vertices | ForEach-Object { '{0},{1}' -f $_.mxGeometry.x, $_.mxGeometry.y } | Select-Object -Unique)
        $points.Count | Should -BeGreaterThan 1 -Because 'vertices must not all share one coordinate (asserted, not eyeballed)'
    }

    It (Get-Label 'deliberately malformed IR') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $bad = [PSCustomObject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Nodes      = @(
                [PSCustomObject]@{ Id = 'PowerShell:PSFunction:Good'; Type = 'PSFunction'; Name = 'Good' }
            )
            Edges      = @(
                [PSCustomObject]@{
                    From = 'PowerShell:PSFunction:Good'
                    To   = 'PowerShell:PSFunction:MissingNode'
                    Type = 'Internal'
                }
            )
        }
        { Export-PSDrawIODiagram -IR $bad -Path (Join-Path $TestDrive 'malformed.drawio') -ErrorAction Stop } |
            Should -Throw
        try {
            Export-PSDrawIODiagram -IR $bad -Path (Join-Path $TestDrive 'malformed.drawio') -ErrorAction Stop
        }
        catch {
            # Fixture-specific identity only — bare 'node' matched unrelated IR errors (T-015).
            $_.Exception.Message | Should -Match 'MissingNode|PowerShell:PSFunction:MissingNode|offending'
        }
    }

    # -------------------------------------------------------------------------
    # Quality gates
    # -------------------------------------------------------------------------

    It (Get-Label 'Pester 5 green') -Tag Acceptance, ManualSignOff {
        $root = Get-CoreRoot
        $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7
        $workflow = Get-Content (Join-Path $root '.github/workflows/ci.yml') -Raw
        $workflow | Should -Match 'windows-latest'
        $workflow | Should -Match 'ubuntu-latest'
        $workflow | Should -Match 'pwsh'
        # Cross-OS green is attested via signed SIGNOFF (CI matrix proof + human countersign).
        Assert-ManualSignOff
    }

    It (Get-Label 'Coverage') -Tag Acceptance {
        $root = Get-CoreRoot
        $unit = Join-Path $root 'tests/Unit'
        $public = Join-Path $root 'src/Public'
        Test-Path -LiteralPath $unit | Should -BeTrue -Because 'tests/Unit must exist for coverage'
        Test-Path -LiteralPath $public | Should -BeTrue -Because 'src/Public must exist for coverage'
        $publicCoverage = Invoke-Pester $unit -CodeCoverage (Join-Path $public '*.ps1') -PassThru
        $overallCoverage = Invoke-Pester $unit -CodeCoverage (Join-Path $root 'src/**/*.ps1') -PassThru
        $publicCoverage.CodeCoverage.CoveragePercent | Should -BeGreaterOrEqual 90
        $overallCoverage.CodeCoverage.CoveragePercent | Should -BeGreaterOrEqual 80
    }

    It (Get-Label 'PSScriptAnalyzer') -Tag Acceptance {
        $root = Get-CoreRoot
        $src = Join-Path $root 'src'
        Test-Path -LiteralPath $src | Should -BeTrue -Because 'src/ must exist for PSScriptAnalyzer'
        Invoke-ScriptAnalyzer -Path $src -Recurse -Severity Error, Warning | Should -BeNullOrEmpty
    }

    It (Get-Label 'Test-ModuleManifest') -Tag Acceptance {
        $manifest = Get-CoreManifestPath
        Test-Path -LiteralPath $manifest | Should -BeTrue -Because 'module manifest must exist'
        Test-ModuleManifest $manifest | Should -Not -BeNullOrEmpty
    }

    It (Get-Label 'Imports clean') -Tag Acceptance {
        $manifest = Get-CoreManifestPath
        Test-Path -LiteralPath $manifest | Should -BeTrue -Because 'module manifest must exist'
        $command = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$manifest' -Force
(Get-Module PS.DrawIO.Core).Name
(Get-Command ConvertTo-PSDrawIOIR -Module PS.DrawIO.Core).Name
(Get-Command Export-PSDrawIODiagram -Module PS.DrawIO.Core).Name
"@
        $output = & pwsh -NoLogo -NoProfile -NonInteractive -Command $command 2>&1
        $LASTEXITCODE | Should -Be 0
        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        $output | Should -Contain 'PS.DrawIO.Core'
        $output | Should -Contain 'ConvertTo-PSDrawIOIR'
        $output | Should -Contain 'Export-PSDrawIODiagram'
    }

    It (Get-Label 'exceeds 100 lines') -Tag Acceptance {
        $public = Join-Path (Get-CoreRoot) 'src/Public'
        Test-Path -LiteralPath $public | Should -BeTrue -Because 'src/Public must exist'
        $files = @(Get-ChildItem -LiteralPath $public -Filter '*.ps1' -File)
        $files.Count | Should -BeGreaterThan 0 -Because 'src/Public must contain functions'
        foreach ($f in $files) {
            @(Get-Content -LiteralPath $f.FullName).Count | Should -BeLessOrEqual 100 -Because "$($f.Name) must not exceed 100 lines"
        }
    }

    It (Get-Label 'approved verbs') -Tag Acceptance {
        Assert-CoreModuleAvailable
        $commands = (Get-Module PS.DrawIO.Core).ExportedCommands.Keys
        @($commands).Count | Should -BeGreaterThan 0 -Because 'module must export commands'
        foreach ($name in $commands) {
            $verb = ($name -split '-', 2)[0]
            (Get-Verb $verb).Verb | Should -Not -BeNullOrEmpty -Because "$name must use an approved verb"
        }
    }

    # -------------------------------------------------------------------------
    # Documentation
    # -------------------------------------------------------------------------

    It (Get-Label 'README.md') -Tag Acceptance {
        $readmePath = Join-Path (Get-CoreRoot) 'README.md'
        Test-Path -LiteralPath $readmePath | Should -BeTrue
        $lines = @(Get-Content -LiteralPath $readmePath | Where-Object { $_.Trim() })
        $lines.Count | Should -BeLessOrEqual 20 -Because 'install → resolve → render must fit under 20 non-empty lines'
        $raw = Get-Content -LiteralPath $readmePath -Raw
        $raw | Should -Match 'ConvertTo-PSDrawIOIR|Export-PSDrawIODiagram'
        $raw | Should -Match 'Resolve-PSDrawIOShape|Register-PSDrawIOProvider|PS\.DrawIO\.Registry'
    }

    It (Get-Label 'IR-SCHEMA.md') -Tag Acceptance {
        $path = Join-Path (Get-CoreRoot) 'docs/IR-SCHEMA.md'
        Test-Path -LiteralPath $path | Should -BeTrue
        $raw = Get-Content -LiteralPath $path -Raw
        $raw | Should -Match 'Provider:Type:Name|PSTypeName|ConvertTo-PSDrawIOIR'
    }

    It (Get-Label 'LIMITATIONS.md') -Tag Acceptance {
        $path = Join-Path (Get-CoreRoot) 'docs/LIMITATIONS.md'
        Test-Path -LiteralPath $path | Should -BeTrue
        $raw = Get-Content -LiteralPath $path -Raw
        $raw | Should -Match 'layout'
    }

    It (Get-Label 'CHANGELOG.md') -Tag Acceptance {
        $path = Join-Path (Get-CoreRoot) 'CHANGELOG.md'
        Test-Path -LiteralPath $path | Should -BeTrue
        $raw = Get-Content -LiteralPath $path -Raw
        $raw | Should -Match '\[Unreleased\]'
        # Keep a Changelog + v1 surface: once the module ships, changelog must name public commands.
        $manifest = Get-CoreManifestPath
        Test-Path -LiteralPath $manifest | Should -BeTrue -Because 'CHANGELOG tracks a shipping module'
        $raw | Should -Match 'ConvertTo-PSDrawIOIR|Export-PSDrawIODiagram'
    }

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
        $registered = @(

            if ($global:PSDrawIOCoreRegisteredAcceptanceLabels) {

                $global:PSDrawIOCoreRegisteredAcceptanceLabels

            }

            else {

                $script:registeredAcceptanceLabels

            }

        )

        $registered | Should -Not -BeNullOrEmpty -Because 'Get-Label must have registered checkbox labels during discovery/load'

        foreach ($label in $labels) {

            $registered | Should -Contain $label

        }

        $registered.Count | Should -Be $labels.Count
    }
}
