function ConvertTo-PSDrawIOIR {
    <#
    .SYNOPSIS
    Converts a provider graph into Core's intermediate representation.

    .DESCRIPTION
    Normalizes provider nodes and edges into boundary-safe PSCustomObject IR.
    Node Ids are Provider:Type:Name (ADR 0001). Caller supplies -Provider (ADR 0003).
    Edges whose From or To name a node absent from the IR are rejected.

    Optional -Resolver is an injected seam (ADR 0004). Core never loads
    PS.DrawIO.Registry. Invoked as & $Resolver $Provider $Type; returns a
    declaration (Style, LinkTemplate, ...) or throw/null. Null or throw is a
    terminating error naming type and provider. Omitting -Resolver skips
    resolution and invents no style.

    .PARAMETER Graph
    Provider graph with Nodes and Edges. Optional Provider must match -Provider if set.

    .PARAMETER Provider
    Owning provider name. Mandatory. Rule: ^[A-Z][A-Za-z0-9]+$ (no Registry dependency).

    .PARAMETER Resolver
    Optional scriptblock: param($Provider, $Type) -> declaration or throw/null.

    .EXAMPLE
    $graph = [pscustomobject]@{
        Nodes = @(
            [pscustomobject]@{ Type = 'Widget'; Name = 'Get-Foo'; Label = 'Get-Foo' }
            [pscustomobject]@{ Type = 'Widget'; Name = 'Set-Foo'; Label = 'Set-Foo' }
        )
        Edges = @(
            [pscustomobject]@{ From = 'Demo:Widget:Get-Foo'; To = 'Demo:Widget:Set-Foo'; Type = 'Link' }
        )
    }
    $resolver = {
        param($Provider, $Type)
        [pscustomobject]@{ Style = 'rounded=1;whiteSpace=wrap;html=1;' }
    }
    $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo -Resolver $resolver
    $ir.Nodes[0].Style
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Graph,

        [Parameter(Mandatory)]
        [string] $Provider,

        [Parameter()]
        [scriptblock] $Resolver
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

        $members = ConvertTo-PSDrawIOIRContent -Graph $Graph -Provider $Provider -Resolver $Resolver

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
            Nodes        = $members.Nodes
            Edges        = $members.Edges
            LayoutHints  = $layoutHints
            LinkTemplate = $linkTemplate
        }
    }
}

