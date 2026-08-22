[CmdletBinding()]
param([ValidateSet('All', 'Clean', 'Analyze', 'Test', 'Package')][string]$Task = 'All')

& (Join-Path $PSScriptRoot 'build/build.ps1') -Task $Task
