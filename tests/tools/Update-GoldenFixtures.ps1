<#
.SYNOPSIS
    (Re)captures golden fixtures by running the REAL Ruby Re:VIEW (review-pdfmaker and
    review-epubmaker, inside the review-oracle Docker image) over each project in
    tests/Fixtures/.
.DESCRIPTION
    For each fixture, in a temp copy of tests/Fixtures/<name>:

    - LaTeX: `review-pdfmaker --debug config.yml`, then every generated .tex (each chapter
      + __REVIEW_BOOK__.tex) is copied to tests/Golden/latex/<name>/.
      Fixture images are zero-byte placeholders (only their existence affects the .tex),
      so the LaTeX stage of this run is EXPECTED to fail; --debug keeps the build dir
      regardless (pdfmaker.rb removes it in an `ensure` only when debug is off), and the
      .tex files are all written before uplatex runs. The script therefore checks that
      the .tex files exist rather than trusting the exit code.

    - EPUB: `review-epubmaker --debug config.yml`, then the generated package files
      (mimetype, META-INF/container.xml, OEBPS/*.xhtml and *.opf -- not the copied images
      or stylesheets) are copied to tests/Golden/epub/<name>/, plus entries.txt listing
      the .epub's zip entries in order.

    Run manually when the oracle version or a fixture changes; not part of the test run.
.EXAMPLE
    pwsh tests/tools/Update-GoldenFixtures.ps1
    pwsh tests/tools/Update-GoldenFixtures.ps1 -Fixture syntax-book -Target epub
#>
[CmdletBinding()]
param(
    [string[]]$Fixture,
    [ValidateSet('latex', 'epub')]
    [string[]]$Target = @('latex', 'epub'),
    [string]$DockerImage = 'review-oracle:5.9'
)

$ErrorActionPreference = 'Stop'
$testsRoot = Split-Path $PSScriptRoot -Parent
$fixturesRoot = Join-Path $testsRoot 'Fixtures'
$goldenRoot = Join-Path $testsRoot 'Golden'
Add-Type -AssemblyName System.IO.Compression.FileSystem

& docker image inspect $DockerImage *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker image '$DockerImage' not found. Build it: docker build -t $DockerImage docker-review/review-5.9"
}

if (-not $Fixture) { $Fixture = (Get-ChildItem -LiteralPath $fixturesRoot -Directory).Name }

function Reset-Directory([string]$Path) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    New-Item -ItemType Directory -Path $Path | Out-Null
}

foreach ($name in $Fixture) {
    $source = Join-Path $fixturesRoot $name
    $work = Join-Path ([IO.Path]::GetTempPath()) "pwshreview-golden-$name-$([guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath $source -Destination $work -Recurse

    try {
        $bookname = (Get-Content -LiteralPath (Join-Path $work 'config.yml') |
            Where-Object { $_ -match '^bookname:\s*(\S+)' } | Select-Object -First 1) -replace '^bookname:\s*', ''
        if (-not $bookname) { $bookname = 'book' }

        if ($Target -contains 'latex') {
            Write-Host "[$name] running review-pdfmaker in $DockerImage ..."
            $output = & docker run --rm -v "${work}:/work" -w /work $DockerImage review-pdfmaker --debug config.yml 2>&1
            Write-Verbose ($output -join "`n")

            $buildDir = Join-Path $work "$bookname-pdf"
            $texFiles = @(Get-ChildItem -LiteralPath $buildDir -Filter *.tex -ErrorAction SilentlyContinue)
            if (-not ($texFiles.Name -contains '__REVIEW_BOOK__.tex')) {
                throw "[$name] oracle produced no __REVIEW_BOOK__.tex. Output:`n$($output -join "`n")"
            }
            $dest = Join-Path $goldenRoot "latex/$name"
            Reset-Directory $dest
            $texFiles | Copy-Item -Destination $dest
            Write-Host "[$name] captured $($texFiles.Count) .tex files -> $dest"
        }

        if ($Target -contains 'epub') {
            Write-Host "[$name] running review-epubmaker in $DockerImage ..."
            $output = & docker run --rm -v "${work}:/work" -w /work $DockerImage review-epubmaker --debug config.yml 2>&1
            Write-Verbose ($output -join "`n")

            $epubFile = Join-Path $work "$bookname.epub"
            $pkgDir = Join-Path $work "$bookname-epub/$bookname-epub"
            if (-not (Test-Path -LiteralPath $epubFile) -or -not (Test-Path -LiteralPath $pkgDir)) {
                throw "[$name] oracle produced no EPUB. Output:`n$($output -join "`n")"
            }
            $dest = Join-Path $goldenRoot "epub/$name"
            Reset-Directory $dest
            $count = 0
            foreach ($f in Get-ChildItem -LiteralPath $pkgDir -Recurse -File) {
                $rel = [IO.Path]::GetRelativePath($pkgDir, $f.FullName).Replace('\', '/')
                if ($rel -ne 'mimetype' -and $rel -notmatch '\.(xhtml|html|opf|xml)$') { continue }
                # (not $target: PowerShell variables are case-insensitive, so that would
                # reassign the validated -Target parameter)
                $destFile = Join-Path $dest $rel
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destFile) | Out-Null
                Copy-Item -LiteralPath $f.FullName -Destination $destFile
                $count++
            }
            $zip = [IO.Compression.ZipFile]::OpenRead($epubFile)
            try { $entries = @($zip.Entries | ForEach-Object FullName) } finally { $zip.Dispose() }
            [IO.File]::WriteAllText((Join-Path $dest 'entries.txt'), (($entries -join "`n") + "`n"))
            Write-Host "[$name] captured $count EPUB package files + entries.txt -> $dest"
        }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
