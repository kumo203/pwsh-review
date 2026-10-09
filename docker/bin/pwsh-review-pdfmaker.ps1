# review-pdfmaker-compatible front end for Invoke-ReviewPdfMaker.
#   pwsh-review-pdfmaker [config.yml] [--debug] [--ignore-errors] [-y file1,file2,...]
$ErrorActionPreference = 'Stop'

$usage = @'
Usage: pwsh-review-pdfmaker [config.yml] [options]
  --debug               Keep the build directory (<bookname>-pdf/).
  --ignore-errors       Build the PDF even if some chapters fail to compile.
  -y, --only a,b,...    Build only the named files.
  -h, --help            Show this help.
'@

$configFile = 'config.yml'
$keepBuildDir = $false
$ignoreErrors = $false
$only = $null

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    switch -CaseSensitive -Regex ($arg) {
        '^(-h|--help)$' { Write-Host $usage; exit 0 }
        '^--debug$' { $keepBuildDir = $true; break }
        '^--ignore-errors$' { $ignoreErrors = $true; break }
        '^(-y|--only)$' {
            $i++
            if ($i -ge $args.Count) { Write-Error "$arg requires a value" }
            $only = ([string]$args[$i]) -split '\s*,\s*'
            break
        }
        '^--only=(.+)$' { $only = $Matches[1] -split '\s*,\s*'; break }
        '^-' { Write-Host $usage; Write-Error "unknown option: $arg" }
        default { $configFile = $arg }
    }
}

Import-Module PwshReview
try {
    $pdf = Invoke-ReviewPdfMaker -Path $configFile -KeepBuildDir:$keepBuildDir -IgnoreCompileErrors:$ignoreErrors -Only $only
    Write-Host "built $($pdf.Name)"
}
catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
