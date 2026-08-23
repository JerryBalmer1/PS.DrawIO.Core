function Add-PSDrawIOResolvedDeclaration {
    <#
    .SYNOPSIS
    Copies declaration fields returned by a resolver onto an IR node or edge.

    .DESCRIPTION
    Applies only what the declaration carries. Style maps to Style (and
    ResolvedStyle for emission). LinkTemplate maps to LinkTemplate. Unknown
    properties are ignored. Nothing is invented when a field is absent.
    Geometry is never written here.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [object] $Declaration
    )

    if ($null -eq $Declaration -or $null -eq $Declaration.PSObject) {
        return $Target
    }

    $props = $Declaration.PSObject.Properties

    if ($null -ne $props['Style'] -and -not [string]::IsNullOrWhiteSpace([string]$Declaration.Style)) {
        $style = [string]$Declaration.Style
        $Target | Add-Member -NotePropertyName Style -NotePropertyValue $style -Force
        $Target | Add-Member -NotePropertyName ResolvedStyle -NotePropertyValue $style -Force
    }

    if ($null -ne $props['LinkTemplate'] -and -not [string]::IsNullOrWhiteSpace([string]$Declaration.LinkTemplate)) {
        $Target | Add-Member -NotePropertyName LinkTemplate -NotePropertyValue ([string]$Declaration.LinkTemplate) -Force
    }

    return $Target
}
