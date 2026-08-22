# PSScriptAnalyzer suppression: function asserts about a collection of containers.
function Assert-PSDrawIOPesterContainers {
    <#
    .SYNOPSIS
        Fail when any Pester 5 container discovered zero tests.
    .DESCRIPTION
        Pester 5 containers do not populate .Tests after a run; use TotalCount.
        A container with TotalCount -eq 0 means discovery found nothing - the
        failure mode this guard exists to catch.
    .PARAMETER Result
        A Pester.Run object from Invoke-Pester -PassThru.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns',
        '',
        Justification = 'Asserts about a collection of Pester containers; plural noun is intentional.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Result
    )

    $containers = @($Result.Containers)
    if ($containers.Count -eq 0) {
        throw 'Pester: result contained no test containers.'
    }

    $ranNothing = @($containers | Where-Object { $_.TotalCount -eq 0 })
    if ($ranNothing) {
        $names = @($ranNothing | ForEach-Object {
                if ($_.Name) { $_.Name }
                elseif ($_.Item) { [string]$_.Item }
                else { '<unknown>' }
            })
        throw "Pester: container produced no tests: $($names -join ', ')"
    }
}
