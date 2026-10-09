function Test-ReviewCatalog {
    <#
    .SYNOPSIS
        Loads a Re:VIEW project's config.yml + catalog.yml and prints the resolved,
        ordered chapter list -- the M1 smoke-test surface for the Book/Catalog/Configure
        model (mirrors what `review-pdfmaker` resolves before compiling anything).
    .PARAMETER Path
        Path to the project's config.yml (catalog.yml is expected alongside it, per
        config['catalogfile'], default 'catalog.yml').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $basedir = Split-Path -Parent $resolvedPath

    [ReviewI18n]::Setup('ja')
    $config = [ReviewConfigure]::Create('pdfmaker', $resolvedPath, $null)
    if ($config.Get('language')) {
        [ReviewI18n]::Setup([string]$config.Get('language'))
    }

    $book = [ReviewBookBase]::new($basedir, $config)

    [PSCustomObject]@{
        BookName   = $config.Get('bookname')
        Language   = $config.Get('language')
        Chapters   = @($book.Chapters() | ForEach-Object {
            [PSCustomObject]@{
                Id         = $_.Id()
                Number     = $_.Number
                OnPredef   = $_.OnPredef()
                OnChaps    = $_.OnChaps()
                OnAppendix = $_.OnAppendix()
                OnPostdef  = $_.OnPostdef()
            }
        })
    }
}
