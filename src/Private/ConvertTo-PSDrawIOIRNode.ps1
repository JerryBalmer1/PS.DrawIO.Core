function ConvertTo-PSDrawIOIRNode {
    <#
    .SYNOPSIS
    Maps one provider graph node into a boundary-safe IR node PSCustomObject.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Node,

        [Parameter(Mandatory)]
        [string] $Provider,

        [Parameter(Mandatory)]
        [string] $Id
    )

    $parts = $Id.Split(':', 3)
    $type = if ($Node.Type) { [string] $Node.Type } elseif ($parts.Count -eq 3) { $parts[1] } else { $null }
    $name = if ($Node.Name) { [string] $Node.Name } elseif ($parts.Count -eq 3) { $parts[2] } else { $null }
    $variant = if ($null -ne $Node.PSObject.Properties['Variant']) {
        $Node.Variant
    }
    elseif ($null -ne $Node.PSObject.Properties['Visibility']) {
        $Node.Visibility
    }
    else {
        $null
    }

    $metadata = [ordered]@{}
    foreach ($prop in $Node.PSObject.Properties) {
        if ($prop.Name -in @('PSTypeName', 'Id', 'Type', 'Name', 'Label', 'Visibility', 'Variant', 'ParentId', 'Link', 'IsGroup', 'Metadata')) {
            continue
        }
        $metadata[$prop.Name] = $prop.Value
    }
    if ($null -ne $Node.PSObject.Properties['Metadata'] -and $null -ne $Node.Metadata) {
        foreach ($prop in $Node.Metadata.PSObject.Properties) {
            $metadata[$prop.Name] = $prop.Value
        }
    }

    $irNode = [pscustomobject]@{
        PSTypeName = 'PS.DrawIO.IR.Node'
        Id         = $Id
        Provider   = $Provider
        Type       = $type
        Name       = $name
        Label      = $Node.Label
        ParentId   = $(if ($null -ne $Node.PSObject.Properties['ParentId']) { $Node.ParentId } else { $null })
        Link       = $(if ($null -ne $Node.PSObject.Properties['Link']) { $Node.Link } else { $null })
        Variant    = $variant
        IsGroup    = $(if ($null -ne $Node.PSObject.Properties['IsGroup']) { [bool] $Node.IsGroup } else { $false })
        Metadata   = [pscustomobject]$metadata
    }

    return $irNode
}
