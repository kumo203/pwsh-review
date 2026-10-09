function ConvertTo-ReviewLatex {
    <#
    .SYNOPSIS
        Compiles a Re:VIEW project to LaTeX sources -- every chapter's .tex plus the
        master __REVIEW_BOOK__.tex -- WITHOUT running the LaTeX toolchain.
    .DESCRIPTION
        Runs the same pipeline as Invoke-ReviewPdfMaker (two-pass compile, templates,
        colophon, project-local .erb overrides) up to the point where uplatex would be
        invoked, so it needs no Docker. Useful for inspecting/diffing generated LaTeX.
    .PARAMETER Path
        Path to the project's config.yml.
    .PARAMETER OutputDirectory
        Directory to write the .tex files into (created if missing).
    .PARAMETER IgnoreCompileErrors
        Keep going even if some chapters fail to compile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [switch]$IgnoreCompileErrors
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $maker = [ReviewPdfMaker]::new()
    $maker.ExecuteTexOnly($resolvedPath, $OutputDirectory, [bool]$IgnoreCompileErrors)

    Get-ChildItem -LiteralPath $maker.Path -Filter *.tex
}
