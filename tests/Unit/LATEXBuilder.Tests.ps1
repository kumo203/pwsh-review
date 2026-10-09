# Exact-string assertions in the spirit of review/test/test_latexbuilder.rb: each test
# compiles a small markup snippet through the REAL two-pass Compiler+Builder pipeline
# (not a hand-rolled stub) and asserts the exact LaTeX string produced. The first test
# ("golden scenario") was independently verified byte-for-byte against the real Ruby
# Re:VIEW running in the review-oracle:5.9 Docker container before being captured here.

$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'ReviewLATEXBuilder (M2 subset)' {
    InModuleScope PwshReview {
        BeforeAll {
            [ReviewI18n]::Setup('ja')

            function New-TestChapterTex {
                param([string]$Content, [string]$Name = 'ch01')

                $dir = Join-Path $TestDrive ([guid]::NewGuid())
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Set-Content -Path (Join-Path $dir 'catalog.yml') -Value "CHAPS:`n  - $Name.re`n"
                Set-Content -Path (Join-Path $dir 'config.yml') -Value "review_version: 5`nbookname: test`ntexcommand: uplatex`n"
                Set-Content -Path (Join-Path $dir "$Name.re") -Value $Content

                $config = [ReviewConfigure]::Create('pdfmaker', (Join-Path $dir 'config.yml'), $null)
                $book = [ReviewBookBase]::new($dir, $config)
                $builder = [ReviewLATEXBuilder]::new()
                $converter = [ReviewConverter]::new($book, $builder)
                $outPath = Join-Path $dir "$Name.tex"
                $converter.Convert("$Name.re", $outPath)
                return (Get-Content -Raw $outPath)
            }
        }

        It 'reproduces the exact LaTeX byte-for-byte verified against the real Ruby Re:VIEW oracle (review-oracle:5.9)' {
            $content = @'
= Hello World

This is a @<b>{bold} paragraph with @<code>{some code} and a footnote@<fn>{f1}.

//footnote[f1][This is the footnote text.]

 * item one
 * item two
 ** nested item

//emlist[A simple example]{
puts "hi"
//}
'@
            $result = New-TestChapterTex -Content $content
            $result | Should -Be @'
\chapter{Hello World}
\label{chap:ch01}

This is a \reviewbold{bold} paragraph with \reviewcode{some code} and a footnote\footnote{This is the footnote text.}.

\begin{itemize}
\item item one
\item item two

\begin{itemize}
\item nested item
\end{itemize}

\end{itemize}

\begin{reviewlistblock}
\reviewemlistcaption{A simple example}
\begin{reviewemlist}
puts "hi"
\end{reviewemlist}
\end{reviewlistblock}

'@
        }

        It 'renders a level-2 headline as \section with a label' {
            $result = New-TestChapterTex -Content "= Chap`n`n== A Section`n`nbody text`n"
            $result.Contains('\section{A Section}') | Should -BeTrue
            $result.Contains('\label{sec:1-1}') | Should -BeTrue
        }

        It 'escapes LaTeX metacharacters in plain text' {
            $result = New-TestChapterTex -Content "= T`n`n100%  cost & time_ok`n"
            $result.Contains('100\%') | Should -BeTrue
            $result.Contains('\&') | Should -BeTrue
            $result.Contains('\textunderscore{}') | Should -BeTrue
        }

        It 'renders strong and em inline ops' {
            $result = New-TestChapterTex -Content "= T`n`n@<strong>{important} and @<em>{emphasis}`n"
            $result.Contains('\reviewstrong{important}') | Should -BeTrue
            $result.Contains('\reviewem{emphasis}') | Should -BeTrue
        }

        It 'renders an external href with a label' {
            $result = New-TestChapterTex -Content "= T`n`nSee @<href>{http://example.com,Example}.`n"
            $result.Contains('\href{http://example.com}{Example}') | Should -BeTrue
        }

        It 'renders a bare href URL as \url' {
            $result = New-TestChapterTex -Content "= T`n`nSee @<href>{http://example.com}.`n"
            $result.Contains('\url{http://example.com}') | Should -BeTrue
        }

        It 'renders an ordered list' {
            $result = New-TestChapterTex -Content "= T`n`n 1. first`n 2. second`n"
            $result.Contains('\begin{enumerate}') | Should -BeTrue
            $result.Contains('\item first') | Should -BeTrue
            $result.Contains('\item second') | Should -BeTrue
            $result.Contains('\end{enumerate}') | Should -BeTrue
        }

        It 'renders a definition list' {
            $result = New-TestChapterTex -Content "= T`n`n : term`n    description text`n"
            $result.Contains('\begin{description}') | Should -BeTrue
            $result.Contains('\item[term]') | Should -BeTrue
            $result.Contains('\end{description}') | Should -BeTrue
        }

        It 'renders kw with and without an alternate reading' {
            $result = New-TestChapterTex -Content "= T`n`n@<kw>{GNU,GNU is Not Unix} and @<kw>{API}`n"
            $result.Contains('\reviewkw{GNU}') | Should -BeTrue
            $result.Contains('\reviewkw{API}') | Should -BeTrue
        }
    }
}
