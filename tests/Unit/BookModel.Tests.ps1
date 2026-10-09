$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'ReviewCatalog + ReviewBookBase' {
    InModuleScope PwshReview {
        BeforeAll {
            [ReviewI18n]::Setup('ja')

            function New-TestBook {
                param([string]$Dir, [string]$CatalogYaml, [string]$ConfigYaml, [hashtable]$ChapterContents)

                New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                Set-Content -Path (Join-Path $Dir 'catalog.yml') -Value $CatalogYaml
                Set-Content -Path (Join-Path $Dir 'config.yml') -Value $ConfigYaml
                foreach ($name in $ChapterContents.Keys) {
                    Set-Content -Path (Join-Path $Dir $name) -Value $ChapterContents[$name]
                }
            }
        }

        It 'orders PREDEF, flat CHAPS, APPENDIX, POSTDEF chapters correctly (FirstStepReVIEW-v3 shape)' {
            $dir = Join-Path $TestDrive 'flatbook'
            New-TestBook -Dir $dir -CatalogYaml @'
PREDEF:
  - preface.re
CHAPS:
  - ch01.re
  - ch02.re
APPENDIX:
  - appA.re
POSTDEF:
  - contributors.re
'@ -ConfigYaml @'
review_version: 5
bookname: flatbook
'@ -ChapterContents @{
                'preface.re'      = "= Preface`n"
                'ch01.re'         = "= Chapter One`n"
                'ch02.re'         = "= Chapter Two`n"
                'appA.re'         = "= Appendix A`n"
                'contributors.re' = "= Contributors`n"
            }

            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            $book = [ReviewBookBase]::new($dir, $config)
            $ids = $book.Chapters() | ForEach-Object { $_.Id() }
            $ids | Should -Be @('preface', 'ch01', 'ch02', 'appA', 'contributors')

            $preface = $book.Chapters()[0]
            $preface.OnPredef() | Should -BeTrue
            $preface.OnChaps() | Should -BeFalse

            $ch01 = $book.Chapters()[1]
            $ch01.OnChaps() | Should -BeTrue
            $ch01.Number | Should -Be 1

            $appA = $book.Chapters()[3]
            $appA.OnAppendix() | Should -BeTrue
            $appA.Number | Should -Be 1

            $contrib = $book.Chapters()[4]
            $contrib.OnPostdef() | Should -BeTrue
        }

        It 'supports CHAPS part-grouping (hashtable entries), numbering chapters continuously across parts' {
            $dir = Join-Path $TestDrive 'partbook'
            New-TestBook -Dir $dir -CatalogYaml @'
CHAPS:
  - part1chaps:
      - p1c1.re
      - p1c2.re
  - part2chaps:
      - p2c1.re
'@ -ConfigYaml @'
review_version: 5
bookname: partbook
'@ -ChapterContents @{
                'p1c1.re' = "= P1C1`n"
                'p1c2.re' = "= P1C2`n"
                'p2c1.re' = "= P2C1`n"
            }

            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            $book = [ReviewBookBase]::new($dir, $config)

            $book.Parts().Count | Should -Be 2
            $book.Parts()[0].Chapters.Count | Should -Be 2
            $book.Parts()[1].Chapters.Count | Should -Be 1

            $allIds = $book.Chapters() | ForEach-Object { $_.Id() }
            $allIds | Should -Be @('p1c1', 'p1c2', 'p2c1')

            # chapter numbering continues across the part boundary (1,2,3 - not reset per part)
            ($book.Chapters() | ForEach-Object { $_.Number }) | Should -Be @(1, 2, 3)
        }

        It 'Catalog.Validate throws ReviewFileNotFoundError for a missing chapter file' {
            $dir = Join-Path $TestDrive 'missingchap'
            New-TestBook -Dir $dir -CatalogYaml @'
CHAPS:
  - doesnotexist.re
'@ -ConfigYaml @'
review_version: 5
'@ -ChapterContents @{}

            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            { [ReviewBookBase]::new($dir, $config) } | Should -Throw -ExceptionType ([ReviewFileNotFoundError])
        }

        It 'NextChapter/PrevChapter walk the flattened chapter list' {
            $dir = Join-Path $TestDrive 'navbook'
            New-TestBook -Dir $dir -CatalogYaml @'
CHAPS:
  - a.re
  - b.re
  - c.re
'@ -ConfigYaml @'
review_version: 5
'@ -ChapterContents @{
                'a.re' = "= A`n"
                'b.re' = "= B`n"
                'c.re' = "= C`n"
            }
            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            $book = [ReviewBookBase]::new($dir, $config)
            $chapters = $book.Chapters()
            $book.NextChapter($chapters[0]).Id() | Should -Be 'b'
            $book.PrevChapter($chapters[2]).Id() | Should -Be 'b'
            $book.NextChapter($chapters[2]) | Should -BeNullOrEmpty
        }

        It 'Chapter with a [nonum] headline tag gets Number = $null' {
            $dir = Join-Path $TestDrive 'nonumbook'
            New-TestBook -Dir $dir -CatalogYaml @'
CHAPS:
  - nonum.re
'@ -ConfigYaml @'
review_version: 5
'@ -ChapterContents @{
                'nonum.re' = "=[nonum] Untitled Chapter`n"
            }
            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            $book = [ReviewBookBase]::new($dir, $config)
            $book.Chapters()[0].Number | Should -BeNullOrEmpty
        }
    }
}

Describe 'ReviewChapter.FormatNumber / ReviewI18n' {
    InModuleScope PwshReview {
        BeforeAll {
            [ReviewI18n]::Setup('ja')

            function New-TestBook {
                param([string]$Dir, [string]$CatalogYaml, [string]$ConfigYaml, [hashtable]$ChapterContents)

                New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                Set-Content -Path (Join-Path $Dir 'catalog.yml') -Value $CatalogYaml
                Set-Content -Path (Join-Path $Dir 'config.yml') -Value $ConfigYaml
                foreach ($name in $ChapterContents.Keys) {
                    Set-Content -Path (Join-Path $Dir $name) -Value $ChapterContents[$name]
                }
            }
        }

        It 'formats a normal chapter number using the "chapter" locale string' {
            $dir = Join-Path $TestDrive 'fmtbook'
            New-TestBook -Dir $dir -CatalogYaml @'
CHAPS:
  - one.re
'@ -ConfigYaml @'
review_version: 5
'@ -ChapterContents @{ 'one.re' = "= One`n" }
            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            $book = [ReviewBookBase]::new($dir, $config)
            $chap = $book.Chapters()[0]
            # Literal expected string, not a second call to ReviewI18n::T -- comparing
            # against the same (possibly broken) function call would pass tautologically
            # even if substitution were silently broken, which it once was (ReviewI18n's
            # $Args-named parameter collided with PowerShell's automatic $args and
            # silently dropped all format arguments).
            $chap.FormatNumber($true) | Should -Be '第1章'
            $chap.FormatNumber($false) | Should -Be '1'
        }

        It 'formats an appendix chapter using the roman/alpha-aware "appendix" locale string' {
            $dir = Join-Path $TestDrive 'appfmtbook'
            New-TestBook -Dir $dir -CatalogYaml @'
APPENDIX:
  - a1.re
'@ -ConfigYaml @'
review_version: 5
'@ -ChapterContents @{ 'a1.re' = "= Appendix One`n" }
            $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
            $book = [ReviewBookBase]::new($dir, $config)
            $chap = $book.Chapters()[0]
            # Literal expected string -- see the note in the previous test for why this
            # must not be a second call to ReviewI18n::T.
            $chap.FormatNumber($true) | Should -Be '付録A'
        }
    }
}
