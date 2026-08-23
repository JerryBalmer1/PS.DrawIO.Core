function ConvertTo-PSDrawIOIRContent {
    <#
    .SYNOPSIS
    Builds IR nodes and edges from a provider graph, optionally resolving types.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Graph,

        [Parameter(Mandatory)]
        [string] $Provider,

        [Parameter()]
        [scriptblock] $Resolver
    )

    $declCache = @{}
    $getDeclaration = {
        param([string] $TypeName)
        if (-not $Resolver) { return $null }
        if ([string]::IsNullOrWhiteSpace($TypeName)) {
            throw ("Semantic type is missing for provider '{0}'." -f $Provider)
        }
        if ($declCache.ContainsKey($TypeName)) { return $declCache[$TypeName] }
        $d = Invoke-PSDrawIOShapeResolver -Resolver $Resolver -Provider $Provider -Type $TypeName
        $declCache[$TypeName] = $d
        return $d
    }

    $nodeIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $irNodes = [System.Collections.Generic.List[object]]::new()

    foreach ($node in @($Graph.Nodes)) {
        $id = Resolve-PSDrawIOQualifiedId -Node $node -Provider $Provider
        if (-not $nodeIds.Add($id)) { throw "Duplicate IR node Id '$id'." }
        $irNode = ConvertTo-PSDrawIOIRNode -Node $node -Provider $Provider -Id $id
        if ($Resolver) {
            $null = Add-PSDrawIOResolvedDeclaration -Target $irNode -Declaration (& $getDeclaration ([string]$irNode.Type))
        }
        $irNodes.Add($irNode)
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
        if ($Resolver) {
            $null = Add-PSDrawIOResolvedDeclaration -Target $irEdge -Declaration (& $getDeclaration ([string]$irEdge.Type))
        }
        $irEdges.Add($irEdge)
        $index++
    }

    return @{
        Nodes = @($irNodes.ToArray())
        Edges = @($irEdges.ToArray())
    }
}
