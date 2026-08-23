#Requires -Version 7.0
Describe 'PS.DrawIO.Core IR unit' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        Import-Module (Join-Path $root 'src/PS.DrawIO.Core.psd1') -Force

        # Pester 5: helpers defined at Describe body are discovery-scoped only.
        function script:New-UnitProviderGraph {
            param(
                [switch] $WithMissingEdgeEndpoint,
                [switch] $OmitProviderProperty
            )

            $to = if ($WithMissingEdgeEndpoint) {
                'Demo:Widget:Missing-Target'
            }
            else {
                'Demo:Widget:Set-Item'
            }

            $graph = [ordered]@{
                Nodes        = @(
                    [pscustomobject]@{
                        Id    = 'Demo:Widget:Get-Item'
                        Type  = 'Widget'
                        Name  = 'Get-Item'
                        Label = 'Get-Item'
                    }
                    [pscustomobject]@{
                        Id    = 'Demo:Widget:Set-Item'
                        Type  = 'Widget'
                        Name  = 'Set-Item'
                        Label = 'Set-Item'
                    }
                )
                Edges        = @(
                    [pscustomobject]@{
                        From = 'Demo:Widget:Get-Item'
                        To   = $to
                        Type = 'DependsOn'
                    }
                )
                LayoutHints  = @(
                    [pscustomobject]@{
                        Kind    = 'Stack'
                        Targets = @('Demo:Widget:Get-Item', 'Demo:Widget:Set-Item')
                    }
                )
                LinkTemplate = 'vscode://file/{Path}:{Line}'
            }

            if (-not $OmitProviderProperty) {
                $graph['Provider'] = 'Demo'
            }

            return [pscustomobject]$graph
        }
    }

    AfterAll {
        Remove-Module PS.DrawIO.Core -Force -ErrorAction SilentlyContinue
    }

    It 'converts a closed provider graph into an IR with nodes and edges' {
        $graph = New-UnitProviderGraph
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo

        $ir.Provider | Should -Be 'Demo'
        @($ir.Nodes).Count | Should -Be 2
        @($ir.Edges).Count | Should -Be 1
        $ir.Nodes[0].Id | Should -Be 'Demo:Widget:Get-Item'
        $ir.Nodes[1].Name | Should -Be 'Set-Item'
        $ir.Edges[0].From | Should -Be 'Demo:Widget:Get-Item'
        $ir.Edges[0].To | Should -Be 'Demo:Widget:Set-Item'
        $ir.Edges[0].Type | Should -Be 'DependsOn'
        @($ir.LayoutHints).Count | Should -Be 1
        $ir.LinkTemplate | Should -Be 'vscode://file/{Path}:{Line}'
    }

    It 'qualifies bare node Ids as Provider:Type:Name' {
        $graph = [pscustomobject]@{
            Provider = 'Demo'
            Nodes    = @(
                [pscustomobject]@{ Type = 'Widget'; Name = 'Alpha'; Label = 'Alpha' }
                [pscustomobject]@{ Type = 'Widget'; Name = 'Beta'; Label = 'Beta' }
            )
            Edges    = @(
                [pscustomobject]@{ From = 'Demo:Widget:Alpha'; To = 'Demo:Widget:Beta'; Type = 'Link' }
            )
        }

        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
        $ir.Nodes.Id | Should -Contain 'Demo:Widget:Alpha'
        $ir.Nodes.Id | Should -Contain 'Demo:Widget:Beta'
        foreach ($node in $ir.Nodes) {
            $node.Id | Should -Match '^[^:]+:[^:]+:.+$'
            $node.Provider | Should -Be 'Demo'
        }
    }

    It 'rejects an edge whose To names a node absent from the IR' {
        $graph = New-UnitProviderGraph -WithMissingEdgeEndpoint

        { ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo -ErrorAction Stop } | Should -Throw

        try {
            ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo -ErrorAction Stop
        }
        catch {
            $_.Exception.Message | Should -Match 'Demo:Widget:Missing-Target'
            $_.Exception.Message | Should -Match 'absent|rejected|offending'
        }
    }

    It 'returns PSCustomObject IR with a non-default PSTypeName' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo

        $ir -is [pscustomobject] | Should -BeTrue
        $ir.GetType().FullName | Should -Be 'System.Management.Automation.PSCustomObject'
        $ir.PSObject.TypeNames[0] | Should -Be 'PS.DrawIO.IR'
        $ir.PSObject.TypeNames[0] | Should -Not -Be 'System.Management.Automation.PSCustomObject'
        $ir.Nodes[0].PSObject.TypeNames[0] | Should -Be 'PS.DrawIO.IR.Node'
        $ir.Edges[0].PSObject.TypeNames[0] | Should -Be 'PS.DrawIO.IR.Edge'
    }

    It 'round-trips through JSON with structural equality' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $json = $ir | ConvertTo-Json -Depth 20
        $round = $json | ConvertFrom-Json

        ($round | ConvertTo-Json -Depth 20) | Should -Be ($ir | ConvertTo-Json -Depth 20)
        $round.Nodes[0].Id | Should -Be 'Demo:Widget:Get-Item'
        $round.Edges[0].To | Should -Be 'Demo:Widget:Set-Item'
        $round.LayoutHints[0].Kind | Should -Be 'Stack'
        $round.LinkTemplate | Should -Be 'vscode://file/{Path}:{Line}'
    }

    It 'converts a graph with no Provider property when -Provider is given' {
        $graph = New-UnitProviderGraph -OmitProviderProperty
        $null -eq $graph.PSObject.Properties['Provider'] | Should -BeTrue

        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
        $ir.Provider | Should -Be 'Demo'
        $ir.Nodes[0].Id | Should -Be 'Demo:Widget:Get-Item'
        $ir.Nodes[1].Id | Should -Be 'Demo:Widget:Set-Item'
        $ir.Edges[0].From | Should -Be 'Demo:Widget:Get-Item'
    }

    It 'throws when graph.Provider disagrees with -Provider, naming both' {
        $graph = New-UnitProviderGraph
        $graph.Provider | Should -Be 'Demo'

        try {
            ConvertTo-PSDrawIOIR -Graph $graph -Provider Other -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Demo'
            $_.Exception.Message | Should -Match 'Other'
            $_.Exception.Message | Should -Match 'mismatch|Provider'
        }
    }

    It 'throws on invalid provider name, naming the value' {
        $graph = New-UnitProviderGraph -OmitProviderProperty

        try {
            ConvertTo-PSDrawIOIR -Graph $graph -Provider 'bad.name' -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'bad\.name'
            $_.Exception.Message | Should -Match 'Invalid Provider|PascalCase|A-Z'
        }
    }

    It 'requires -Provider' {
        $p = (Get-Command ConvertTo-PSDrawIOIR).Parameters['Provider']
        $attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        $attr.Mandatory | Should -BeTrue
    }

    It 'Resolver parameter is optional (not Mandatory)' {
        $p = (Get-Command ConvertTo-PSDrawIOIR).Parameters['Resolver']
        $p | Should -Not -BeNullOrEmpty
        $attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($attr | Where-Object { $_.Mandatory }).Count | Should -Be 0
    }

    It 'applies Style from injected resolver exactly' {
        $knownStyle = 'rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;'
        $resolver = {
            param($Provider, $Type)
            [pscustomobject]@{ Style = $knownStyle }
        }
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo -Resolver $resolver
        $ir.Nodes[0].Style | Should -Be $knownStyle
        $ir.Nodes[0].ResolvedStyle | Should -Be $knownStyle
        $ir.Nodes[1].Style | Should -Be $knownStyle
    }

    It 'applies LinkTemplate from injected resolver exactly' {
        $knownLink = 'vscode://file/{Path}:{Line}'
        $resolver = {
            param($Provider, $Type)
            [pscustomobject]@{ LinkTemplate = $knownLink }
        }
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo -Resolver $resolver
        $ir.Nodes[0].LinkTemplate | Should -Be $knownLink
        $null -eq $ir.Nodes[0].PSObject.Properties['Style'] -or [string]::IsNullOrWhiteSpace([string]$ir.Nodes[0].Style) | Should -BeTrue
    }

    It 'does not invent Style when declaration has only LinkTemplate' {
        $resolver = {
            param($Provider, $Type)
            [pscustomobject]@{ LinkTemplate = 'vscode://file/{Path}:{Line}' }
        }
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo -Resolver $resolver
        foreach ($n in $ir.Nodes) {
            $hasStyle = ($null -ne $n.PSObject.Properties['Style'] -and -not [string]::IsNullOrWhiteSpace([string]$n.Style)) -or
                ($null -ne $n.PSObject.Properties['ResolvedStyle'] -and -not [string]::IsNullOrWhiteSpace([string]$n.ResolvedStyle)) -or
                ($null -ne $n.PSObject.Properties['ShapeStyle'] -and -not [string]::IsNullOrWhiteSpace([string]$n.ShapeStyle))
            $hasStyle | Should -BeFalse -Because $n.Id
        }
    }

    It 'throws naming type and provider when resolver throws' {
        $resolver = {
            param($Provider, $Type)
            throw "not found: $Type"
        }
        try {
            ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo -Resolver $resolver -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Widget'
            $_.Exception.Message | Should -Match 'Demo'
        }
    }

    It 'throws naming type and provider when resolver returns null' {
        $resolver = {
            param($Provider, $Type)
            $null
        }
        try {
            ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo -Resolver $resolver -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Widget'
            $_.Exception.Message | Should -Match 'Demo'
            $_.Exception.Message | Should -Match 'not registered|null|not found'
        }
    }

    It 'omitting -Resolver converts successfully with no style applied' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $ir.Nodes.Count | Should -Be 2
        foreach ($n in $ir.Nodes) {
            $hasStyle = ($null -ne $n.PSObject.Properties['Style'] -and -not [string]::IsNullOrWhiteSpace([string]$n.Style)) -or
                ($null -ne $n.PSObject.Properties['ResolvedStyle'] -and -not [string]::IsNullOrWhiteSpace([string]$n.ResolvedStyle))
            $hasStyle | Should -BeFalse -Because $n.Id
        }
    }

    It 'throws when Graph is null' {
        { ConvertTo-PSDrawIOIR -Graph $null -Provider Demo -ErrorAction Stop } | Should -Throw
        try {
            ConvertTo-PSDrawIOIR -Graph $null -Provider Demo -ErrorAction Stop
        }
        catch {
            $_.Exception.Message | Should -Match 'Graph'
        }
    }

    It 'converts a graph with no LayoutHints or LinkTemplate' {
        $graph = [pscustomobject]@{
            Nodes = @(
                [pscustomobject]@{ Type = 'Widget'; Name = 'Solo'; Label = 'Solo' }
            )
            Edges = @()
        }
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
        $ir.Nodes.Count | Should -Be 1
        @($ir.LayoutHints).Count | Should -Be 0
        $null -eq $ir.LinkTemplate | Should -BeTrue
    }

    It 'requires -IR on Invoke-PSDrawIOLayout' {
        $p = (Get-Command Invoke-PSDrawIOLayout).Parameters['IR']
        $attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        $attr.Mandatory | Should -BeTrue
    }

    It 'built-in strategy assigns coordinates to every vertex' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $vertices = @($laidOut.Nodes | Where-Object { -not $_.IsEdge })
        $vertices.Count | Should -Be 2
        foreach ($v in $vertices) {
            $null -ne $v.X | Should -BeTrue -Because "$($v.Id) X"
            $null -ne $v.Y | Should -BeTrue -Because "$($v.Id) Y"
            $v.Width | Should -Be 120
            $v.Height | Should -Be 40
        }
        $laidOut.Nodes[0].X | Should -Be 40
        $laidOut.Nodes[0].Y | Should -Be 40
        $laidOut.Nodes[1].X | Should -Be 200
        $laidOut.Nodes[1].Y | Should -Be 40
    }

    It 'same IR laid out twice produces identical coordinates' {
        $graph = New-UnitProviderGraph
        $a = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        $b = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        foreach ($i in 0..($a.Nodes.Count - 1)) {
            $a.Nodes[$i].X | Should -Be $b.Nodes[$i].X
            $a.Nodes[$i].Y | Should -Be $b.Nodes[$i].Y
            $a.Nodes[$i].Width | Should -Be $b.Nodes[$i].Width
            $a.Nodes[$i].Height | Should -Be $b.Nodes[$i].Height
        }
    }

    It 'no two sibling vertices overlap after built-in layout' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $vertices = @($laidOut.Nodes | Where-Object { -not $_.IsEdge })
        for ($i = 0; $i -lt $vertices.Count; $i++) {
            for ($j = $i + 1; $j -lt $vertices.Count; $j++) {
                $a = $vertices[$i]; $b = $vertices[$j]
                $aParent = [string]$a.ParentId; $bParent = [string]$b.ParentId
                if ($aParent -ne $bParent) { continue }
                $aRight = [double]$a.X + [double]$a.Width
                $aBottom = [double]$a.Y + [double]$a.Height
                $bRight = [double]$b.X + [double]$b.Width
                $bBottom = [double]$b.Y + [double]$b.Height
                $overlap = -not ([double]$a.X -ge $bRight -or [double]$b.X -ge $aRight -or [double]$a.Y -ge $bBottom -or [double]$b.Y -ge $aBottom)
                $overlap | Should -BeFalse -Because "$($a.Id) vs $($b.Id)"
            }
        }
    }

    It 'substituted strategy output is what gets returned' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $double = {
            param($IR)
            foreach ($n in @($IR.Nodes)) {
                $n | Add-Member -NotePropertyName X -NotePropertyValue 42 -Force
                $n | Add-Member -NotePropertyName Y -NotePropertyValue 7 -Force
                $n | Add-Member -NotePropertyName Width -NotePropertyValue 10 -Force
                $n | Add-Member -NotePropertyName Height -NotePropertyValue 10 -Force
            }
            $IR
        }
        $laidOut = Invoke-PSDrawIOLayout -IR $ir -Strategy $double
        $laidOut.Nodes[0].X | Should -Be 42
        $laidOut.Nodes[0].Y | Should -Be 7
        $laidOut.Nodes[1].X | Should -Be 42
    }

    It 'strategy returning null is a terminating error naming the problem' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $bad = { param($IR) $null }
        try {
            Invoke-PSDrawIOLayout -IR $ir -Strategy $bad -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'null'
            $_.Exception.Message | Should -Match 'Layout strategy|IR'
        }
    }

    It 'strategy returning a non-IR object is a terminating error naming the problem' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $bad = { param($IR) 'not-an-ir' }
        try {
            Invoke-PSDrawIOLayout -IR $ir -Strategy $bad -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'non-IR|Nodes'
        }
    }

    It 'edges are not given vertex geometry' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        # Promote edges into Nodes list as IsEdge markers (layout must skip them).
        $edgeAsNode = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR.Node'
            Id         = 'Demo:Edge:E0'
            IsEdge     = $true
            From       = 'Demo:Widget:Get-Item'
            To         = 'Demo:Widget:Set-Item'
        }
        $ir.Nodes = @($ir.Nodes) + @($edgeAsNode)
        $laidOut = Invoke-PSDrawIOLayout -IR $ir
        $edge = @($laidOut.Nodes | Where-Object { $_.Id -eq 'Demo:Edge:E0' })[0]
        $edge | Should -Not -BeNullOrEmpty
        $null -eq $edge.PSObject.Properties['X'] -or $null -eq $edge.X | Should -BeTrue
        $null -eq $edge.PSObject.Properties['Y'] -or $null -eq $edge.Y | Should -BeTrue
        $vertices = @($laidOut.Nodes | Where-Object { -not $_.IsEdge })
        foreach ($v in $vertices) {
            $null -ne $v.X | Should -BeTrue
            $null -ne $v.Y | Should -BeTrue
        }
    }

    It 'Export-PSDrawIODiagram writes a non-empty .drawio file' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $path = Join-Path $TestDrive 'unit-export.drawio'
        $returned = Export-PSDrawIODiagram -IR $ir -Path $path
        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Item -LiteralPath $path).Length | Should -BeGreaterThan 0
        $returned | Should -Be $path
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Match '<mxfile\b'
        $text | Should -Match '<mxGraphModel\b'
        $text | Should -Match '<mxCell\s+id="0"\s*/>'
        $text | Should -Match '<mxCell\s+id="1"[^>]*parent="0"'
    }

    It 'Export emits unique mxCell ids and exclusive vertex/edge flags' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $path = Join-Path $TestDrive 'unit-cells.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $doc = [xml](Get-Content -LiteralPath $path -Raw)
        $cells = @($doc.SelectNodes('//mxCell'))
        $ids = @($cells | ForEach-Object { $_.id })
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        @($cells | Where-Object { $_.vertex -eq '1' -and $_.edge -eq '1' }) | Should -BeNullOrEmpty
        @($cells | Where-Object { $_.vertex -eq '1' }).Count | Should -Be 2
        @($cells | Where-Object { $_.edge -eq '1' }).Count | Should -Be 1
    }

    It 'Export XML-escapes HTML in value attributes' {
        $graph = New-UnitProviderGraph
        $graph.Nodes[0].Label = '<b>Get-Item</b>'
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        $path = Join-Path $TestDrive 'unit-html.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Not -Match 'value="[^"]*<b>'
        $text | Should -Match '&lt;b&gt;'
    }

    It 'Export emits perimeter= for non-rectangular Shape metadata' {
        $graph = New-UnitProviderGraph
        $graph.Nodes[0] | Add-Member -NotePropertyName Shape -NotePropertyValue 'ellipse' -Force
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        $path = Join-Path $TestDrive 'unit-perimeter.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'perimeter=ellipsePerimeter'
    }

    It 'Export emits UserObject link when node.Link is set' {
        $graph = New-UnitProviderGraph
        $graph.Nodes[0] | Add-Member -NotePropertyName Link -NotePropertyValue 'vscode://file/demo.ps1:10' -Force
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        $path = Join-Path $TestDrive 'unit-link.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Match '<UserObject'
        $text | Should -Match 'link="vscode://file/demo.ps1:10"'
        # Schema: required id is on UserObject; nested mxCell may also carry id (dual-id).
        $text | Should -Match 'UserObject[^>]*\bid="'
        $text | Should -Match '<mxCell[^>]*\bid="'
    }

    It 'Export rejects malformed IR naming the missing node' {
        $bad = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Nodes      = @(
                [pscustomobject]@{ Id = 'Demo:Widget:Good'; Type = 'Widget'; Name = 'Good' }
            )
            Edges      = @(
                [pscustomobject]@{
                    From = 'Demo:Widget:Good'
                    To   = 'Demo:Widget:Missing-Target'
                    Type = 'DependsOn'
                }
            )
        }
        $path = Join-Path $TestDrive 'unit-malformed.drawio'
        try {
            Export-PSDrawIODiagram -IR $bad -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Demo:Widget:Missing-Target'
            $_.Exception.Message | Should -Match 'absent|rejected|offending|node'
        }
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'Export -WhatIf does not write a file' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $path = Join-Path $TestDrive 'unit-whatif.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path -WhatIf
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'requires -IR and -Path on Export-PSDrawIODiagram' {
        $cmd = Get-Command Export-PSDrawIODiagram
        foreach ($name in @('IR', 'Path')) {
            $p = $cmd.Parameters[$name]
            $attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.Mandatory | Should -BeTrue -Because "$name must be mandatory"
        }
    }

    It 'Export emits vertex geometry from laid-out IR coordinates' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $path = Join-Path $TestDrive 'unit-geo.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $doc = [xml](Get-Content -LiteralPath $path -Raw)
        $v = @($doc.SelectNodes('//mxCell[@vertex="1"]'))
        $v.Count | Should -Be 2
        [double]$v[0].mxGeometry.x | Should -Be 40
        [double]$v[0].mxGeometry.y | Should -Be 40
        [double]$v[0].mxGeometry.width | Should -Be 120
        [double]$v[0].mxGeometry.height | Should -Be 40
        [double]$v[1].mxGeometry.x | Should -Be 200
    }

    It 'Import reads vertex id value and geometry' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" /><mxCell id="n1" value="Hello" style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="40" y="50" width="120" height="40" as="geometry" /></mxCell></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-vertex.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        @($ir.Nodes).Count | Should -Be 1
        $ir.Nodes[0].Id | Should -Be 'n1'
        $ir.Nodes[0].Label | Should -Be 'Hello'
        [double]$ir.Nodes[0].X | Should -Be 40
        [double]$ir.Nodes[0].Y | Should -Be 50
        [double]$ir.Nodes[0].Width | Should -Be 120
        [double]$ir.Nodes[0].Height | Should -Be 40
    }

    It 'Import maps edge source and target to From and To' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" /><mxCell id="a" value="A" style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="10" y="10" width="40" height="20" as="geometry" /></mxCell><mxCell id="b" value="B" style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="100" y="10" width="40" height="20" as="geometry" /></mxCell><mxCell id="e0" value="" style="endArrow=classic;html=1;rounded=0;" edge="1" parent="1" source="a" target="b"><mxGeometry relative="1" as="geometry" /></mxCell></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-edge.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        @($ir.Edges).Count | Should -Be 1
        $ir.Edges[0].From | Should -Be 'a'
        $ir.Edges[0].To | Should -Be 'b'
        $ir.Edges[0].Id | Should -Be 'e0'
    }

    It 'Import preserves customAttr and Export re-emits it on UserObject (ADR 0006 Option A)' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net" agent="accept-test"><diagram id="u" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" /><mxCell id="u1" value="X" style="whiteSpace=wrap;" vertex="1" parent="1" customAttr="keep-me"><mxGeometry x="10" y="10" width="40" height="20" as="geometry" /></mxCell></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-custom.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        $ir.Nodes[0].Metadata.XmlAttributes.customAttr | Should -Be 'keep-me'
        $out = Join-Path $TestDrive 'unit-import-custom-out.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $out | Out-Null
        $text = Get-Content -LiteralPath $out -Raw
        $text | Should -Match 'customAttr="keep-me"'
        $text | Should -Match 'agent="accept-test"'
        # Option A: preserved attrs live on UserObject with required id, not bare mxCell.
        $text | Should -Match '<UserObject[^>]*\bid="u1"'
        $text | Should -Match '<UserObject[^>]*customAttr="keep-me"'
        $text | Should -Not -Match '<mxCell[^>]*customAttr='
    }

    It 'Export leaves bare mxCell when node has neither link nor preserved attrs' {
        # IR.LinkTemplate also forces wrap via resolveLink — strip it and per-node links/attrs.
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        if ($null -ne $ir.PSObject.Properties['LinkTemplate']) {
            $ir.PSObject.Properties.Remove('LinkTemplate')
        }
        foreach ($n in @($ir.Nodes)) {
            if ($null -ne $n.PSObject.Properties['Link']) {
                $n.PSObject.Properties.Remove('Link')
            }
            if ($null -ne $n.PSObject.Properties['Metadata'] -and $null -ne $n.Metadata) {
                if ($null -ne $n.Metadata.PSObject.Properties['XmlAttributes']) {
                    $n.Metadata.PSObject.Properties.Remove('XmlAttributes')
                }
                if ($null -ne $n.Metadata.PSObject.Properties['UserObjectAttributes']) {
                    $n.Metadata.PSObject.Properties.Remove('UserObjectAttributes')
                }
            }
        }
        $path = Join-Path $TestDrive 'unit-bare-no-wrap.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Not -Match '<UserObject' -Because 'no link and no preserved attrs must stay bare mxCell'
        $text | Should -Match '<mxCell[^>]*vertex="1"'
    }

    It 'Import throws naming the file on malformed XML' {
        $path = Join-Path $TestDrive 'unit-import-bad.xml'
        [System.IO.File]::WriteAllText($path, '<not-closed')
        try {
            Import-PSDrawIODiagram -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match ([regex]::Escape($path))
            $_.Exception.Message | Should -Match 'parse|Failed|XML'
        }
    }

    It 'Import throws when mxCell id 0 or 1 is missing' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="n1" value="X" style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="1" y="1" width="10" height="10" as="geometry" /></mxCell></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-missing-root.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        try {
            Import-PSDrawIODiagram -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'id 0|id 1|must contain'
        }
    }

    It 'Import reads UserObject link onto node.Link' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" /><UserObject label="Linked" link="vscode://file/demo.ps1:3"><mxCell id="L1" value="Linked" style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="20" y="20" width="80" height="30" as="geometry" /></mxCell></UserObject></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-link.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        $ir.Nodes[0].Id | Should -Be 'L1'
        $ir.Nodes[0].Label | Should -Be 'Linked'
        $ir.Nodes[0].Link | Should -Be 'vscode://file/demo.ps1:3'
    }

    It 'requires -Path on Import-PSDrawIODiagram' {
        $p = (Get-Command Import-PSDrawIODiagram).Parameters['Path']
        $attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        $attr.Mandatory | Should -BeTrue
    }

    It 'Export accepts bare node Ids from Import' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="hand" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" /><mxCell id="hand-1" value="Hand" style="rounded=0;" vertex="1" parent="1"><mxGeometry x="40" y="40" width="80" height="40" as="geometry" /></mxCell></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-bare-in.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        $ir.Nodes[0].Id | Should -Be 'hand-1'
        $out = Join-Path $TestDrive 'unit-bare-out.drawio'
        { Export-PSDrawIODiagram -IR $ir -Path $out -ErrorAction Stop } | Should -Not -Throw
        (Get-Content -LiteralPath $out -Raw) | Should -Match 'id="hand-1"'
    }

    It 'valid IR emission validates against mxfile.xsd' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $path = Join-Path $TestDrive 'unit-schema-valid.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        Test-PSDrawIODiagramSchema -Content $xml | Should -BeTrue
    }

    It 'missing structural mxCell id 0 fails schema validation naming the violation' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="1" parent="0" /><mxCell id="n1" value="X" style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="1" y="1" width="10" height="10" as="geometry" /></mxCell></root></mxGraphModel></diagram></mxfile>
'@
        try {
            Test-PSDrawIODiagramSchema -Content $xml -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match '\bschema\b'
            $_.Exception.Message | Should -Match 'id="0"|id=.0.|structural|root'
        }
    }

    It 'UserObject with customAttr validates against mxfile.xsd' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" /><UserObject id="u1" label="X" customAttr="keep-me" link="vscode://file/demo.ps1:1"><mxCell id="u1" style="whiteSpace=wrap;" vertex="1" parent="1"><mxGeometry x="10" y="10" width="40" height="20" as="geometry" /></mxCell></UserObject></root></mxGraphModel></diagram></mxfile>
'@
        Test-PSDrawIODiagramSchema -Content $xml | Should -BeTrue
    }

    It 'vendored mxfile.xsd SHA256 matches ADR 0005 pin' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $xsd = Join-Path $root 'src/Schema/mxfile.xsd'
        Test-Path -LiteralPath $xsd | Should -BeTrue -Because 'src/Schema/mxfile.xsd must be vendored'
        $hash = (Get-FileHash -LiteralPath $xsd -Algorithm SHA256).Hash.ToLowerInvariant()
        # Pin: docs/DECISIONS/0005-vendoring-the-mxfile-schema.md
        $hash | Should -Be '905db85d4e8ebec0e91518cdd62982e0afb3f09ebdcaf9e6b1952957a606639a'
    }

    It 'schema resolves from packaged module ModuleBase' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $build = Join-Path $root 'build/build.ps1'
        & $build -Task Package | Out-Null
        $distManifest = Join-Path $root 'dist/PS.DrawIO.Core/PS.DrawIO.Core.psd1'
        Test-Path -LiteralPath $distManifest | Should -BeTrue -Because 'Package must produce dist/PS.DrawIO.Core'
        $distXsd = Join-Path $root 'dist/PS.DrawIO.Core/Schema/mxfile.xsd'
        Test-Path -LiteralPath $distXsd | Should -BeTrue -Because 'Package must include Schema/mxfile.xsd'
        Remove-Module PS.DrawIO.Core -Force -ErrorAction SilentlyContinue
        Import-Module $distManifest -Force
        $mod = Get-Module PS.DrawIO.Core
        $resolved = Join-Path $mod.ModuleBase 'Schema/mxfile.xsd'
        Test-Path -LiteralPath $resolved | Should -BeTrue
        $minimal = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="p" name="Page-1"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/></root></mxGraphModel></diagram></mxfile>
'@
        Test-PSDrawIODiagramSchema -Content $minimal | Should -BeTrue
        Remove-Module PS.DrawIO.Core -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $root 'src/PS.DrawIO.Core.psd1') -Force
    }

    It 'schema rejects whitespace-only Content with a schema validation message' {
        # Empty string is rejected by the binder before the body; whitespace reaches IsNullOrWhiteSpace.
        try {
            Test-PSDrawIODiagramSchema -Content " `t`n" -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'Diagram schema validation failed: Content is empty.'
        }
    }

    It 'schema rejects malformed XML naming well-formed failure' {
        try {
            Test-PSDrawIODiagramSchema -Content '<mxfile><diagram>' -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Diagram schema validation failed'
            $_.Exception.Message | Should -Match 'not well-formed|well-formed'
        }
    }

    It 'schema rejects non-mxfile root via XSD validation event path' {
        # Well-formed XML that is not a valid mxfile document — must hit ValidationEventHandler.
        $xml = '<?xml version="1.0" encoding="UTF-8"?><not-mxfile><child/></not-mxfile>'
        try {
            Test-PSDrawIODiagramSchema -Content $xml -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Diagram schema validation failed'
            $_.Exception.Message | Should -Not -Match 'Content is empty'
            $_.Exception.Message | Should -Not -Match 'not well-formed'
        }
    }

    It 'schema rejects missing structural id=1 parent=0 after XSD passes' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="p" name="Page-1"><mxGraphModel><root><mxCell id="0"/></root></mxGraphModel></diagram></mxfile>
'@
        try {
            Test-PSDrawIODiagramSchema -Content $xml -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Diagram schema validation failed'
            $_.Exception.Message | Should -Match 'id="1"|parent="0"|default layer'
        }
    }

    It 'schema accepts structural roots carried only on UserObject wrappers' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="p" name="Page-1"><mxGraphModel><root><UserObject id="0" label="root"><mxCell/></UserObject><UserObject id="1" label="layer"><mxCell parent="0"/></UserObject></root></mxGraphModel></diagram></mxfile>
'@
        Test-PSDrawIODiagramSchema -Content $xml | Should -BeTrue
    }

    It 'Export throws when destination directory does not exist' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $missingDir = Join-Path $TestDrive 'no-such-export-dir'
        $path = Join-Path $missingDir 'out.drawio'
        Test-Path -LiteralPath $missingDir | Should -BeFalse
        try {
            Export-PSDrawIODiagram -IR $ir -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Export directory does not exist'
            $_.Exception.Message | Should -Match ([regex]::Escape($missingDir))
        }
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'Import throws when the draw.io file path does not exist' {
        $missing = Join-Path $TestDrive 'definitely-missing-import.drawio'
        Test-Path -LiteralPath $missing | Should -BeFalse
        try {
            Import-PSDrawIODiagram -Path $missing -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'Draw.io file not found'
            $_.Exception.Message | Should -Match ([regex]::Escape($missing))
        }
    }

    It 'layout throws when IR has no Nodes property' {
        $bad = [pscustomobject]@{ Provider = 'Demo' }
        try {
            Invoke-PSDrawIOLayout -IR $bad -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'IR is invalid: Nodes property is required.'
        }
    }

    It 'layout throws when strategy returns a PSCustomObject without Nodes' {
        $ir = ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo
        $bad = { param($IR) [pscustomobject]@{ NotNodes = 1 } }
        try {
            Invoke-PSDrawIOLayout -IR $ir -Strategy $bad -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'Layout strategy returned a non-IR object: Nodes property is missing.'
        }
    }

    It 'Export rejects IR node Id that collides with reserved root cell 0' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{ Id = '0'; Type = 'Widget'; Name = 'Rootish'; Label = 'X'; X = 1; Y = 1; Width = 10; Height = 10 }
            )
            Edges      = @()
        }
        $path = Join-Path $TestDrive 'unit-reserved-id.drawio'
        try {
            Export-PSDrawIODiagram -IR $ir -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match "collides with reserved root cell id"
            $_.Exception.Message | Should -Match "'0'"
        }
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'Export rejects IR with duplicate node Ids naming the id' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{ Id = 'Demo:Widget:Dup'; Type = 'Widget'; Name = 'Dup'; Label = 'A'; X = 1; Y = 1; Width = 10; Height = 10 }
                [pscustomobject]@{ Id = 'Demo:Widget:Dup'; Type = 'Widget'; Name = 'Dup'; Label = 'B'; X = 2; Y = 2; Width = 10; Height = 10 }
            )
            Edges      = @()
        }
        $path = Join-Path $TestDrive 'unit-dup-id.drawio'
        try {
            Export-PSDrawIODiagram -IR $ir -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'duplicate node Id'
            $_.Exception.Message | Should -Match 'Demo:Widget:Dup'
        }
    }

    It 'Export rejects IR node with blank Id' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{ Id = '   '; Type = 'Widget'; Name = 'Blank'; Label = 'Blank'; X = 1; Y = 1; Width = 10; Height = 10 }
            )
            Edges      = @()
        }
        $path = Join-Path $TestDrive 'unit-blank-id.drawio'
        try {
            Export-PSDrawIODiagram -IR $ir -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'IR is invalid: node Id is required (offending node).'
        }
    }

    It 'Export rejects IR missing Nodes property' {
        $ir = [pscustomobject]@{ Provider = 'Demo' }
        $path = Join-Path $TestDrive 'unit-no-nodes.drawio'
        try {
            Export-PSDrawIODiagram -IR $ir -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'IR is invalid: Nodes property is required.'
        }
    }

    It 'Export emits group style and sizes parent from children via built-in layout' {
        $graph = [pscustomobject]@{
            Provider = 'Demo'
            Nodes    = @(
                [pscustomobject]@{
                    Id      = 'Demo:Group:Box'
                    Type    = 'Group'
                    Name    = 'Box'
                    Label   = 'Box'
                    IsGroup = $true
                }
                [pscustomobject]@{
                    Id       = 'Demo:Widget:ChildA'
                    Type     = 'Widget'
                    Name     = 'ChildA'
                    Label    = 'ChildA'
                    ParentId = 'Demo:Group:Box'
                }
                [pscustomobject]@{
                    Id       = 'Demo:Widget:ChildB'
                    Type     = 'Widget'
                    Name     = 'ChildB'
                    Label    = 'ChildB'
                    ParentId = 'Demo:Group:Box'
                }
            )
            Edges = @()
        }
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        $box = @($ir.Nodes | Where-Object { $_.Id -eq 'Demo:Group:Box' })[0]
        $child = @($ir.Nodes | Where-Object { $_.Id -eq 'Demo:Widget:ChildA' })[0]
        $null -ne $box.X | Should -BeTrue
        $null -ne $child.X | Should -BeTrue
        [double]$box.Width | Should -BeGreaterThan 120
        [double]$box.Height | Should -BeGreaterThan 40
        $child.ParentId | Should -Be 'Demo:Group:Box'

        $path = Join-Path $TestDrive 'unit-group.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'id="Demo:Group:Box"'
        $xml | Should -Match 'group'
        $xml | Should -Match 'parent="Demo:Group:Box"'
    }

    It 'Export resolves LinkTemplate from node Metadata Path and Line' {
        $graph = [pscustomobject]@{
            Provider     = 'Demo'
            LinkTemplate = 'vscode://file/{Path}:{Line}'
            Nodes        = @(
                [pscustomobject]@{
                    Id       = 'Demo:Widget:Linked'
                    Type     = 'Widget'
                    Name     = 'Linked'
                    Label    = 'Linked'
                    Metadata = [pscustomobject]@{ Path = 'src/Demo.ps1'; Line = '42' }
                }
            )
            Edges = @()
        }
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo)
        $path = Join-Path $TestDrive 'unit-link-template.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'UserObject'
        $xml | Should -Match 'link="vscode://file/src/Demo.ps1:42"'
    }

    It 'Export uses nested Geometry coordinates when flat X/Y are absent' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{
                    Id       = 'Demo:Widget:Geo'
                    Type     = 'Widget'
                    Name     = 'Geo'
                    Label    = 'Geo'
                    Geometry = [pscustomobject]@{ X = 11; Y = 22; Width = 33; Height = 44 }
                }
            )
            Edges = @()
        }
        $path = Join-Path $TestDrive 'unit-geometry-bag.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'x="11"'
        $xml | Should -Match 'y="22"'
        $xml | Should -Match 'width="33"'
        $xml | Should -Match 'height="44"'
    }

    It 'Export wraps edge with Link in UserObject and keeps edge endpoints' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $ir.Edges[0] | Add-Member -NotePropertyName Link -NotePropertyValue 'https://example.test/edge' -Force
        $ir.Edges[0] | Add-Member -NotePropertyName Id -NotePropertyValue 'edge-linked-1' -Force
        $ir.Edges[0] | Add-Member -NotePropertyName Style -NotePropertyValue 'endArrow=block;html=1' -Force
        $ir.Edges[0] | Add-Member -NotePropertyName Metadata -NotePropertyValue ([pscustomobject]@{
                Value         = 'calls'
                Parent        = '1'
                XmlAttributes = [pscustomobject]@{ edgeNote = 'keep' }
            }) -Force
        $path = Join-Path $TestDrive 'unit-edge-uo.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'UserObject[^>]*id="edge-linked-1"'
        $xml | Should -Match 'link="https://example.test/edge"'
        $xml | Should -Match 'edgeNote="keep"'
        $xml | Should -Match 'source="Demo:Widget:Get-Item"'
        $xml | Should -Match 'target="Demo:Widget:Set-Item"'
        $xml | Should -Match 'endArrow=block'
    }

    It 'Export falls back to node Name when Label is absent' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{
                    Id     = 'Demo:Widget:NameOnly'
                    Type   = 'Widget'
                    Name   = 'NameOnly'
                    X      = 5; Y = 5; Width = 20; Height = 10
                }
            )
            Edges = @()
        }
        $path = Join-Path $TestDrive 'unit-name-label.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'value="NameOnly"'
    }

    It 'Export applies IR Metadata model attributes onto mxGraphModel' {
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        $ir | Add-Member -NotePropertyName Metadata -NotePropertyValue ([pscustomobject]@{
                ModelAttributes = [pscustomobject]@{ grid = '1'; gridSize = '10' }
            }) -Force
        $path = Join-Path $TestDrive 'unit-model-attrs.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'grid="1"'
        $xml | Should -Match 'gridSize="10"'
    }

    It 'Import throws when root element is not mxfile' {
        $path = Join-Path $TestDrive 'unit-not-mxfile.drawio'
        [System.IO.File]::WriteAllText($path, '<?xml version="1.0"?><html><body/></html>')
        try {
            Import-PSDrawIODiagram -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'missing a root mxfile element'
            $_.Exception.Message | Should -Match ([regex]::Escape($path))
        }
    }

    It 'Import throws when diagram element is missing' {
        $path = Join-Path $TestDrive 'unit-no-diagram.drawio'
        [System.IO.File]::WriteAllText($path, '<?xml version="1.0"?><mxfile host="x"></mxfile>')
        try {
            Import-PSDrawIODiagram -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'missing a diagram element'
            $_.Exception.Message | Should -Match ([regex]::Escape($path))
        }
    }

    It 'Import throws when mxGraphModel is missing' {
        $path = Join-Path $TestDrive 'unit-no-model.drawio'
        [System.IO.File]::WriteAllText($path, '<?xml version="1.0"?><mxfile host="x"><diagram id="p" name="P"></diagram></mxfile>')
        try {
            Import-PSDrawIODiagram -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'missing mxGraphModel'
            $_.Exception.Message | Should -Match ([regex]::Escape($path))
        }
    }

    It 'Import throws when root element under model is missing' {
        $path = Join-Path $TestDrive 'unit-no-root.drawio'
        [System.IO.File]::WriteAllText($path, '<?xml version="1.0"?><mxfile host="x"><diagram id="p" name="P"><mxGraphModel></mxGraphModel></diagram></mxfile>')
        try {
            Import-PSDrawIODiagram -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match 'missing root'
            $_.Exception.Message | Should -Match ([regex]::Escape($path))
        }
    }

    It 'Import maps edge UserObject label link and custom attrs' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="a" value="A" style="whiteSpace=wrap;" vertex="1" parent="1"><mxGeometry x="10" y="10" width="40" height="20" as="geometry"/></mxCell><mxCell id="b" value="B" style="whiteSpace=wrap;" vertex="1" parent="1"><mxGeometry x="100" y="10" width="40" height="20" as="geometry"/></mxCell><UserObject id="e1" label="uses" link="https://example.test/e" edgeNote="n1"><mxCell id="e1" style="endArrow=classic;" edge="1" parent="1" source="a" target="b"><mxGeometry relative="1" as="geometry"/></mxCell></UserObject></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-edge-uo.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        $edge = @($ir.Edges | Where-Object { $_.From -eq 'a' -and $_.To -eq 'b' })[0]
        $edge | Should -Not -BeNullOrEmpty
        $edge.Link | Should -Be 'https://example.test/e'
        $edge.Metadata.Value | Should -Be 'uses'
        $edge.Metadata.XmlAttributes.edgeNote | Should -Be 'n1'
    }

    It 'ConvertTo-PSDrawIOIR copies node Variant ParentId IsGroup and Metadata' {
        $graph = [pscustomobject]@{
            Provider = 'Demo'
            Nodes    = @(
                [pscustomobject]@{
                    Type     = 'Widget'
                    Name     = 'Rich'
                    Label    = 'Rich'
                    Variant  = 'Public'
                    ParentId = 'Demo:Group:Box'
                    IsGroup  = $false
                    Metadata = [pscustomobject]@{ Source = 'fixture'; Tier = 2 }
                }
                [pscustomobject]@{
                    Type    = 'Group'
                    Name    = 'Box'
                    Label   = 'Box'
                    IsGroup = $true
                }
            )
            Edges = @()
        }
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
        $rich = @($ir.Nodes | Where-Object { $_.Name -eq 'Rich' })[0]
        $rich.Variant | Should -Be 'Public'
        $rich.ParentId | Should -Be 'Demo:Group:Box'
        $rich.IsGroup | Should -BeFalse
        $rich.Metadata.Source | Should -Be 'fixture'
        $rich.Metadata.Tier | Should -Be 2
        $box = @($ir.Nodes | Where-Object { $_.Name -eq 'Box' })[0]
        $box.IsGroup | Should -BeTrue
    }

    It 'ConvertTo-PSDrawIOIR maps Visibility onto Variant when Variant is absent' {
        $graph = [pscustomobject]@{
            Provider = 'Demo'
            Nodes    = @(
                [pscustomobject]@{
                    Type       = 'Widget'
                    Name       = 'Vis'
                    Label      = 'Vis'
                    Visibility = 'Private'
                }
            )
            Edges = @()
        }
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
        $ir.Nodes[0].Variant | Should -Be 'Private'
    }

    It 'ConvertTo-PSDrawIOIR preserves edge Id CallCount Extents aggregates' {
        $graph = [pscustomobject]@{
            Provider = 'Demo'
            Nodes    = @(
                [pscustomobject]@{ Type = 'Widget'; Name = 'A'; Label = 'A' }
                [pscustomobject]@{ Type = 'Widget'; Name = 'B'; Label = 'B' }
            )
            Edges    = @(
                [pscustomobject]@{
                    Id        = 'e-custom'
                    From      = 'Demo:Widget:A'
                    To        = 'Demo:Widget:B'
                    Type      = 'Calls'
                    CallCount = 3
                    Extents   = @(@{ Start = 1; End = 2 })
                }
            )
        }
        $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
        $ir.Edges[0].Id | Should -Be 'e-custom'
        $ir.Edges[0].Aggregates.CallCount | Should -Be 3
        @($ir.Edges[0].Aggregates.Extents).Count | Should -Be 1
    }

    It 'requires -Content on Test-PSDrawIODiagramSchema' {
        $p = (Get-Command Test-PSDrawIODiagramSchema).Parameters['Content']
        $attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($attr | Where-Object Mandatory).Count | Should -BeGreaterThan 0
        ($attr | Select-Object -First 1).Mandatory | Should -BeTrue
    }

    It 'Export throws Path is required when Path is whitespace' {
        # Null IR / empty Path are binder-rejected before body; whitespace Path hits body guard.
        $ir = Invoke-PSDrawIOLayout -IR (ConvertTo-PSDrawIOIR -Graph (New-UnitProviderGraph) -Provider Demo)
        try {
            Export-PSDrawIODiagram -IR $ir -Path '   ' -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'Path is required.'
        }
    }

    It 'Import throws Path is required when Path is whitespace' {
        try {
            Import-PSDrawIODiagram -Path '   ' -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Be 'Path is required.'
        }
    }

    It 'schema load failure names the schema path when xsd content is temporarily invalid' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $xsd = Join-Path $root 'src/Schema/mxfile.xsd'
        Test-Path -LiteralPath $xsd | Should -BeTrue
        $original = [System.IO.File]::ReadAllText($xsd)
        try {
            # File must exist so Resolve-PSDrawIOSchemaPath succeeds; invalid XSD hits Add/Compile catch.
            [System.IO.File]::WriteAllText($xsd, '<?xml version="1.0"?><not-a-schema/>')
            try {
                Test-PSDrawIODiagramSchema -Content '<?xml version="1.0"?><mxfile host="x"><diagram id="p" name="P"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/></root></mxGraphModel></diagram></mxfile>' -ErrorAction Stop
                throw 'expected terminating error was not thrown'
            }
            catch {
                $_.Exception.Message | Should -Match 'Diagram schema validation failed'
                $_.Exception.Message | Should -Match 'could not load schema'
                $_.Exception.Message | Should -Match 'mxfile\.xsd'
            }
        }
        finally {
            [System.IO.File]::WriteAllText($xsd, $original)
        }
        $restored = (Get-FileHash -LiteralPath $xsd -Algorithm SHA256).Hash.ToLowerInvariant()
        $restored | Should -Be '905db85d4e8ebec0e91518cdd62982e0afb3f09ebdcaf9e6b1952957a606639a'
    }

    It 'Export rejects edge From naming a node absent from IR' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{ Id = 'Demo:Widget:Only'; Type = 'Widget'; Name = 'Only'; Label = 'Only'; X = 1; Y = 1; Width = 10; Height = 10 }
            )
            Edges      = @(
                [pscustomobject]@{ From = 'Demo:Widget:Missing'; To = 'Demo:Widget:Only'; Type = 'DependsOn' }
            )
        }
        $path = Join-Path $TestDrive 'unit-edge-from-missing.drawio'
        try {
            Export-PSDrawIODiagram -IR $ir -Path $path -ErrorAction Stop
            throw 'expected terminating error was not thrown'
        }
        catch {
            $_.Exception.Message | Should -Match "From='Demo:Widget:Missing'"
            $_.Exception.Message | Should -Match 'absent from the IR'
        }
    }

    It 'Export applies Shape and IsGroup into style string' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{
                    Id      = 'Demo:Widget:Shaped'
                    Type    = 'Widget'
                    Name    = 'Shaped'
                    Label   = 'Shaped'
                    Shape   = 'ellipse'
                    IsGroup = $true
                    X       = 10; Y = 10; Width = 50; Height = 50
                }
            )
            Edges = @()
        }
        $path = Join-Path $TestDrive 'unit-shape-group.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'shape=ellipse'
        $xml | Should -Match 'perimeter=ellipsePerimeter'
        $xml | Should -Match 'group'
    }

    It 'Export regenerates edge Id when it collides with a node Id' {
        $ir = [pscustomobject]@{
            PSTypeName = 'PS.DrawIO.IR'
            Provider   = 'Demo'
            Nodes      = @(
                [pscustomobject]@{ Id = 'Demo:Widget:A'; Type = 'Widget'; Name = 'A'; Label = 'A'; X = 1; Y = 1; Width = 10; Height = 10 }
                [pscustomobject]@{ Id = 'Demo:Widget:B'; Type = 'Widget'; Name = 'B'; Label = 'B'; X = 20; Y = 1; Width = 10; Height = 10 }
            )
            Edges      = @(
                [pscustomobject]@{
                    Id   = 'Demo:Widget:A'
                    From = 'Demo:Widget:A'
                    To   = 'Demo:Widget:B'
                    Type = 'DependsOn'
                }
            )
        }
        $path = Join-Path $TestDrive 'unit-edge-id-collision.drawio'
        Export-PSDrawIODiagram -IR $ir -Path $path | Out-Null
        $xml = Get-Content -LiteralPath $path -Raw
        $xml | Should -Match 'edge="1"'
        $xml | Should -Match 'source="Demo:Widget:A"'
        $xml | Should -Match 'target="Demo:Widget:B"'
        # Colliding edge id must be regenerated away from the node id.
        ([regex]::Matches($xml, 'id="Demo:Widget:A"')).Count | Should -Be 1
        $xml | Should -Match 'id="edge-0-'
    }

    It 'Import promotes UserObject id when nested mxCell omits id' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/><UserObject id="uo-only" label="Wrapped" customKeep="yes"><mxCell style="whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="5" y="6" width="7" height="8" as="geometry"/></mxCell></UserObject></root></mxGraphModel></diagram></mxfile>
'@
        $path = Join-Path $TestDrive 'unit-import-uo-id.drawio'
        [System.IO.File]::WriteAllText($path, $xml)
        $ir = Import-PSDrawIODiagram -Path $path
        $ir.Nodes.Count | Should -Be 1
        $ir.Nodes[0].Id | Should -Be 'uo-only'
        $ir.Nodes[0].Label | Should -Be 'Wrapped'
        $ir.Nodes[0].X | Should -Be 5
        $ir.Nodes[0].Metadata.XmlAttributes.customKeep | Should -Be 'yes'
    }
}

