# M6: end-to-end parity on a real book, TechBooster's FirstStepReVIEW-v3.
#
# The book's text is all-rights-reserved (its README forbids redistribution/modification),
# so neither its sources nor the generated .tex (which contains the text) are vendored
# here. Instead this test needs a local checkout -- default ../FirstStepReVIEW-v3 next to
# this repo, or $env:PWSHREVIEW_FIRSTSTEP_PATH -- and produces the oracle output on the
# fly with the real Ruby Re:VIEW in review-oracle:5.9. Skipped if either is missing.
#
# Checks: every chapter .tex + __REVIEW_BOOK__.tex byte-for-byte identical to the
# oracle's, then a full PDF build through the port with the same page count and
# identical extracted text (PDF bytes differ only by creation-time metadata).

$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

function Get-FirstStepArticlesDir {
    $root = if ($env:PWSHREVIEW_FIRSTSTEP_PATH) { $env:PWSHREVIEW_FIRSTSTEP_PATH }
            else { Join-Path $PSScriptRoot '..\..\..\FirstStepReVIEW-v3' }
    return (Join-Path $root 'articles')
}
$fixtureAvailable = Test-Path -LiteralPath (Join-Path (Get-FirstStepArticlesDir) 'config.yml')

$dockerAvailable = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
$oracleImageAvailable = $false
if ($dockerAvailable) {
    & docker image inspect review-oracle:5.9 *> $null
    $oracleImageAvailable = ($LASTEXITCODE -eq 0)
}

Describe 'FirstStepReVIEW-v3 end-to-end parity with Ruby Re:VIEW 5.9.0 (M6)' -Skip:(-not ($fixtureAvailable -and $dockerAvailable -and $oracleImageAvailable)) {
    BeforeAll {
        # Discovery-time variables are not visible here (Pester 5), so re-resolve.
        $articlesDir = Join-Path (Join-Path $PSScriptRoot '..\..\..\FirstStepReVIEW-v3') 'articles'
        if ($env:PWSHREVIEW_FIRSTSTEP_PATH) { $articlesDir = Join-Path $env:PWSHREVIEW_FIRSTSTEP_PATH 'articles' }
        $script:OracleDir = Join-Path $TestDrive 'oracle'
        $script:OursDir = Join-Path $TestDrive 'ours'
        Copy-Item -LiteralPath $articlesDir -Destination $script:OracleDir -Recurse
        Copy-Item -LiteralPath $articlesDir -Destination $script:OursDir -Recurse

        $env:MSYS_NO_PATHCONV = '1'
        & docker run --rm -v "${script:OracleDir}:/work" -w /work review-oracle:5.9 review-pdfmaker --debug config.yml *> $null
        $script:OracleTexDir = Join-Path $script:OracleDir 'FirstStepReVIEW-v3-pdf'

        $script:OursTexDir = Join-Path $TestDrive 'ours-tex'
        ConvertTo-ReviewLatex -Path (Join-Path $script:OursDir 'config.yml') -OutputDirectory $script:OursTexDir 3>$null | Out-Null

        function Get-PdfFacts([string]$PdfPath) {
            $dir = Split-Path -Parent $PdfPath
            $name = Split-Path -Leaf $PdfPath
            $out = & docker run --rm -v "${dir}:/p" review-oracle:5.9 sh -c "pdfinfo '/p/$name' | grep '^Pages:'; pdftotext '/p/$name' - | md5sum"
            return @{ Pages = ($out[0] -replace '\D', ''); TextHash = ($out[1] -split '\s')[0] }
        }
    }

    It 'oracle produced the expected chapter set' {
        $names = @(Get-ChildItem -LiteralPath $script:OracleTexDir -Filter *.tex).Name
        $names | Should -Contain '__REVIEW_BOOK__.tex'
        $names.Count | Should -Be 13
    }

    It 'generates every .tex byte-for-byte identical to the oracle' {
        $mismatches = foreach ($f in Get-ChildItem -LiteralPath $script:OracleTexDir -Filter *.tex) {
            $ours = Join-Path $script:OursTexDir $f.Name
            if (-not (Test-Path -LiteralPath $ours)) { "$($f.Name) (missing)"; continue }
            if ([IO.File]::ReadAllText($f.FullName) -cne [IO.File]::ReadAllText($ours)) { $f.Name }
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'builds a PDF with the same page count and identical extracted text' {
        $pdf = Invoke-ReviewPdfMaker -Path (Join-Path $script:OursDir 'config.yml') 3>$null
        $pdf.Exists | Should -BeTrue

        $oracleFacts = Get-PdfFacts (Join-Path $script:OracleDir 'FirstStepReVIEW-v3.pdf')
        $oursFacts = Get-PdfFacts $pdf.FullName
        $oursFacts.Pages | Should -Be $oracleFacts.Pages
        $oursFacts.TextHash | Should -Be $oracleFacts.TextHash
    }
}
