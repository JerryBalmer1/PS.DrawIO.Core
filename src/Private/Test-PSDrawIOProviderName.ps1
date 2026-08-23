function Test-PSDrawIOProviderName {
    <#
    .SYNOPSIS
    Validates a provider name against the ecosystem naming rule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Invalid Provider name '' (empty). Rule: PascalCase letters and digits only, matching ^[A-Z][A-Za-z0-9]+$ (no dots)."
    }

    if ($Name -notmatch '^[A-Z][A-Za-z0-9]+$') {
        throw ("Invalid Provider name '{0}'. Rule: PascalCase letters and digits only, matching ^[A-Z][A-Za-z0-9]+$ (no dots)." -f $Name)
    }
}
