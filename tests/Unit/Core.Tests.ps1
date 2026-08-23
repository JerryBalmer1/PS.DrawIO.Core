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
}

