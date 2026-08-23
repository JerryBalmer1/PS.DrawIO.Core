function Invoke-PSDrawIOLayout {
    <#
    .SYNOPSIS
    Runs a layout strategy over a Core IR, assigning vertex geometry.

    .DESCRIPTION
    Layout is a swappable pass. The default strategy is the built-in deterministic
    grid/stack placer. Pass -Strategy to substitute a scriptblock that receives
    the IR and returns the laid-out IR. Geometry belongs only in this pass.

    .PARAMETER IR
    Intermediate representation produced by ConvertTo-PSDrawIOIR (or equivalent).

    .PARAMETER Strategy
    Optional scriptblock strategy. Signature: param($IR)  IR. When omitted, the
    built-in strategy runs.

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
    '{0},{1}' -f $laidOut.Nodes[0].X, $laidOut.Nodes[0].Y
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $IR,

        [Parameter()]
        [scriptblock] $Strategy
    )

    process {
        if ($null -eq $IR) {
            throw 'IR is required.'
        }
        if ($null -eq $IR.PSObject.Properties['Nodes']) {
            throw 'IR is invalid: Nodes property is required.'
        }

        $result = $null
        if ($PSBoundParameters.ContainsKey('Strategy') -and $null -ne $Strategy) {
            $result = & $Strategy $IR
        }
        else {
            $result = Invoke-PSDrawIOBuiltinLayout -IR $IR
        }

        if ($null -eq $result) {
            throw 'Layout strategy returned null; expected an IR object with Nodes.'
        }
        if ($result -isnot [pscustomobject] -and $result -isnot [System.Management.Automation.PSObject]) {
            throw ("Layout strategy returned a non-IR object of type '{0}'; expected PSCustomObject IR." -f $result.GetType().FullName)
        }
        if ($null -eq $result.PSObject.Properties['Nodes']) {
            throw 'Layout strategy returned a non-IR object: Nodes property is missing.'
        }

        return $result
    }
}
