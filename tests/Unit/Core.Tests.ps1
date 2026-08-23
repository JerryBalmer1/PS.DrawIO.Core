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
}

