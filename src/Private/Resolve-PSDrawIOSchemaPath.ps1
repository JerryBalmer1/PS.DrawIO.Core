function Resolve-PSDrawIOSchemaPath {
    <#
    .SYNOPSIS
    Resolves the vendored mxfile.xsd path relative to the loaded module root.

    .DESCRIPTION
    Uses $PSScriptRoot (Private/) → parent module root → Schema/mxfile.xsd.
    Works from source layout (src/) and packaged layout (dist/PS.DrawIO.Core/).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Private/ → module root (one Split-Path). Do not climb past the module root
    # (Registry packaging bug: two Split-Path calls broke dist/).
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $xsd = Join-Path $moduleRoot 'Schema/mxfile.xsd'
    if (-not (Test-Path -LiteralPath $xsd)) {
        throw ("mxfile.xsd not found at module-relative path '{0}'." -f $xsd)
    }
    return (Resolve-Path -LiteralPath $xsd).Path
}
