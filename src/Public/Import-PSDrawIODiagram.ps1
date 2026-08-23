function Import-PSDrawIODiagram {
    <#
    .SYNOPSIS
    Reads a .drawio file into a Core intermediate representation (IR).

    .DESCRIPTION
    Parses uncompressed draw.io mxfile XML via the XML DOM and returns a
    PS.DrawIO.IR object that Export-PSDrawIODiagram accepts. Unknown attributes
    are preserved on IR Metadata for round-trip. Node Ids are kept as written
    in the file (including bare ids from hand-edited diagrams).

    .PARAMETER Path
    Path to a .drawio (or .xml) diagram file.

    .EXAMPLE
    $path = Join-Path $env:TEMP 'module.drawio'
    $ir = Import-PSDrawIODiagram -Path $path
    $ir.Nodes[0].Id
    $ir.Nodes[0].Label
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Path is required.'
    }

    $full = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $full)) {
        throw ("Draw.io file not found: '{0}'." -f $full)
    }

    # T-002: read text; never pipe XmlDocument to file writers later.
    $text = [System.IO.File]::ReadAllText($full)
    return (ConvertFrom-PSDrawIODiagramXml -XmlText $text -SourcePath $full)
}
