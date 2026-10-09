function Invoke-ReviewEpubMaker {
    <#
    .SYNOPSIS
        Builds a Re:VIEW project's config.yml into an EPUB3 -- the analog of
        `review-epubmaker config.yml [--debug] [-y file1,file2]`.
    .DESCRIPTION
        Compiles every chapter with the HTML builder, generates the title page, cover,
        colophon, navigation document and OPF package, and zips them into
        <bookname>.epub next to config.yml. Needs no Docker or external tools.
    .PARAMETER Path
        Path to the project's config.yml.
    .PARAMETER KeepBuildDir
        Keep the build directory (<bookname>-epub/ next to config.yml), mirroring
        `review-epubmaker --debug`.
    .PARAMETER Only
        Build only the named chapters (by filename, with or without .re), mirroring
        `review-epubmaker -y file1,file2`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$KeepBuildDir,

        [string[]]$Only
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $maker = [ReviewEpubMaker]::new()
    $maker.Execute($resolvedPath, [bool]$KeepBuildDir, $Only)

    Get-Item -LiteralPath $maker.EpubFilePath()
}
