# Front end for ConvertTo-ReviewLatex: generate .tex sources only (no LaTeX run).
#   pwsh-review-tex [config.yml] [output-dir] [--ignore-errors]
$ErrorActionPreference = 'Stop'

$positional = [System.Collections.Generic.List[string]]::new()
$ignoreErrors = $false
foreach ($arg in $args) {
    switch -CaseSensitive -Regex ([string]$arg) {
        '^(-h|--help)$' {
            Write-Host "Usage: pwsh-review-tex [config.yml] [output-dir (default: <bookname>-tex)] [--ignore-errors]"
            exit 0
        }
        '^--ignore-errors$' { $ignoreErrors = $true; break }
        '^-' { Write-Error "unknown option: $arg" }
        default { $positional.Add([string]$arg) }
    }
}

$configFile = if ($positional.Count -ge 1) { $positional[0] } else { 'config.yml' }
$outDir = if ($positional.Count -ge 2) { $positional[1] } else {
    $bookname = (Get-Content -LiteralPath $configFile | Where-Object { $_ -match '^bookname:\s*(\S+)' } |
        Select-Object -First 1) -replace '^bookname:\s*', ''
    "$(if ($bookname) { $bookname } else { 'book' })-tex"
}

Import-Module PwshReview
try {
    ConvertTo-ReviewLatex -Path $configFile -OutputDirectory $outDir -IgnoreCompileErrors:$ignoreErrors |
        ForEach-Object { Write-Host $_.FullName }
}
catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
