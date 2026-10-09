<#
.SYNOPSIS
    (Re)captures golden .tex fixtures by running the REAL Ruby Re:VIEW (review-pdfmaker,
    inside the review-oracle Docker image) over each project in tests/Fixtures/.
.DESCRIPTION
    For each fixture: copies tests/Fixtures/<name> to a temp dir, runs
    `review-pdfmaker --debug config.yml` in the container, and copies every generated .tex
    (each chapter + __REVIEW_BOOK__.tex) into tests/Golden/<name>/.

    Fixture images are zero-byte placeholders (only their existence affects the .tex), so
    the LaTeX stage of the oracle run is EXPECTED to fail; --debug keeps the build dir
    regardless (pdfmaker.rb removes it in an `ensure` only when debug is off), and the
    .tex files are all written before uplatex runs. The script therefore checks that the
    .tex files exist rather than trusting the exit code.

    Run manually when the oracle version or a fixture changes; not part of the test run.
.EXAMPLE
    pwsh tests/tools/Update-GoldenFixtures.ps1
    pwsh tests/tools/Update-GoldenFixtures.ps1 -Fixture syntax-book -DockerImage review-oracle:5.9
#>
[CmdletBinding()]
param(
    [string[]]$Fixture,
    [string]$DockerImage = 'review-oracle:5.9'
)

$ErrorActionPreference = 'Stop'
$testsRoot = Split-Path $PSScriptRoot -Parent
$fixturesRoot = Join-Path $testsRoot 'Fixtures'
$goldenRoot = Join-Path $testsRoot 'Golden'

& docker image inspect $DockerImage *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker image '$DockerImage' not found. Build it: docker build -t $DockerImage docker-review/review-5.9"
}

if (-not $Fixture) { $Fixture = (Get-ChildItem -LiteralPath $fixturesRoot -Directory).Name }

foreach ($name in $Fixture) {
    $source = Join-Path $fixturesRoot $name
    $work = Join-Path ([IO.Path]::GetTempPath()) "pwshreview-golden-$name-$([guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath $source -Destination $work -Recurse

    try {
        $bookname = (Get-Content -LiteralPath (Join-Path $work 'config.yml') |
            Where-Object { $_ -match '^bookname:\s*(\S+)' } | Select-Object -First 1) -replace '^bookname:\s*', ''
        if (-not $bookname) { $bookname = 'book' }

        Write-Host "[$name] running review-pdfmaker in $DockerImage ..."
        $output = & docker run --rm -v "${work}:/work" -w /work $DockerImage review-pdfmaker --debug config.yml 2>&1
        Write-Verbose ($output -join "`n")

        $buildDir = Join-Path $work "$bookname-pdf"
        $texFiles = @(Get-ChildItem -LiteralPath $buildDir -Filter *.tex -ErrorAction SilentlyContinue)
        if (-not ($texFiles.Name -contains '__REVIEW_BOOK__.tex')) {
            throw "[$name] oracle produced no __REVIEW_BOOK__.tex. Output:`n$($output -join "`n")"
        }

        $dest = Join-Path $goldenRoot $name
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        New-Item -ItemType Directory -Path $dest | Out-Null
        $texFiles | Copy-Item -Destination $dest
        Write-Host "[$name] captured $($texFiles.Count) .tex files -> $dest"
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
