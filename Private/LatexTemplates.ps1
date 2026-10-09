# Hand-ported equivalents of review/templates/latex/config.erb and layout.tex.erb.
#
# These are plain functions (not class methods) specifically so they can take a
# duck-typed $Maker parameter ([object], not [ReviewPdfMaker]) without creating a
# forward-reference: PdfMaker.ps1 (a class, loaded early) calls these at runtime, and
# function calls -- unlike class type-literals -- resolve at call time, not parse time,
# so these can safely live in Private/ (loaded after all Classes/*.ps1) even though
# PdfMaker.ps1 is loaded first.
#
# $Maker is expected to expose: Config [ReviewConfigure], TexCompiler, DocumentClass,
# DocumentClassOption, Authors, Okuduke, CustomOriginalTitlePage, CustomCreditPage,
# CustomProfilePage, CustomAdvFilePage, CustomBackCoverPage, CustomColophonPage,
# CoverImageOption, LocaleLatex, BoxSetting, InputFiles [hashtable], Escaper
# [ReviewLaTeXEscaper] -- all set by ReviewPdfMaker.ErbConfig() before these are called.

# Fixed to match the Re:VIEW gem version the review-oracle:5.9 Docker image (and its
# bundled review-jsbook.cls, which may read this macro) is pinned to.
$script:ReviewPortedGemVersion = '5.9.0'

function New-ReviewLatexConfigBlock {
    param([object]$Maker)

    $cfg = $Maker.Config
    $esc = { param($s) $Maker.Escaper.Escape([string]$s) }
    $sb = [System.Text.StringBuilder]::new()
    $nl = { param([string]$s) [void]$sb.Append($s).Append("`n") }

    & $nl '\makeatletter'
    & $nl "\def\review@reviewversion{$script:ReviewPortedGemVersion}"
    & $nl "\def\review@texcompiler{$($Maker.TexCompiler)}"
    & $nl "\def\review@documentclass{$($Maker.DocumentClass)}"
    & $nl ''

    foreach ($item in @('booktitle', 'subtitle')) {
        if ($cfg.Get($item)) {
            & $nl "\def\review@${item}name{$(& $esc $cfg.NameOf($item))}"
        }
    }
    & $nl ''

    $authorRoles = @('aut', 'adp', 'ann', 'arr', 'art', 'asn', 'aqt', 'aft', 'aui', 'ant', 'bkp', 'clb', 'cmm', 'csl', 'dsr', 'edt', 'ill', 'lyr', 'mdc', 'mus', 'nrt', 'oth', 'pht', 'pbl', 'prt', 'red', 'rev', 'spn', 'ths', 'trc', 'trl')
    foreach ($item in $authorRoles) {
        if ($cfg.Get($item)) {
            $joined = ($cfg.NamesOf($item) -join [ReviewI18n]::T('names_splitter'))
            & $nl "\def\review@${item}names{$(& $esc $joined)}"
        }
    }
    & $nl ''

    & $nl "\def\review@titlepageauthors{$($Maker.Authors)}"
    & $nl "\def\review@date{$(& $esc ([string]$cfg.Get('date')))}"
    & $nl ''

    foreach ($item in @('bookname', 'language', 'urnid', 'isbn')) {
        if ($cfg.Get($item)) {
            & $nl "\def\review@${item}{$(& $esc $cfg.Get($item))}"
        }
    }
    foreach ($item in @('rights', 'description', 'subject', 'type', 'format', 'source', 'relation', 'coverage')) {
        $v = $cfg.Get($item)
        if ($v) {
            $arr = @($v) | ForEach-Object { & $esc $_ }
            & $nl "\def\review@${item}{$($arr -join '\\')}"
        }
    }
    & $nl ''

    $highlight = $cfg.Get('highlight')
    if ($highlight -and $highlight['latex']) {
        & $nl "\def\review@highlightlatex{$($highlight['latex'])}"
    }
    & $nl ''

    & $nl "\def\review@intn@list{$(& $esc ([ReviewI18n]::T('list')))}"
    & $nl "\def\review@intn@columnhead{$(& $esc ([ReviewI18n]::T('column_head')))}"
    & $nl "\def\review@intn@image{$(& $esc ([ReviewI18n]::T('image')))}"
    & $nl "\def\review@intn@table{$(& $esc ([ReviewI18n]::T('table')))}"
    & $nl "\def\review@intn@equation{$(& $esc ([ReviewI18n]::T('equation')))}"
    & $nl "\def\review@intn@columnname{$(& $esc ([ReviewI18n]::T('columnname')))}"
    foreach ($mini in @('note', 'tip', 'info', 'warning', 'important', 'caution', 'notice', 'memo')) {
        & $nl "\def\review@intn@${mini}head{$(& $esc ([ReviewI18n]::T("${mini}_head")))}"
    }
    & $nl "\def\review@intn@edition{$(& $esc ([ReviewI18n]::T('edition')))}"
    $pblJoined = ($cfg.NamesOf('pbl') -join [ReviewI18n]::T('names_splitter'))
    & $nl "\def\review@intn@publishedby{$(& $esc ([ReviewI18n]::T('published_by', $pblJoined)))}"
    & $nl "\def\review@intn@captionprefix{$(& $esc ([ReviewI18n]::T('caption_prefix')))}"
    $toctitle = if ($cfg.Get('toctitle')) { $cfg.Get('toctitle') } else { [ReviewI18n]::T('toctitle') }
    & $nl "\def\review@toctitle{$(& $esc $toctitle)}"
    & $nl "\def\review@prepartname{$(& $esc $Maker.LocaleLatex['prepartname'])}"
    & $nl "\def\review@postpartname{$(& $esc $Maker.LocaleLatex['postpartname'])}"
    & $nl "\def\review@prechaptername{$(& $esc $Maker.LocaleLatex['prechaptername'])}"
    & $nl "\def\review@postchaptername{$(& $esc $Maker.LocaleLatex['postchaptername'])}"
    & $nl "\def\review@figurename{$(& $esc ([ReviewI18n]::T('image')))}"
    & $nl "\def\review@tablename{$(& $esc ([ReviewI18n]::T('table')))}"
    & $nl "\def\review@appendixname{$(& $esc $Maker.LocaleLatex['preappendixname'])}"
    & $nl ''

    if ($cfg.Get('toc')) {
        & $nl '\def\review@toc{true}'
        & $nl "\def\review@tocdepth{$([int]$cfg.Get('toclevel') - 1)}"
    }
    if ($cfg.Get('makeindex')) {
        & $nl '\def\review@makeindex{true}'
    }
    if ($cfg.Get('cover')) {
        $coverPath = [System.IO.Path]::Combine($Maker.BaseDir, [string]$cfg.Get('cover'))
        & $nl "\def\review@coverfile{$(Get-Content -LiteralPath $coverPath -Raw)}"
    }
    elseif ($cfg.Get('coverimage')) {
        & $nl "\def\review@coverimage{./$($cfg.Get('imagedir'))/$($cfg.Get('coverimage'))}"
        & $nl "\def\review@coverimageoption{$($Maker.CoverImageOption)}"
    }
    $pdfmakerCfg = $cfg.Get('pdfmaker')
    if ($pdfmakerCfg -and $pdfmakerCfg['use_cover_nombre']) {
        & $nl '\def\review@usecovernombre{true}'
    }
    if ($cfg.Get('titlepage')) {
        & $nl '\def\review@titlepage{true}'
        if ($cfg.Get('titlefile')) {
            $titleFilePath = [System.IO.Path]::Combine($Maker.BaseDir, [string]$cfg.Get('titlefile'))
            & $nl "\def\review@titlefile{$(Get-Content -LiteralPath $titleFilePath -Raw)}"
        }
    }
    if ($Maker.CustomOriginalTitlePage) { & $nl "\def\revieworiginaltitlepagecont{$($Maker.CustomOriginalTitlePage)}" }
    if ($Maker.CustomCreditPage) { & $nl "\def\reviewcreditfilecont{$($Maker.CustomCreditPage)}" }
    if ($Maker.CustomProfilePage) { & $nl "\def\reviewprofilepagecont{$($Maker.CustomProfilePage)}" }
    if ($Maker.CustomAdvFilePage) { & $nl "\def\reviewadvfilepagecont{$($Maker.CustomAdvFilePage)}" }
    if ($Maker.CustomBackCoverPage) { & $nl "\def\reviewbackcovercont{$($Maker.CustomBackCoverPage)}" }
    & $nl ''

    if ($cfg.Get('colophon')) {
        & $nl '\def\review@colophon{true}'
        if ($Maker.CustomColophonPage) { & $nl "\def\review@colophonfile{$($Maker.CustomColophonPage)}" }
    }
    $pubHistories = ([string]$cfg.Get('pubhistory')) -replace "`n", "`n`n\noindent`n"
    & $nl "\def\review@pubhistories{$pubHistories}"
    & $nl "\def\review@colophonnames{$($Maker.Okuduke)}"
    & $nl ''

    & $nl "\def\reviewprefacefiles{$($Maker.InputFiles['PREDEF'])}"
    & $nl "\def\reviewchapterfiles{$($Maker.InputFiles['CHAPS'])}"
    & $nl "\def\reviewappendixfiles{$($Maker.InputFiles['APPENDIX'])}"
    & $nl "\def\reviewpostdeffiles{$($Maker.InputFiles['POSTDEF'])}"
    if ($cfg.Get('use_part')) { & $nl '\def\reviewusepart{true}' }
    if ($pdfmakerCfg -and $pdfmakerCfg['bbox']) { & $nl "\def\review@bbox{$($pdfmakerCfg['bbox'])}" }
    if ($Maker.BoxSetting) {
        & $nl '\newcommand{\reviewboxsetting}{%'
        & $nl "$($Maker.BoxSetting)%"
        & $nl '}'
    }
    & $nl ''

    & $nl '\def\reviewbackcompatibilityhook{'
    & $nl '  \ifdefined\reviewimagecaption\else% for 3.0.0 compatibility'
    & $nl "    \newcommand{\reviewimagecaption}[1]{\caption{##1}}"
    & $nl '  \fi'
    & $nl '  \ifdefined\reviewincludegraphics\else% for 3.2.0 compatibility'
    & $nl "    \DeclareRobustCommand{\reviewincludegraphics}[2][]{%"
    & $nl '      \includegraphics[##1]{##2}}'
    & $nl '  \fi'
    & $nl '  \ifdefined\covermatter\else% for 4.0.0 compatibility'
    & $nl '    \def\covermatter{}'
    & $nl '  \fi'
    & $nl '  \ifdefined\reviewchapref\else% for 5.1.0 compatibility'
    & $nl "    \newcommand{\reviewchapref}[2]{\hyperref[##2]{##1}}"
    & $nl '  \fi'
    & $nl '  \ifdefined\reviewtcy\else% for 5.3.0 compatibility'
    & $nl "    \DeclareRobustCommand{\reviewtcy}[1]{\rensuji{##1}}"
    & $nl '  \fi'
    & $nl '  \ifdefined\reviewicon\else% for 5.6.0 compatibility'
    & $nl "    \DeclareRobustCommand{\reviewicon}[1]{\reviewincludegraphics{##1}}"
    & $nl '  \fi'
    & $nl '}'
    & $nl ''
    & $nl '\makeatother'

    return $sb.ToString()
}

function New-ReviewLatexLayout {
    param([object]$Maker, [string]$ConfigBlock)

    $cfg = $Maker.Config
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("\documentclass[$($Maker.DocumentClassOption)]{$($Maker.DocumentClass)}`n")
    [void]$sb.Append($ConfigBlock).Append("`n")

    $texStyle = $cfg.Get('texstyle')
    if ($texStyle) {
        foreach ($x in @($texStyle)) {
            [void]$sb.Append("\usepackage{$x}`n")
        }
    }

    [void]$sb.Append(@"

%% backward compatibility (defined in config.erb)
\reviewbackcompatibilityhook

\begin{document}

%% begindocument hook
\ifdefined\reviewbegindocumenthook
\reviewbegindocumenthook
\fi

%% coverpage
\ifdefined\reviewcoverpagecont
\covermatter
\reviewcoverpagecont
\fi

%% frontmatter hook
\ifdefined\reviewfrontmatterhook
\reviewfrontmatterhook
\fi

%% title page
\ifdefined\reviewtitlepagecont
\reviewtitlepagecont
\fi

%% originaltitle
\ifdefined\revieworiginaltitlepagecont
\revieworiginaltitlepagecont
\fi

%% credit
\ifdefined\reviewcreditfilecont
\reviewcreditfilecont
\fi

%% preface
\ifdefined\reviewprefacefiles
\reviewprefacefiles
\fi

%% toc
\ifdefined\reviewtableofcontents
\reviewtableofcontents
\fi

%% mainmatter hook
\ifdefined\reviewmainmatterhook
\reviewmainmatterhook
\fi

%% chapters body
\ifdefined\reviewchapterfiles
\reviewchapterfiles
\fi

%% appendix hook
\ifdefined\reviewappendixhook
\reviewappendixhook
\fi

%% appendix body
\ifdefined\reviewappendixfiles
\reviewappendixfiles
\fi

%% backmatter hook
\ifdefined\reviewbackmatterhook
\reviewbackmatterhook
\fi

%% postdef body
\ifdefined\reviewpostdeffiles
\reviewpostdeffiles
\fi

%% index page
\ifdefined\reviewprintindex
\reviewprintindex
\fi

%% profile page
\ifdefined\reviewprofilepagecont
\reviewprofilepagecont
\fi

%% advfile page
\ifdefined\reviewadvfilepagecont
\reviewadvfilepagecont
\fi

%%% colophon page
\ifdefined\reviewcolophonpagecont
\reviewcolophonpagecont
\fi

%%% backcover page
\ifdefined\reviewbackcovercont
\reviewbackcovercont
\fi

%% enddocument hook
\ifdefined\reviewenddocumenthook
\reviewenddocumenthook
\fi

\end{document}
"@)
    # PowerShell here-strings consume the final newline immediately before the closing
    # "@ marker, unlike the source .erb file (which has a real trailing newline) --
    # restore it explicitly to match.
    [void]$sb.Append("`n")

    return $sb.ToString()
}
