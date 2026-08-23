function ConvertTo-PSDrawIOIREdge {
    <#
    .SYNOPSIS
    Maps one provider graph edge into a boundary-safe IR edge PSCustomObject.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Edge,

        [Parameter(Mandatory)]
        [int] $Index
    )

    $from = [string] $Edge.From
    $to = [string] $Edge.To
    $type = [string] $Edge.Type
    $id = if ($Edge.Id) {
        [string] $Edge.Id
    }
    else {
        'edge:{0}:{1}:{2}:{3}' -f $Index, $from, $to, $type
    }

    $aggregates = $null
    if ($null -ne $Edge.PSObject.Properties['Aggregates']) {
        $aggregates = $Edge.Aggregates
    }
    elseif ($null -ne $Edge.PSObject.Properties['CallCount'] -or $null -ne $Edge.PSObject.Properties['Extents']) {
        $aggregates = [pscustomobject]@{
            CallCount = $(if ($null -ne $Edge.PSObject.Properties['CallCount']) { $Edge.CallCount } else { $null })
            Extents   = $(if ($null -ne $Edge.PSObject.Properties['Extents']) { $Edge.Extents } else { $null })
        }
    }

    return [pscustomobject]@{
        PSTypeName = 'PS.DrawIO.IR.Edge'
        Id         = $id
        From       = $from
        To         = $to
        Type       = $type
        Aggregates = $aggregates
    }
}
