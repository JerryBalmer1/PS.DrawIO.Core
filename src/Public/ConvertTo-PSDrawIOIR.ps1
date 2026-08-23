function ConvertTo-PSDrawIOIR {
    <#
    .SYNOPSIS
    Converts a provider graph into Core's intermediate representation.

    .DESCRIPTION
    Normalizes provider nodes and edges into boundary-safe PSCustomObject IR.
    Node Ids are Provider:Type:Name (ADR 0001). Caller supplies -Provider (ADR 0003).
    Edges whose From or To name a node absent from the IR are rejected.

    .PARAMETER Graph
    Provider graph with Nodes and Edges. Optional Provider must match -Provider if set.

    .PARAMETER Provider
    Owning provider name. Mandatory. Rule: ^[A-Z][A-Za-z0-9]+$ (no Registry dependency).

    .EXAMPLE
    $graph = [pscustomobject]@{
        Nodes = @(
            [pscustomobject]@{ Id = 'PowerShell:Function:Get-Foo'; Type = 'Function'; Name = 'Get-Foo'; Label = 'Get-Foo' }
            [pscustomobject]@{ Id = 'PowerShell:Function:Set-Foo'; Type = 'Function'; Name = 'Set-Foo'; Label = 'Set-Foo' }
        )
        Edges = @(
            [pscustomobject]@{ From = 'PowerShell:Function:Get-Foo'; To = 'PowerShell:Function:Set-Foo'; Type = 'Internal' }
        )
    }
    ConvertTo-PSDrawIOIR -Graph $graph -Provider PowerShell
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Graph,

        [Parameter(Mandatory)]
        [string] $Provider
    )

    process {
        if ($null -eq $Graph) { throw 'Graph is required.' }

        Test-PSDrawIOProviderName -Name $Provider

        if ($null -ne $Graph.PSObject.Properties['Provider']) {
            $graphProvider = [string] $Graph.Provider
            if (-not [string]::IsNullOrWhiteSpace($graphProvider) -and $graphProvider -cne $Provider) {
                throw ("Provider mismatch: -Provider is '{0}' but graph.Provider is '{1}'." -f $Provider, $graphProvider)
            }
        }

        $nodeIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $irNodes = [System.Collections.Generic.List[object]]::new()

        foreach ($node in @($Graph.Nodes)) {
            $id = Resolve-PSDrawIOQualifiedId -Node $node -Provider $Provider
            if (-not $nodeIds.Add($id)) { throw "Duplicate IR node Id '$id'." }
            $irNodes.Add((ConvertTo-PSDrawIOIRNode -Node $node -Provider $Provider -Id $id))
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
            Provider     = $Provider
            Nodes        = @($irNodes.ToArray())
            Edges        = @($irEdges.ToArray())
            LayoutHints  = $layoutHints
            LinkTemplate = $linkTemplate
        }
    }
}

