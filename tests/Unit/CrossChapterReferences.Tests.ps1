# M3: validates that the two-pass architecture (every chapter indexed across the WHOLE
# book before any chapter is rendered -- see ReviewBuilder.bind() and
# ReviewBookBase.GenerateIndexes()) correctly resolves cross-chapter references, both
# forward (chapter 1 referencing something defined in chapter 2) and backward.

$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'Cross-chapter reference resolution' {
    InModuleScope PwshReview {
        BeforeAll {
            [ReviewI18n]::Setup('ja')

            function New-TwoChapterBook {
                param([string]$Ch01Content, [string]$Ch02Content)

                $dir = Join-Path $TestDrive ([guid]::NewGuid())
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Set-Content -Path (Join-Path $dir 'catalog.yml') -Value "CHAPS:`n  - ch01.re`n  - ch02.re`n"
                Set-Content -Path (Join-Path $dir 'config.yml') -Value "review_version: 5`nbookname: test`ntexcommand: uplatex`n"
                Set-Content -Path (Join-Path $dir 'ch01.re') -Value $Ch01Content
                Set-Content -Path (Join-Path $dir 'ch02.re') -Value $Ch02Content

                $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
                $book = [ReviewBookBase]::new($dir, $config)
                $builder = [ReviewLATEXBuilder]::new()
                $converter = [ReviewConverter]::new($book, $builder)

                $results = @{}
                foreach ($name in @('ch01', 'ch02')) {
                    $outPath = Join-Path $dir "$name.tex"
                    $converter.Convert("$name.re", $outPath)
                    $results[$name] = Get-Content -Raw $outPath
                }
                return $results
            }
        }

        It 'resolves a FORWARD chapref from chapter 1 to chapter 2 (not yet rendered)' {
            $ch01 = "= First Chapter`n`nSee @<chapref>{ch02} for more.`n"
            $ch02 = "= Second Chapter`n`nbody.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            # chapter_quote format is "%s「%s」" -- number + title in guillemets
            $results['ch01'].Contains('第2章') | Should -BeTrue
            $results['ch01'].Contains('Second Chapter') | Should -BeTrue
        }

        It 'resolves a BACKWARD chapref from chapter 2 to chapter 1' {
            $ch01 = "= First Chapter`n`nbody.`n"
            $ch02 = "= Second Chapter`n`nSee @<chapref>{ch01} first.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            $results['ch02'].Contains('第1章') | Should -BeTrue
            $results['ch02'].Contains('First Chapter') | Should -BeTrue
        }

        It 'resolves chap across chapters (renders via format_number(heading=true), i.e. with the kanji chapter prefix -- confirmed against Ruby''s ChapterIndex#number/Chapter#format_number source)' {
            $ch01 = "= First Chapter`n`nNext is @<chap>{ch02}.`n"
            $ch02 = "= Second Chapter`n`nPrev was @<chap>{ch01}.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            $results['ch01'].Contains('Next is 第2章.') | Should -BeTrue
            $results['ch02'].Contains('Prev was 第1章.') | Should -BeTrue
        }

        It 'resolves title across chapters' {
            $ch01 = "= First Chapter`n`nTitle of next: @<title>{ch02}`n"
            $ch02 = "= Second Chapter`n`nbody.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            $results['ch01'].Contains('Second Chapter') | Should -BeTrue
        }

        It 'throws a clear error for a reference to a nonexistent chapter' {
            $ch01 = "= First Chapter`n`nSee @<chapref>{doesnotexist}.`n"
            $ch02 = "= Second Chapter`n`nbody.`n"
            # The reference error is caught by Compiler and surfaces as a compile
            # failure (mirrors Ruby's error -> @compile_errors=true -> raise path),
            # not an uncaught .NET exception.
            { New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02 } | Should -Throw -ExceptionType ([ReviewApplicationError])
        }
    }
}
