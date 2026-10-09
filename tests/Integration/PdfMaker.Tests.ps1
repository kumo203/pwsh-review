# M4: produces a real PDF via the Docker-backed uplatex/mendex/dvipdfmx pipeline, and
# independently verifies the generated __REVIEW_BOOK__.tex master file against the real
# Ruby Re:VIEW oracle (review-oracle:5.9) -- with deterministic inputs (pinned date/
# urnid), the two are byte-for-byte identical (confirmed manually while building this;
# captured here as a lasting regression test). Requires Docker Desktop running and the
# review-oracle:5.9 image already built (see README Prerequisites).

$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

$dockerAvailable = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
$oracleImageAvailable = $false
if ($dockerAvailable) {
    & docker image inspect review-oracle:5.9 *> $null
    $oracleImageAvailable = ($LASTEXITCODE -eq 0)
}

Describe 'ReviewPdfMaker (M4: real Docker-backed PDF build)' -Skip:(-not ($dockerAvailable -and $oracleImageAvailable)) {
    BeforeAll {
        $script:TestDir = Join-Path $TestDrive 'm4book'
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

        Set-Content -Path (Join-Path $script:TestDir 'catalog.yml') -Value "CHAPS:`n  - ch01.re`n"
        Set-Content -Path (Join-Path $script:TestDir 'config.yml') -Value @'
review_version: 5
bookname: m4test
booktitle: M4 Test Book
aut: Test Author
language: ja
date: "2026-10-09"
urnid: "urn:uuid:00000000-0000-0000-0000-000000000000"
texcommand: uplatex
texoptions: '-interaction=nonstopmode -file-line-error -halt-on-error'
dvicommand: dvipdfmx
dvioptions: '-d 5 -z 9'
texstyle: ["reviewmacro"]
texdocumentclass: ["review-jsbook", "media=print,paper=b5"]
toc: false
titlepage: true
colophon: false
'@
        $chapterLines = @(
            '= Hello World',
            '',
            'This is a @<b>{bold} test paragraph.',
            '',
            ' * item one',
            ' * item two'
        )
        Set-Content -Path (Join-Path $script:TestDir 'ch01.re') -Value ($chapterLines -join "`n")
    }

    It 'produces a real, valid PDF' {
        $pdf = Invoke-ReviewPdfMaker -Path (Join-Path $script:TestDir 'config.yml')
        $pdf.Exists | Should -BeTrue
        $pdf.Length | Should -BeGreaterThan 1000

        $header = [System.IO.File]::ReadAllBytes($pdf.FullName)[0..3]
        ([System.Text.Encoding]::ASCII.GetString($header)) | Should -Be '%PDF'

        Remove-Item -LiteralPath $pdf.FullName -Force -ErrorAction SilentlyContinue
    }

    It 'generates a __REVIEW_BOOK__.tex byte-for-byte identical to the real Ruby Re:VIEW oracle' {
        Push-Location $script:TestDir
        try {
            $pdf = Invoke-ReviewPdfMaker -Path (Join-Path $script:TestDir 'config.yml') -KeepBuildDir
            $oursPath = Join-Path $script:TestDir 'm4test-pdf\__REVIEW_BOOK__.tex'
            Test-Path -LiteralPath $oursPath | Should -BeTrue
            $ours = Get-Content -LiteralPath $oursPath -Raw

            # Build the same fixture through the real Ruby Re:VIEW in the oracle
            # container (needs the review-jsbook .sty/.cls files vendored into sty/,
            # exactly as a real Re:VIEW project is expected to do -- see README).
            $styDir = Join-Path $script:TestDir 'sty'
            if (-not (Test-Path -LiteralPath $styDir)) {
                New-Item -ItemType Directory -Path $styDir -Force | Out-Null
                $bundled = Join-Path $PSScriptRoot '..\..\Resources\latex\review-jsbook'
                Copy-Item -Path (Join-Path $bundled '*') -Destination $styDir -Force
            }

            Remove-Item -LiteralPath (Join-Path $script:TestDir 'm4test-pdf') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $script:TestDir 'm4test.pdf') -Recurse -Force -ErrorAction SilentlyContinue

            $env:MSYS_NO_PATHCONV = '1'
            & docker run --rm -v "${script:TestDir}:/work" -w /work review-oracle:5.9 review-pdfmaker --debug config.yml *> $null
            $oraclePath = Join-Path $script:TestDir 'm4test-pdf\__REVIEW_BOOK__.tex'
            Test-Path -LiteralPath $oraclePath | Should -BeTrue
            $oracle = Get-Content -LiteralPath $oraclePath -Raw

            $ours | Should -Be $oracle
        }
        finally {
            Pop-Location
        }
    }
}
