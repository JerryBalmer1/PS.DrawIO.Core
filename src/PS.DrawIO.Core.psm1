$moduleRoot = Split-Path -Parent $PSCommandPath

foreach ($folder in @('Classes', 'Private', 'Public')) {
    $path = Join-Path $moduleRoot $folder
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Filter '*.ps1' |
            Sort-Object Name |
            ForEach-Object { . $_.FullName }
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-PSDrawIOIR',
    'Invoke-PSDrawIOLayout',
    'Export-PSDrawIODiagram',
    'Import-PSDrawIODiagram',
    'Test-PSDrawIODiagramSchema'
)
