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
}

