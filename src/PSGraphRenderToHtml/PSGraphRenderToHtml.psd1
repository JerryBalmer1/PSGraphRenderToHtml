@{
    RootModule           = 'PSGraphRenderToHtml.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'e076328c-a8d8-4789-b423-c296f7a9d2ad'
    Author               = 'JerryBalmer1'
    CompanyName          = 'JerryBalmer1'
    Copyright            = '(c) JerryBalmer1. MIT.'
    Description          = 'The battery between a producer and PSGraphRender: one producer-graph contract, options, view model mapping, and a contract battery any producer can run against its own output.'
    CompatiblePSEditions = @('Core')
    PowerShellVersion    = '7.2'

    # RUNTIME dependency, which is a different thing from a build one.
    # Requirements.psd1 pins what is needed to build; this says what is needed
    # to run. ModuleVersion is a FLOOR - it accepts every version above it -
    # which is a hazard PSGraphRender's own handoff names by name. It is a floor
    # here deliberately: a pin would make every renderer patch a breaking change
    # for this module, and the battery is what catches an incompatible one.
    RequiredModules      = @(
        @{ ModuleName = 'PSGraphRender'; ModuleVersion = '0.13.0' }
    )

    FunctionsToExport    = @(
        'ConvertTo-GraphRenderViewModel'
        'Export-ProducerGraphHtml'
        'New-GraphRenderOptions'
        'Test-ProducerGraph'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('graph', 'html', 'visualisation', 'contract')
            LicenseUri = 'https://github.com/JerryBalmer1/PSGraphRenderToHtml/blob/main/LICENSE'
            ProjectUri = 'https://github.com/JerryBalmer1/PSGraphRenderToHtml'
        }
    }
}
