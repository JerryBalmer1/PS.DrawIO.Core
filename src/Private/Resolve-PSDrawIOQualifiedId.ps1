function Resolve-PSDrawIOQualifiedId {
    <#
    .SYNOPSIS
    Ensures a node identity is provider-qualified as Provider:Type:Name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Node,

        [Parameter(Mandatory)]
        [string] $Provider
    )

    if ($null -eq $Node) {
        throw 'Cannot qualify a null IR node.'
    }

    $type = [string] $Node.Type
    $name = [string] $Node.Name
    $rawId = [string] $Node.Id

    if ($rawId -match '^[^:]+:[^:]+:.+$') {
        return $rawId
    }

    if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($name)) {
        throw "Cannot build provider-qualified Id for node; Type and Name are required when Id is not already 'Provider:Type:Name' (Id='$rawId')."
    }

    if ([string]::IsNullOrWhiteSpace($Provider)) {
        throw 'Provider is required to qualify node Ids.'
    }

    return ('{0}:{1}:{2}' -f $Provider, $type, $name)
}
