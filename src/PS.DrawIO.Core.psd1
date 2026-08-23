@{
    RootModule        = 'PS.DrawIO.Core.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a7c4e2b1-9f6d-4e8a-b3c5-1d0f8a6e4b29'
    Author            = 'Jerry Balmer'
    Description       = 'Serialization, layout, and XML emission for the PS.DrawIO ecosystem.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'ConvertTo-PSDrawIOIR'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('PSDrawIO', 'Core', 'drawio')
        }
    }
}
