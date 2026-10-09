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
                param([string]$Ch01Content, [string]$Ch02Content, [string[]]$ConvertOnly = @('ch01', 'ch02'))

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

                # Converting a chapter runs it through the real LATEXBuilder pass, which
                # will fail on syntax this port doesn't render yet (//table/#//image are
                # deferred to M5). The OTHER chapter's cross-reference still resolves
                # correctly without converting it directly: Book.GenerateIndexes() (run
                # from Bind() during the FIRST chapter's conversion) indexes every
                # chapter via its own IndexBuilder pass regardless of which chapters are
                # ever actually converted through LATEXBuilder.
                $results = @{}
                foreach ($name in $ConvertOnly) {
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

            # Exact line verified against the review-oracle:5.9 Docker oracle. (An earlier
            # version of this test only checked substrings like '第2章', which kept
            # passing even while the \reviewchapref{}{} hyperlink wrapping that
            # LATEXBuilder applies under the default chapterlink: true was missing.)
            $results['ch01'].Contains('See \reviewchapref{第2章「Second Chapter」}{chap:ch02} for more.') | Should -BeTrue
        }

        It 'resolves a BACKWARD chapref from chapter 2 to chapter 1' {
            $ch01 = "= First Chapter`n`nbody.`n"
            $ch02 = "= Second Chapter`n`nSee @<chapref>{ch01} first.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            $results['ch02'].Contains('See \reviewchapref{第1章「First Chapter」}{chap:ch01} first.') | Should -BeTrue
        }

        It 'resolves chap across chapters (format_number(heading=true), wrapped in \reviewchapref -- verified against the Docker oracle)' {
            $ch01 = "= First Chapter`n`nNext is @<chap>{ch02}.`n"
            $ch02 = "= Second Chapter`n`nPrev was @<chap>{ch01}.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            $results['ch01'].Contains('Next is \reviewchapref{第2章}{chap:ch02}.') | Should -BeTrue
            $results['ch02'].Contains('Prev was \reviewchapref{第1章}{chap:ch01}.') | Should -BeTrue
        }

        It 'resolves title across chapters' {
            $ch01 = "= First Chapter`n`nTitle of next: @<title>{ch02}`n"
            $ch02 = "= Second Chapter`n`nbody.`n"
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02

            $results['ch01'].Contains('Title of next: \reviewchapref{Second Chapter}{chap:ch02}') | Should -BeTrue
        }

        It 'resolves a cross-chapter @<list> reference (ch01 -> a list numbered/captioned in ch02)' {
            $ch01 = "= First Chapter`n`nSee @<list>{ch02|mylist} for details.`n"
            $ch02 = @'
= Second Chapter

//list[mylist][My List]{
some code
//}
'@
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02
            # LATEXBuilder overrides inline_list to wrap in \reviewlistref{} (TeX-native
            # ref/label wiring) rather than the generic Builder's plain-text rendering --
            # confirmed against the real Ruby Re:VIEW oracle (review-oracle:5.9).
            $results['ch01'].Contains('\reviewlistref{2.1}') | Should -BeTrue
        }

        It 'resolves a cross-chapter @<table> reference (ch01 -> a table numbered in ch02)' {
            $ch01 = "= First Chapter`n`nSee @<table>{ch02|mytable}.`n"
            $ch02 = @'
= Second Chapter

//table[mytable][My Table]{
a	b
------------
1	2
//}
'@
            # //table isn't rendered by LATEXBuilder yet (deferred to M5), so only
            # convert ch01 -- ch02's table is still indexed via Book.GenerateIndexes().
            $results = New-TwoChapterBook -Ch01Content $ch01 -Ch02Content $ch02 -ConvertOnly @('ch01')
            # Verified against the real Ruby Re:VIEW oracle: \reviewtableref{2.1}{table:ch02:mytable}
            $results['ch01'].Contains('\reviewtableref{2.1}{table:ch02:mytable}') | Should -BeTrue
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
