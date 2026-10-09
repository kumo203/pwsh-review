function Invoke-ReviewPdfMaker {
    <#
    .SYNOPSIS
        Builds a Re:VIEW project's config.yml into a PDF -- the analog of
        `review-pdfmaker config.yml [--debug] [--ignore-errors] [-y file1,file2]`.
    .DESCRIPTION
        Shells every uplatex/mendex/dvipdfmx call into the review-oracle Docker
        container (see the README's "LaTeX backend" section); Docker Desktop must be
        running and the image must already be built/pulled.
    .PARAMETER Path
        Path to the project's config.yml.
    .PARAMETER KeepBuildDir
        Keep the build directory (as <bookname>-pdf/ next to the current location)
        instead of deleting it, mirroring `review-pdfmaker --debug`. Named KeepBuildDir,
        not Debug: [CmdletBinding()] already provides a built-in -Debug common parameter
        (tied to $DebugPreference), and redeclaring it would collide.
    .PARAMETER IgnoreCompileErrors
        Proceed to the PDF build even if some chapters failed to compile, mirroring
        `review-pdfmaker --ignore-errors`.
    .PARAMETER Only
        Build only the named chapters/parts (by filename, with or without .re),
        mirroring `review-pdfmaker -y file1,file2`.
    .PARAMETER DockerImage
        The Docker image to shell uplatex/mendex/dvipdfmx into. Defaults to
        'review-oracle:5.9'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$KeepBuildDir,

        [switch]$IgnoreCompileErrors,

        [string[]]$Only,

        [string]$DockerImage = 'review-oracle:5.9'
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $maker = [ReviewPdfMaker]::new()
    $maker.DockerImage = $DockerImage
    $maker.Execute($resolvedPath, [bool]$KeepBuildDir, [bool]$IgnoreCompileErrors, $Only)

    Get-Item -LiteralPath $maker.PdfFilePath()
}
