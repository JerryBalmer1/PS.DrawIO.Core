function ConvertTo-PSDrawIOIR {
    <#
    .SYNOPSIS
    Converts a provider graph into Core's intermediate representation.

    .DESCRIPTION
    Normalizes provider nodes and edges into boundary-safe PSCustomObject IR.
    Node Ids are provider-qualified as Provider:Type:Name. Edges whose From or
    To name a node absent from the IR are rejected with a terminating error.

    .PARAMETER Graph
    A provider graph object with Provider, Nodes, and Edges collections.

    .EXAMPLE
    $graph = [pscustomobject]@{
        Provider = 'PowerShell'
        Nodes    = @(
            [pscustomobject]@{ Id = 'PowerShell:Function:Get-Foo'; Type = 'Function'; Name = 'Get-Foo'; Label = 'Get-Foo' }
            [pscustomobject]@{ Id = 'PowerShell:Function:Set-Foo'; Type = 'Function'; Name = 'Set-Foo'; Label = 'Set-Foo' }
        )
        Edges    = @(
            [pscustomobject]@{ From = 'PowerShell:Function:Get-Foo'; To = 'PowerShell:Function:Set-Foo'; Type = 'Internal' }
        )
    }
    ConvertTo-PSDrawIOIR -Graph $graph
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Graph
    )

    process {
        if ($null -eq $Graph) {
            throw 'Graph is required.'
        }

        $provider = [string] $Graph.Provider
        if ([string]::IsNullOrWhiteSpace($provider)) {
            throw 'Provider graph must include a non-empty Provider.'
        }

        $nodeIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $irNodes = [System.Collections.Generic.List[object]]::new()

        foreach ($node in @($Graph.Nodes)) {
            $id = Resolve-PSDrawIOQualifiedId -Node $node -Provider $provider
            if (-not $nodeIds.Add($id)) {
                throw "Duplicate IR node Id '$id'."
            }
            $irNodes.Add((ConvertTo-PSDrawIOIRNode -Node $node -Provider $provider -Id $id))
        }

        $irEdges = [System.Collections.Generic.List[object]]::new()
        $index = 0
        foreach ($edge in @($Graph.Edges)) {
            $irEdge = ConvertTo-PSDrawIOIREdge -Edge $edge -Index $index
            if (-not $nodeIds.Contains($irEdge.From)) {
                throw ("IR edge rejected: From='{0}' names a node absent from the IR (offending edge Id='{1}', Type='{2}', To='{3}')." -f `
                        $irEdge.From, $irEdge.Id, $irEdge.Type, $irEdge.To)
            }
            if (-not $nodeIds.Contains($irEdge.To)) {
                throw ("IR edge rejected: To='{0}' names a node absent from the IR (offending edge Id='{1}', Type='{2}', From='{3}')." -f `
                        $irEdge.To, $irEdge.Id, $irEdge.Type, $irEdge.From)
            }
            $irEdges.Add($irEdge)
            $index++
        }

        $layoutHints = @()
        if ($null -ne $Graph.PSObject.Properties['LayoutHints'] -and $null -ne $Graph.LayoutHints) {
            $layoutHints = @($Graph.LayoutHints)
        }

        $linkTemplate = $null
        if ($null -ne $Graph.PSObject.Properties['LinkTemplate']) {
            $linkTemplate = $Graph.LinkTemplate
        }

        return [pscustomobject]@{
            PSTypeName   = 'PS.DrawIO.IR'
            Provider     = $provider
            Nodes        = @($irNodes.ToArray())
            Edges        = @($irEdges.ToArray())
            LayoutHints  = $layoutHints
            LinkTemplate = $linkTemplate
        }
    }
}
