# Root module. Classes are dot-sourced in an explicit, hand-maintained dependency order
# (NOT a sorted glob) because PowerShell parses a class's base-class/type references at
# parse time -- a class file that references a type defined in a later file would fail to
# parse, not just to run. Update this list whenever a new Classes/*.ps1 file is added, and
# keep new entries positioned after whatever they depend on.

$script:ClassFiles = @(
    'Classes\00.Exceptions.ps1'
    'Classes\01.LineInput.ps1'
    'Classes\02.YamlLoader.ps1'
    'Classes\03.Configure.ps1'
    'Classes\04.I18n.ps1'
    'Classes\05.Catalog.ps1'
    'Classes\05b.ImageFinder.ps1'
    'Classes\06.BookIndex.ps1'
    'Classes\07.BookUnit.ps1'
    'Classes\08.Chapter.ps1'
    'Classes\09.Part.ps1'
    'Classes\09b.Bib.ps1'
    'Classes\10.BookBase.ps1'
    'Classes\11.SecCounter.ps1'
    'Classes\12.LaTeXEscaper.ps1'
    'Classes\13.Compiler.ps1'
    'Classes\14.Builder.ps1'
    'Classes\15.IndexBuilder.ps1'
    'Classes\16.LATEXBuilder.ps1'
    'Classes\17.Converter.ps1'
    'Classes\18.LaTeXBox.ps1'
    'Classes\18b.ErbLiteTemplate.ps1'
    'Classes\20.ExternalProcessRunner.ps1'
    'Classes\19.PdfMaker.ps1'
)

foreach ($relativePath in $script:ClassFiles) {
    $fullPath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "PwshReview: expected class file not found: $fullPath"
    }
    . $fullPath
}

$script:PublicFunctionFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
$script:PrivateFunctionFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($file in @($script:PrivateFunctionFiles) + @($script:PublicFunctionFiles)) {
    if ($file) { . $file.FullName }
}

if ($script:PublicFunctionFiles) {
    Export-ModuleMember -Function $script:PublicFunctionFiles.BaseName
}
