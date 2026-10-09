# review-epubmaker-compatible front end for Invoke-ReviewEpubMaker.
#   pwsh-review-epubmaker [config.yml] [--debug] [-y file1,file2,...]
$ErrorActionPreference = 'Stop'

$usage = @'
Usage: pwsh-review-epubmaker [config.yml] [options]
  --debug               Keep the build directory (<bookname>-epub/).
  -y, --only a,b,...    Build only the named files.
  -h, --help            Show this help.
'@

$configFile = 'config.yml'
$keepBuildDir = $false
$only = $null

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    switch -CaseSensitive -Regex ($arg) {
        '^(-h|--help)$' { Write-Host $usage; exit 0 }
        '^--debug$' { $keepBuildDir = $true; break }
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
    $epub = Invoke-ReviewEpubMaker -Path $configFile -KeepBuildDir:$keepBuildDir -Only $only
    Write-Host "built $($epub.Name)"
}
catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
