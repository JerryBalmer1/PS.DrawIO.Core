function Test-PSDrawIODiagramStructuralRoot {
    <#
    .SYNOPSIS
    Enforces structural root cells id 0 and id 1 parent=0 (CORE.md).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Content
    )

    try {
        $doc = [xml]$Content
    }
    catch {
        throw ("Diagram schema validation failed: XML is not well-formed — {0}" -f $_.Exception.Message)
    }

    $cells = @($doc.SelectNodes('//mxCell'))
    $has0 = $false
    $has1 = $false
    foreach ($c in $cells) {
        if ($c.id -eq '0') { $has0 = $true }
        if ($c.id -eq '1' -and $c.parent -eq '0') { $has1 = $true }
    }
    # UserObject may carry id; nested mxCell may omit id (schema dual-id optional).
    if (-not $has0 -or -not $has1) {
        foreach ($uo in @($doc.SelectNodes('//UserObject')) + @($doc.SelectNodes('//object'))) {
            if ($uo.id -eq '0') { $has0 = $true }
            if ($uo.id -eq '1') {
                $nested = $uo.SelectSingleNode('mxCell')
                if ($null -ne $nested -and $nested.parent -eq '0') { $has1 = $true }
            }
        }
    }

    if (-not $has0) {
        throw 'Diagram schema validation failed: missing required structural mxCell id="0" (root container).'
    }
    if (-not $has1) {
        throw 'Diagram schema validation failed: missing required structural mxCell id="1" with parent="0" (default layer).'
    }
}
