function Invoke-PSDrawIOShapeResolver {
    <#
    .SYNOPSIS
    Invokes an injected shape resolver for one (Provider, Type) pair.

    .DESCRIPTION
    Calls -Resolver with Provider and Type. A null return or a thrown error is a
    terminating failure that names both the type and the provider. Core does not
    interpret declaration contents here.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Resolver,

        [Parameter(Mandatory)]
        [string] $Provider,

        [Parameter(Mandatory)]
        [string] $Type
    )

    $declaration = $null
    try {
        $declaration = & $Resolver $Provider $Type
    }
    catch {
        $inner = $_.Exception.Message
        throw ("Semantic type '{0}' is not registered for provider '{1}'. {2}" -f $Type, $Provider, $inner)
    }

    if ($null -eq $declaration) {
        throw ("Semantic type '{0}' is not registered for provider '{1}'." -f $Type, $Provider)
    }

    return $declaration
}
