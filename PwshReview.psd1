@{
    RootModule        = 'PwshReview.psm1'
    ModuleVersion      = '0.1.0'
    GUID               = 'b6e7c8b2-6e3d-4b7a-9b7b-1a7e8e9f9b1a'
    Author             = 'PwshReview contributors'
    Description        = 'A PowerShell port of the Re:VIEW (https://reviewml.org) PDF generation pipeline.'
    PowerShellVersion  = '7.0'
    RequiredModules    = @('powershell-yaml')
    FunctionsToExport  = @(
        'Invoke-ReviewPdfMaker'
        'Test-ReviewCatalog'
        'ConvertTo-ReviewLatex'
        'Invoke-ReviewEpubMaker'
    )
    CmdletsToExport    = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
}
