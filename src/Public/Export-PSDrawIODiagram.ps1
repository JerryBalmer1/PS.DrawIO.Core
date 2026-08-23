function Export-PSDrawIODiagram {
    <#
    .SYNOPSIS
    Writes a laid-out Core IR to an uncompressed .drawio file.

    .DESCRIPTION
    Builds draw.io XML via the DOM (no string-concatenated markup) and saves it
    to -Path. Geometry is taken from the IR; run Invoke-PSDrawIOLayout first.
    XML comments are never emitted. Root cells id 0 and id 1 parent=0 are always
    present.

    .PARAMETER IR
    Intermediate representation (typically after Invoke-PSDrawIOLayout).

    .PARAMETER Path
    Destination .drawio file path. Parent directory must exist.

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
    $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider PowerShell
    $laidOut = Invoke-PSDrawIOLayout -IR $ir
    $path = Join-Path $env:TEMP 'ps-drawio-core-example.drawio'
    Export-PSDrawIODiagram -IR $laidOut -Path $path
    Get-Content -LiteralPath $path -TotalCount 20
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $IR,

        [Parameter(Mandatory)]
        [string] $Path
    )

    process {
        if ($null -eq $IR) { throw 'IR is required.' }
        if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path is required.' }

        $xmlText = ConvertTo-PSDrawIODiagramXml -IR $IR

        if ($PSCmdlet.ShouldProcess($Path, 'Export draw.io diagram')) {
            $full = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            $dir = Split-Path -Parent $full
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                throw ("Export directory does not exist: '{0}'." -f $dir)
            }
            # T-002: write the string, never the XmlDocument object.
            [System.IO.File]::WriteAllText($full, $xmlText, [System.Text.UTF8Encoding]::new($false))
            return $full
        }
    }
}
