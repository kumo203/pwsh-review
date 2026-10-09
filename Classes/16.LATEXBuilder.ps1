# Port of review/lib/review/latexbuilder.rb -- the pass-2 LaTeX builder (v1's only real
# output target). M2 scope: headlines (+nonum/notoc/nodisp/column tagged sections),
# paragraphs, ul/ol/dl, emlist/emlistnum/list/listnum/source/cmd/read/lead, footnote +
# inline_fn/inline_endnote, and the inline formatting ops (b/code/tt/tti/ttb/em/strong/
# i/u/sub/sup/ins/del/ami/bou/href/kw/ruby/br). table/image/bibpaper/graph/texequation
# are deferred to M5 (see README non-goals) -- simply not defined here, so Compiler's
# "does not support command" graceful error path covers them in the meantime.

class ReviewLATEXBuilder : ReviewBuilder {
    hidden [ReviewLaTeXEscaper] $Escaper
    hidden [bool] $BlankNeeded = $false
    hidden [hashtable] $FootText
    hidden [Nullable[int]] $OlNumValue = $null
    hidden [string] $LatexTSizeValue = $null
    hidden [object[]] $CellWidth = $null
    hidden [hashtable] $IndexDb = @{}
    hidden [string] $TexCompilerName

    static [hashtable] $HeadlineNames = @{
        1 = 'chapter'; 2 = 'section'; 3 = 'subsection'; 4 = 'subsubsection'; 5 = 'paragraph'; 6 = 'subparagraph'
    }

    ReviewLATEXBuilder() : base($false) {}

    [string] extname() { return '.tex' }

    [void] builder_init_file() {
        ([ReviewBuilder]$this).builder_init_file()
        $this.BlankNeeded = $false
        $this.FootText = @{}
        $this.OlNumValue = $null
        $this.LatexTSizeValue = $null
        $this.TSizeValue = $null
        $this.CellWidth = $null
        $this.FirstLineNumValue = $null
        $this.setup_index()
        $this.TexCompilerName = [System.IO.Path]::GetFileNameWithoutExtension([string]$this.Book.Config.Get('texcommand'))
        $this.Escaper = [ReviewLaTeXEscaper]::new([string]$this.Book.Config.Get('texcommand'))
    }

    # Mirrors setup_index/load_idxdb. MeCab-based yomi generation (makeindex_mecab) is a
    # documented non-goal: non-ASCII index terms without a dictionary entry fall back
    # to the same "no MeCab available" branch Ruby itself takes when MeCab isn't
    # installed.
    hidden [void] setup_index() {
        # Ordinal (case-sensitive) like a Ruby Hash -- a plain @{} is case-INsensitive.
        $this.IndexDb = [hashtable]::new([System.StringComparer]::Ordinal)
        $pdfCfg = $this.Book.Config.Get('pdfmaker')
        if (-not ($pdfCfg -and $pdfCfg['makeindex'])) { return }
        $dic = $pdfCfg['makeindex_dic']
        if (-not $dic) { return }
        $dicPath = Join-Path $this.Book.BaseDir $dic
        if (-not (Test-Path -LiteralPath $dicPath -PathType Leaf)) { return }
        foreach ($line in Get-Content -LiteralPath $dicPath -Encoding utf8) {
            $parts = [regex]::Split($line.Trim(), '\t+', 2)
            if ($parts.Count -ge 1 -and $parts[0]) {
                $this.IndexDb[$parts[0]] = $(if ($parts.Count -gt 1) { $parts[1] } else { $null })
            }
        }
    }

    hidden [void] blank() { $this.BlankNeeded = $true }

    [void] print([string]$S) {
        if ($this.BlankNeeded) { [void]$this.Output.Append("`n"); $this.BlankNeeded = $false }
        ([ReviewBuilder]$this).print($S)
    }

    [void] puts([string]$S) {
        if ($this.BlankNeeded) { [void]$this.Output.Append("`n"); $this.BlankNeeded = $false }
        ([ReviewBuilder]$this).puts($S)
    }

    [void] puts() {
        if ($this.BlankNeeded) { [void]$this.Output.Append("`n"); $this.BlankNeeded = $false }
        ([ReviewBuilder]$this).puts()
    }

    [string] result() {
        $this.check_printendnotes()
        if ($this.Chapter.IsPart() -and -not $this.Book.Config.CheckVersion('2', $false)) {
            $this.puts('\end{reviewpart}')
        }
        return $this.solve_nest($this.Output.ToString())
    }

    # Literal port of Ruby's sentinel-character nested-list string-surgery (see
    # review/lib/review/latexbuilder.rb#solve_nest) -- deliberately NOT restructured into
    # something cleaner, since golden-diffing (M5+) needs byte-level .tex parity with the
    # Ruby oracle, and a structurally different-but-equivalent emission would still fail
    # that diff.
    [string] solve_nest([string]$S) {
        $this.check_nest()
        $r = $S
        $r = $r.Replace("\end{description}`n`n`u{1}→dl←`u{1}`n", "`n")
        $r = $r.Replace("`u{1}→/dl←`u{1}", "\end{description}←END`u{1}")
        $r = $r.Replace("\end{itemize}`n`n`u{1}→ul←`u{1}`n", "`n")
        $r = $r.Replace("`u{1}→/ul←`u{1}", "\end{itemize}←END`u{1}")
        $r = $r.Replace("\end{enumerate}`n`n`u{1}→ol←`u{1}`n", "`n")
        $r = $r.Replace("`u{1}→/ol←`u{1}", "\end{enumerate}←END`u{1}")
        $r = $r.Replace("\end{description}←END`u{1}`n`n\begin{description}", '')
        $r = $r.Replace("\end{itemize}←END`u{1}`n`n\begin{itemize}", '')
        $r = $r.Replace("\end{enumerate}←END`u{1}`n`n\begin{enumerate}", '')
        $r = $r.Replace("←END`u{1}", '')
        return $r
    }

    [string] macro([string]$Name, [string[]]$MacroArgs) { return $this.Escaper.Macro($Name, $MacroArgs) }
    [string] escape([string]$Str) { return $this.Escaper.Escape($Str) }
    [string] unescape([string]$Str) { return $this.Escaper.Unescape($Str) }
    [string] escape_url([string]$Str) { return $this.Escaper.EscapeUrl($Str) }

    hidden [string] chapter_label() { return "chap:$($this.Chapter.Id())" }
    hidden [string] sec_label([string]$Anchor) { return "sec:$Anchor" }
    hidden [string] image_label([string]$Id, [object]$ChapterArg) {
        $targetChapter = if ($ChapterArg) { $ChapterArg } else { $this.Chapter }
        return "image:$($targetChapter.Id()):$Id"
    }

    hidden [string] table_label([string]$Id, [object]$ChapterArg) {
        $targetChapter = if ($ChapterArg) { $ChapterArg } else { $this.Chapter }
        return "table:$($targetChapter.Id()):$Id"
    }

    hidden [string] column_label([string]$Id, [object]$ChapterArg) {
        $chapter = if ($ChapterArg) { $ChapterArg } else { $this.Chapter }
        return "column:$($chapter.Id()):$($chapter.GetColumn($Id).Number)"
    }

    [void] headline([int]$Level, [object]$Label, [string]$Caption) {
        try {
            $prefixAnchor = $this.headline_prefix($Level)
            $anchor = $prefixAnchor[1]
            $headlineName = [ReviewLATEXBuilder]::HeadlineNames[$Level]
            if ($this.Chapter.IsPart()) {
                if ($this.Book.Config.CheckVersion('2', $false)) {
                    $headlineName = 'part'
                }
                elseif ($Level -eq 1) {
                    $headlineName = 'part'
                    $this.puts('\begin{reviewpart}')
                }
            }
            $prefix = ''
            $chapNumStr = "$($this.Chapter.Number)"
            if ($Level -gt [int]$this.Book.Config.Get('secnolevel') -or ($chapNumStr.Length -eq 0 -and $Level -gt 1)) {
                $prefix = '*'
            }
            if ($this.Output.Length -ne 0) { $this.blank() }
            $this.doc_status.caption = $true
            $this.puts($this.macro($headlineName + $prefix, @($this.compile_inline($Caption))))
            $this.doc_status.caption = $null
            if ($prefix -eq '*' -and $Level -le [int]$this.Book.Config.Get('toclevel')) {
                $this.puts("\addcontentsline{toc}{$headlineName}{$($this.compile_inline($Caption))}")
            }
            if ($Level -eq 1) {
                $this.puts($this.macro('label', @($this.chapter_label())))
            }
            else {
                $this.puts($this.macro('label', @($this.sec_label($anchor))))
                if ($Label) { $this.puts($this.macro('label', @($Label))) }
            }
        }
        catch {
            throw [ReviewApplicationError]::new("unknown level: $Level")
        }
    }

    [void] nonum_begin([int]$Level, [object]$Label, [string]$Caption) {
        if ($this.Output.Length -ne 0) { $this.blank() }
        $this.doc_status.caption = $true
        $this.puts($this.macro([ReviewLATEXBuilder]::HeadlineNames[$Level] + '*', @($this.compile_inline($Caption))))
        $this.doc_status.caption = $null
        $this.puts($this.macro('addcontentsline', @('toc', [ReviewLATEXBuilder]::HeadlineNames[$Level], $this.compile_inline($Caption))))
    }
    [void] nonum_end([int]$Level) {}

    [void] notoc_begin([int]$Level, [object]$Label, [string]$Caption) {
        if ($this.Output.Length -ne 0) { $this.blank() }
        $this.doc_status.caption = $true
        $this.puts($this.macro([ReviewLATEXBuilder]::HeadlineNames[$Level] + '*', @($this.compile_inline($Caption))))
        $this.doc_status.caption = $null
    }
    [void] notoc_end([int]$Level) {}

    [void] nodisp_begin([int]$Level, [object]$Label, [string]$Caption) {
        if ($this.Output.Length -eq 0) { $this.puts($this.macro('clearpage', @())) } else { $this.blank() }
        $this.puts($this.macro('addcontentsline', @('toc', [ReviewLATEXBuilder]::HeadlineNames[$Level], $this.compile_inline($Caption))))
    }
    [void] nodisp_end([int]$Level) {}

    [void] column_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.blank()
        $this.doc_status.column = $true
        $target = if ($Label) { "\hypertarget{$($this.column_label($Label, $null))}{}" } else { "\hypertarget{$($this.column_label($Caption, $null))}{}" }
        $this.doc_status.caption = $true
        if ($this.Book.Config.CheckVersion('2', $false)) {
            $this.puts('\begin{reviewcolumn}')
            $this.puts($target)
            $this.puts($this.macro('reviewcolumnhead', @($null, $this.compile_inline($Caption))))
        }
        else {
            $this.print('\begin{reviewcolumn}')
            $this.puts("[$($this.compile_inline($Caption))$target]")
        }
        $this.doc_status.caption = $null
        if ($Level -le [int]$this.Book.Config.Get('toclevel')) {
            $this.puts("\addcontentsline{toc}{$([ReviewLATEXBuilder]::HeadlineNames[$Level])}{$($this.compile_inline($Caption))}")
        }
    }

    [void] column_end([int]$Level) {
        $this.puts('\end{reviewcolumn}')
        $this.blank()
        $this.doc_status.column = $null
    }

    [void] common_block_begin([string]$Type, [object]$Caption) {
        $this.check_nested_minicolumn()
        $effectiveType = if ($this.Book.Config.CheckVersion('2', $false)) { 'minicolumn' } else { $Type }
        $this.doc_status.minicolumn = $effectiveType
        $this.print("\begin{review$effectiveType}")
        $this.doc_status.caption = $true
        if ($this.Book.Config.CheckVersion('2', $false)) {
            $this.puts()
            if ($Caption) { $this.puts("\reviewminicolumntitle{$($this.compile_inline($Caption))}") }
        }
        else {
            if ($Caption) { $this.print("[$($this.compile_inline($Caption))]") }
            $this.puts()
        }
        $this.doc_status.caption = $null
    }

    [void] common_block_end([string]$Type) {
        $effectiveType = if ($this.Book.Config.CheckVersion('2', $false)) { 'minicolumn' } else { $Type }
        $this.puts("\end{review$effectiveType}")
        $this.doc_status.minicolumn = $null
    }

    [void] ul_begin() { $this.blank(); $this.puts('\begin{itemize}') }

    [void] ul_item([string[]]$Lines) {
        $str = $this.join_lines_to_paragraph($Lines)
        if (-not $this.Book.Config.Get('join_lines_by_lang')) {
            $str = ($Lines | ForEach-Object { $_.TrimEnd("`r", "`n") }) -join "`n"
        }
        $str = $str -replace '^\[', '\lbrack{}'
        $this.puts('\item ' + $str)
    }

    [void] ul_end() { $this.puts('\end{itemize}'); $this.blank() }

    [void] ol_begin() {
        $this.blank()
        $this.puts('\begin{enumerate}')
        if ($null -eq $this.OlNumValue) { return }
        $this.puts("\setcounter{enumi}{$($this.OlNumValue - 1)}")
        $this.OlNumValue = $null
    }

    [void] olnum([string[]]$ArgList) { $this.OlNumValue = [int]$ArgList[0] }
    [void] ol_item([string[]]$Lines, [string]$Num) {
        $str = $this.join_lines_to_paragraph($Lines)
        if (-not $this.Book.Config.Get('join_lines_by_lang')) {
            $str = ($Lines | ForEach-Object { $_.TrimEnd("`r", "`n") }) -join "`n"
        }
        $str = $str -replace '^\[', '\lbrack{}'
        $this.puts('\item ' + $str)
    }
    [void] ol_end() { $this.puts('\end{enumerate}'); $this.blank() }

    [void] dl_begin() { $this.blank(); $this.puts('\begin{description}') }
    [void] dt([string]$Str) {
        $s = $Str.Replace('[', '\lbrack{}').Replace(']', '\rbrack{}')
        $this.puts('\item[' + $s + '] \mbox{} \\')
    }
    [void] dd([string[]]$Lines) {
        if ($this.Book.Config.Get('join_lines_by_lang')) {
            $this.puts($this.join_lines_to_paragraph($Lines))
        }
        else {
            $this.puts(($Lines | ForEach-Object { $_.TrimEnd("`r", "`n") }) -join "`n")
        }
    }
    [void] dl_end() { $this.puts('\end{description}'); $this.blank() }

    [void] paragraph([string[]]$Lines) {
        $this.blank()
        if ($this.Book.Config.Get('join_lines_by_lang')) {
            $this.puts($this.join_lines_to_paragraph($Lines))
        }
        else {
            foreach ($line in $Lines) { $this.puts($line) }
        }
        $this.blank()
    }

    [void] parasep() { $this.puts('\parasep') }

    hidden [void] latex_block([string]$Type, [string[]]$Lines) {
        $this.blank()
        $this.puts($this.macro('begin', @($Type)))
        $blocked = $this.split_paragraph($Lines)
        $this.puts(($blocked -join "`n`n"))
        $this.puts($this.macro('end', @($Type)))
        $this.blank()
    }

    [void] read([string[]]$Lines) { $this.latex_block('quotation', $Lines) }
    [void] lead([string[]]$Lines) { $this.latex_block('quotation', $Lines) }
    [void] quote([string[]]$Lines) { $this.latex_block('quote', $Lines) }
    [void] centering([string[]]$Lines) { $this.latex_block('center', $Lines) }
    [void] flushright([string[]]$Lines) { $this.latex_block('flushright', $Lines) }

    [bool] highlight() {
        $h = $this.Book.Config.Get('highlight')
        return [bool]($h -and $h['latex'])
    }

    hidden [string] code_line([string]$Line) { return $this.detab($Line) + "`n" }
    hidden [string] code_line_num([string]$Line, [int]$FirstLineNum, [int]$Idx) {
        return $this.detab(("$($Idx + $FirstLineNum)".PadLeft(2) + ': ' + $Line)) + "`n"
    }

    [void] emlist([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $this.blank()
        $this.common_code_block($null, $Lines, 'reviewemlist', $caption, { param($line, $idx) $this.code_line($line) })
    }

    [void] emlistnum([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $this.blank()
        $firstLineNum = $this.line_num()
        $this.common_code_block($null, $Lines, 'reviewemlist', $caption, { param($line, $idx) $this.code_line_num($line, $firstLineNum, $idx) })
    }

    [void] list([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.common_code_block($id, $Lines, 'reviewlist', $caption, { param($line, $idx) $this.code_line($line) })
    }

    [void] listnum([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $firstLineNum = $this.line_num()
        $this.common_code_block($id, $Lines, 'reviewlist', $caption, { param($line, $idx) $this.code_line_num($line, $firstLineNum, $idx) })
    }

    [void] cmd([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $this.blank()
        $this.common_code_block($null, $Lines, 'reviewcmd', $caption, { param($line, $idx) $this.code_line($line) })
    }

    [void] source([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $this.common_code_block($null, $Lines, 'reviewsource', $caption, { param($line, $idx) $this.code_line($line) })
    }

    hidden [void] common_code_block([object]$Id, [string[]]$Lines, [string]$Command, [object]$Caption, [scriptblock]$LineRenderer) {
        $this.doc_status.caption = $true
        $captionStr = $null
        if (-not $this.Book.Config.CheckVersion('2', $false)) {
            $this.puts('\begin{reviewlistblock}')
        }
        if ($Caption) {
            if ($Command -match 'emlist' -or $Command -match 'cmd' -or $Command -match 'source') {
                $captionStr = $this.macro($Command + 'caption', @($this.compile_inline($Caption)))
            }
            else {
                try {
                    $listItem = $this.Chapter.GetList($Id)
                    $chap = $this.get_chap($null)
                    if ($null -eq $chap) {
                        $captionStr = $this.macro('reviewlistcaption', @("$([ReviewI18n]::T('list'))$([ReviewI18n]::T('format_number_header_without_chapter', @($listItem.Number)))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($Caption))"))
                    }
                    else {
                        $captionStr = $this.macro('reviewlistcaption', @("$([ReviewI18n]::T('list'))$([ReviewI18n]::T('format_number_header', @($chap, $listItem.Number)))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($Caption))"))
                    }
                }
                catch [ReviewKeyError] {
                    throw [ReviewApplicationError]::new("no such list: $Id")
                }
            }
        }
        $this.doc_status.caption = $null

        if ($this.caption_top('list') -and $captionStr) { $this.puts($captionStr) }

        $body = [System.Text.StringBuilder]::new()
        for ($idx = 0; $idx -lt $Lines.Count; $idx++) {
            [void]$body.Append((& $LineRenderer $Lines[$idx] $idx))
        }
        $this.puts($this.macro('begin', @($Command)))
        $this.print($body.ToString())
        $this.puts($this.macro('end', @($Command)))

        if (-not $this.caption_top('list') -and $captionStr) { $this.puts($captionStr) }

        if (-not $this.Book.Config.CheckVersion('2', $false)) {
            $this.puts('\end{reviewlistblock}')
        }
        $this.blank()
    }

    [void] footnote([string[]]$ArgList) {
        $id = $ArgList[0]; $content = $ArgList[1]
        if ($this.Book.Config.Get('footnotetext') -or $this.FootText.ContainsKey($id)) {
            if ($this.doc_status.column) {
                Write-Warning "//footnote[$id] is in the column block. It is recommended to move out of the column block."
            }
            $num = $this.Chapter.GetFootnote($id).Number
            $this.puts($this.macro("footnotetext[$num]", @($this.compile_inline($content.Trim()))))
        }
    }

    [string] inline_fn([string]$Id) {
        try {
            if ($this.Book.Config.Get('footnotetext')) {
                return $this.macro("footnotemark[$($this.Chapter.GetFootnote($Id).Number)]", @(''))
            }
            elseif ($this.doc_status.caption -or $this.doc_status.table -or $this.doc_status.column -or $this.doc_status.dt) {
                $this.FootText[$Id] = $this.Chapter.GetFootnote($Id).Number
                return $this.macro('protect\footnotemark', @(''))
            }
            else {
                return $this.macro('footnote', @($this.compile_inline($this.Chapter.GetFootnote($Id).Content().Trim())))
            }
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown footnote: $Id")
        }
    }

    [string] inline_endnote([string]$Id) {
        try {
            return $this.macro('endnote', @($this.compile_inline($this.Chapter.GetEndnote($Id).Content().Trim())))
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown footnote: $Id")
        }
    }

    [void] printendnotes() {
        $this.ShownEndnotes = $true
        $this.blank()
        $this.puts('\theendnotes')
        $this.blank()
    }

    [string] inline_bou([string]$Str) { return $this.macro('reviewbou', @($this.escape($Str))) }

    [string] compile_ruby([object]$Base, [object]$Ruby) {
        return $this.macro('ruby', @($this.escape($Base), $this.escape($Ruby).Replace('\textbar{}', '|')))
    }

    [string] inline_m([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return " `$$Str`$ " }
        return "`$$Str`$"
    }

    [string] inline_i([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return $this.macro('textit', @($this.escape($Str))) }
        return $this.macro('reviewit', @($this.escape($Str)))
    }

    [string] inline_idx([string]$Str) { return $this.escape($Str) + $this.index($Str) }
    [string] inline_hidx([string]$Str) { return $this.index($Str) }
    [string] inline_hi([string]$Str) { return $this.index($Str) }

    # Mirrors LATEXBuilder#index (mendex/upmendex specific). See setup_index for the
    # MeCab non-goal: items not in the dictionary always take the "no MeCab" branch.
    [string] index([string]$Str) {
        $items = $Str -split '<<>>'
        $converted = foreach ($item in $items) {
            if ($this.IndexDb.ContainsKey($item)) {
                $this.Escaper.EscapeMendexKey($this.Escaper.EscapeIndex($this.IndexDb[$item])) + '@' +
                    $this.Escaper.EscapeMendexDisplay($this.Escaper.EscapeIndex($this.escape($item)))
            }
            else {
                $escItem = $this.Escaper.EscapeMendexDisplay($this.Escaper.EscapeIndex($this.escape($item)))
                if ($escItem -ceq $item) { $escItem }
                else { "$($this.Escaper.EscapeMendexKey($this.Escaper.EscapeIndex($item)))@$escItem" }
            }
        }
        return "\index{$(@($converted) -join '!')}"
    }

    [string] inline_b([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return $this.macro('textbf', @($this.escape($Str))) }
        return $this.macro('reviewbold', @($this.escape($Str)))
    }

    [string] inline_br([string]$Str) { return "\\`n" }
    [string] inline_dtp([string]$Str) { return '' }

    [string] inline_code([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return $this.macro('texttt', @($this.escape($Str))) }
        return $this.macro('reviewcode', @($this.escape($Str)))
    }

    [string] nofunc_text([string]$Str) { return $this.escape($Str) }

    [string] inline_tt([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return $this.macro('texttt', @($this.escape($Str))) }
        return $this.macro('reviewtt', @($this.escape($Str)))
    }

    [string] inline_ins([string]$Str) { return $this.macro('reviewinsert', @($this.escape($Str))) }
    [string] inline_del([string]$Str) { return $this.macro('reviewstrike', @($this.escape($Str))) }

    [string] inline_tti([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return $this.macro('texttt', @($this.macro('textit', @($this.escape($Str))))) }
        return $this.macro('reviewtti', @($this.escape($Str)))
    }

    [string] inline_ttb([string]$Str) {
        if ($this.Book.Config.CheckVersion('2', $false)) { return $this.macro('texttt', @($this.macro('textbf', @($this.escape($Str))))) }
        return $this.macro('reviewttb', @($this.escape($Str)))
    }

    [string] compile_kw([string]$Word, [object]$Alt) {
        if ($Alt) { return $this.macro('reviewkw', @($this.escape($Word))) + "（$($this.escape($Alt.Trim()))）" }
        return $this.macro('reviewkw', @($this.escape($Word)))
    }

    # Matches Re:VIEW 5.9.0 (the review-oracle's version): no '#anchor' internal-link
    # branch -- that was added after 5.9.0, and an earlier port of the newer source
    # emitted \hyperref[...] where the oracle emits \ref{#...}.
    [string] compile_href([string]$Url, [object]$Label) {
        if ($Url -match '^[a-z]+:') {
            if ($Label) { return $this.macro('href', @($this.escape_url($Url), $this.escape($Label))) }
            return $this.macro('url', @($this.escape_url($Url)))
        }
        else {
            return $this.macro('ref', @($Url))
        }
    }

    [string] inline_sub([string]$Str) { return $this.macro('textsubscript', @($this.escape($Str))) }
    [string] inline_sup([string]$Str) { return $this.macro('textsuperscript', @($this.escape($Str))) }
    [string] inline_em([string]$Str) { return $this.macro('reviewem', @($this.escape($Str))) }
    [string] inline_strong([string]$Str) { return $this.macro('reviewstrong', @($this.escape($Str))) }
    [string] inline_u([string]$Str) { return $this.macro('reviewunderline', @($this.escape($Str))) }
    [string] inline_ami([string]$Str) { return $this.macro('reviewami', @($this.escape($Str))) }

    # Overrides of Builder's generic inline_list/inline_table/inline_img/inline_eq
    # (14.Builder.ps1): LaTeX wraps the cross-reference in a \review*ref{} macro (for
    # TeX-native \ref/\label wiring) instead of the generic "リスト2.1"-style plain text
    # those base versions produce -- confirmed against the real Ruby Re:VIEW oracle,
    # which emits \reviewlistref{2.1} for @<list>{otherchapter|id}, not the base
    # class's plain-text rendering.
    [string] inline_list([string]$Id) {
        $resolved = $this.extract_chapter_id($Id)
        $targetChapter = $resolved[0]; $itemId = $resolved[1]
        try {
            $num = $targetChapter.GetList($itemId).Number
            $chap = $this.get_chap($targetChapter)
            if ($null -eq $chap) {
                return $this.macro('reviewlistref', @([ReviewI18n]::T('format_number_without_chapter', @($num))))
            }
            return $this.macro('reviewlistref', @([ReviewI18n]::T('format_number', @($chap, $num))))
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown list: $Id")
        }
    }

    [string] inline_table([string]$Id) {
        $resolved = $this.extract_chapter_id($Id)
        $targetChapter = $resolved[0]; $itemId = $resolved[1]
        try {
            $num = $targetChapter.GetTable($itemId).Number
            $chap = $this.get_chap($targetChapter)
            $label = $this.table_label($itemId, $targetChapter)
            if ($null -eq $chap) {
                return $this.macro('reviewtableref', @([ReviewI18n]::T('format_number_without_chapter', @($num)), $label))
            }
            return $this.macro('reviewtableref', @([ReviewI18n]::T('format_number', @($chap, $num)), $label))
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown table: $Id")
        }
    }

    [string] inline_img([string]$Id) {
        $resolved = $this.extract_chapter_id($Id)
        $targetChapter = $resolved[0]; $itemId = $resolved[1]
        try {
            $num = $targetChapter.GetImage($itemId).Number
            $chap = $this.get_chap($targetChapter)
            $label = $this.image_label($itemId, $targetChapter)
            if ($null -eq $chap) {
                return $this.macro('reviewimageref', @([ReviewI18n]::T('format_number_without_chapter', @($num)), $label))
            }
            return $this.macro('reviewimageref', @([ReviewI18n]::T('format_number', @($chap, $num)), $label))
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown image: $Id")
        }
    }

    [string] inline_eq([string]$Id) {
        $resolved = $this.extract_chapter_id($Id)
        $targetChapter = $resolved[0]; $itemId = $resolved[1]
        try {
            $num = $targetChapter.GetEquation($itemId).Number
            $chap = $this.get_chap($targetChapter)
            if ($null -eq $chap) {
                return $this.macro('reviewequationref', @([ReviewI18n]::T('format_number_without_chapter', @($num))))
            }
            return $this.macro('reviewequationref', @([ReviewI18n]::T('format_number', @($chap, $num))))
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown equation: $Id")
        }
    }

    # ---------------------------------------------------------------------------------
    # M5: chapter-reference link wrapping, misc inline ops
    # ---------------------------------------------------------------------------------

    [string] inline_chapref([string]$Id) {
        $title = ([ReviewBuilder]$this).inline_chapref($Id)
        if ($this.Book.Config.Get('chapterlink')) { return "\reviewchapref{$title}{chap:$Id}" }
        return $title
    }

    [string] inline_chap([string]$Id) {
        $num = ([ReviewBuilder]$this).inline_chap($Id)
        if ($this.Book.Config.Get('chapterlink')) { return "\reviewchapref{$num}{chap:$Id}" }
        return $num
    }

    [string] inline_title([string]$Id) {
        $title = ([ReviewBuilder]$this).inline_title($Id)
        if ($this.Book.Config.Get('chapterlink')) { return "\reviewchapref{$title}{chap:$Id}" }
        return $title
    }

    [string] inline_pageref([string]$Id) { return "\pageref{$Id}" }

    [string] inline_icon([string]$Id) {
        $p = $this.Chapter.GetImage($Id).Path()
        if ($p) {
            $cmd = if ($this.Book.Config.CheckVersion('2', $false)) { 'includegraphics' } else { 'reviewicon' }
            return $this.macro($cmd, @($p))
        }
        Write-Warning "image not bound: $Id"
        return "\verb|--[[path = $Id ($($this.existence($Id)))]]--|"
    }

    # Ruby checks `@texcompiler.start_with?('platex')` here, but LATEXBuilder never
    # assigns @texcompiler (only PDFMaker does, on a different object), so Ruby always
    # takes the passthrough branch. Mirrored faithfully rather than "fixed".
    [string] inline_uchar([string]$Str) {
        return [char]::ConvertFromUtf32([Convert]::ToInt32($Str, 16))
    }

    [string] inline_comment([string]$Str) {
        if ($this.Book.Config.Get('draft')) { return $this.macro('pdfcomment', @($this.escape($Str))) }
        return ''
    }

    [string] inline_tcy([string]$Str) { return $this.macro('reviewtcy', @($this.escape($Str))) }
    [string] inline_balloon([string]$Str) { return $this.macro('reviewballoon', @($this.escape($Str))) }

    [string] inline_bib([string]$Id) {
        return $this.macro('reviewbibref', @("[$($this.Chapter.GetBibpaper($Id).Number)]", "bib:$Id"))
    }

    [string] inline_hd_chap([object]$Chap, [string]$Id) {
        $n = $Chap.HeadlineIndex.NumberOf($Id)
        $caption = $this.compile_inline([string]$Chap.GetHeadline($Id).Content())
        $str = if ($n -and $null -ne $Chap.Number -and $this.over_secnolevel($n)) {
            [ReviewI18n]::T('hd_quote', @($n, $caption))
        }
        else {
            [ReviewI18n]::T('hd_quote_without_number', $caption)
        }
        if ($this.Book.Config.Get('chapterlink')) {
            return $this.macro('reviewsecref', @($str, $this.sec_label($n.Replace('.', '-'))))
        }
        return $str
    }

    [string] inline_sec([string]$Id) {
        $n = ([ReviewBuilder]$this).inline_sec($Id)
        if ($this.Book.Config.Get('chapterlink')) {
            return $this.macro('reviewsecref', @($n, $this.sec_label($n.Replace('.', '-'))))
        }
        return $n
    }

    [string] inline_sectitle([string]$Id) {
        $title = ([ReviewBuilder]$this).inline_sectitle($Id)
        if ($this.Book.Config.Get('chapterlink')) {
            $resolved = $this.extract_chapter_id($Id)
            $anchor = $resolved[0].HeadlineIndex.NumberOf($resolved[1]).Replace('.', '-')
            return $this.macro('reviewsecref', @($title, $this.sec_label($anchor)))
        }
        return $title
    }

    [string] inline_column_chap([object]$Chap, [string]$Id) {
        try {
            return $this.macro('reviewcolumnref', @(
                    [ReviewI18n]::T('column', $this.compile_inline([string]$Chap.GetColumn($Id).Content())),
                    $this.column_label($Id, $Chap)))
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown column: $Id")
        }
    }

    # ---------------------------------------------------------------------------------
    # M5: single-line commands
    # ---------------------------------------------------------------------------------

    [void] hr() { $this.puts('\hrule') }
    [void] label([string[]]$ArgList) { $this.puts($this.macro('label', @($ArgList[0]))) }
    [void] pagebreak() { $this.puts('\pagebreak') }
    [void] blankline() { $this.puts('\par\vspace{\baselineskip}\par') }
    [void] noindent() { $this.print('\noindent') }
    [void] latextsize([string[]]$ArgList) { $this.LatexTSizeValue = $ArgList[0] }

    [void] comment([string[]]$Lines, [string[]]$ArgList) {
        if (-not $this.Book.Config.Get('draft')) { return }
        $all = [System.Collections.Generic.List[string]]::new()
        if ($ArgList.Count -gt 0 -and $ArgList[0]) { $all.Add($this.escape($ArgList[0])) }
        foreach ($l in @($Lines)) { $all.Add($l) }
        $this.puts($this.macro('pdfcomment', @($all -join '\par ')))
    }

    [void] box([string[]]$Lines, [string[]]$ArgList) {
        $caption = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
        $this.blank()
        if ($caption) { $this.puts($this.macro('reviewboxcaption', @($this.compile_inline($caption)))) }
        $this.puts('\begin{reviewbox}')
        foreach ($line in @($Lines)) { $this.puts($this.detab($line)) }
        $this.puts('\end{reviewbox}')
        $this.blank()
    }

    # ---------------------------------------------------------------------------------
    # M5: //texequation (plain LaTeX math only -- math_format: imgmath, which renders
    # equations to images via an external toolchain, remains a documented non-goal)
    # ---------------------------------------------------------------------------------

    [void] texequation([string[]]$Lines, [string[]]$ArgList) {
        $id = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { '' }
        $this.blank()
        $captionStr = $null
        if ($id) {
            $this.puts($this.macro('begin', @('reviewequationblock')))
            $num = $this.Chapter.GetEquation($id).Number
            $chap = $this.get_chap($null)
            $header = if ($null -eq $chap) {
                [ReviewI18n]::T('format_number_header_without_chapter', @($num))
            }
            else {
                [ReviewI18n]::T('format_number_header', @($chap, $num))
            }
            $captionStr = $this.macro('reviewequationcaption', @("$([ReviewI18n]::T('equation'))$header$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($caption))"))
        }
        if ($this.caption_top('equation') -and $captionStr) { $this.puts($captionStr) }
        $this.puts($this.macro('begin', @('equation*')))
        foreach ($line in @($Lines)) { $this.puts($line) }
        $this.puts($this.macro('end', @('equation*')))
        if (-not $this.caption_top('equation') -and $captionStr) { $this.puts($captionStr) }
        if ($id) { $this.puts($this.macro('end', @('reviewequationblock'))) }
        $this.blank()
    }

    # ---------------------------------------------------------------------------------
    # M5: images
    # ---------------------------------------------------------------------------------

    [string] image_ext() { return 'pdf' }

    hidden [string] existence([string]$Id) {
        if ($this.Chapter.ImageBound($Id)) { return 'exist' }
        return 'not exist'
    }

    [object] handle_metric([string]$Str) {
        $pdfCfg = $this.Book.Config.Get('pdfmaker')
        if ($pdfCfg -and $pdfCfg['image_scale2width'] -and $Str -match '^scale=([\d.]+)$') {
            return "width=$($Matches[1])\maxwidth"
        }
        return $Str
    }

    [string] parse_metric([string]$Type, [string]$Metric) {
        $s = ([ReviewBuilder]$this).parse_metric($Type, $Metric)
        $pdfCfg = $this.Book.Config.Get('pdfmaker')
        if ($pdfCfg -and $pdfCfg['use_original_image_size'] -and $s.Length -eq 0 -and [string]::IsNullOrWhiteSpace($Metric)) {
            return ' '
        }
        return $s
    }

    hidden [string] include_graphics_line([string]$Id, [string]$Metrics) {
        $cmd = if ($this.Book.Config.CheckVersion('2', $false)) { 'includegraphics' } else { 'reviewincludegraphics' }
        $p = $this.Chapter.GetImage($Id).Path()
        if ($Metrics) { return "\$cmd[$Metrics]{$p}" }
        return "\$cmd[width=\maxwidth]{$p}"
    }

    [void] image_image([string]$Id, [object]$Caption, [object]$Metric) {
        $this.doc_status.caption = $true
        $capMacro = if ($this.Book.Config.CheckVersion('2', $false)) { 'caption' } else { 'reviewimagecaption' }
        $captionStr = $this.macro($capMacro, @($this.compile_inline([string]$Caption))) + "`n" + $this.macro('label', @($this.image_label($Id, $null)))
        $this.doc_status.caption = $null

        $metrics = $this.parse_metric('latex', [string]$Metric)
        $this.puts("\begin{reviewimage}%%$Id")
        if ($this.caption_top('image')) { $this.puts($captionStr) }
        $this.puts($this.include_graphics_line($Id, $metrics))
        if (-not $this.caption_top('image')) { $this.puts($captionStr) }
        $this.puts('\end{reviewimage}')
    }

    [void] image_dummy([string]$Id, [object]$Caption, [string[]]$Lines) {
        Write-Warning "image not bound: $Id"
        $this.puts('\begin{reviewdummyimage}')
        $this.puts($this.escape("--[[path = $Id ($($this.existence($Id)))]]--"))
        foreach ($line in @($Lines)) {
            $this.puts("`n")
            $this.puts($this.detab($line.TrimEnd()))
        }
        $this.puts($this.macro('label', @($this.image_label($Id, $null))))
        $this.doc_status.caption = $true
        if ($this.Book.Config.CheckVersion('2', $false)) {
            if ($Caption) { $this.puts($this.macro('caption', @($this.compile_inline([string]$Caption)))) }
        }
        elseif ($Caption) {
            $this.puts($this.macro('reviewimagecaption', @($this.compile_inline([string]$Caption))))
        }
        $this.doc_status.caption = $null
        $this.puts('\end{reviewdummyimage}')
    }

    [void] indepimage([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $metric = if ($ArgList.Count -gt 2) { $ArgList[2] } else { $null }
        $metrics = $this.parse_metric('latex', [string]$metric)

        $captionStr = $null
        if ($caption) {
            $this.doc_status.caption = $true
            $captionStr = $this.macro('reviewindepimagecaption', @("$([ReviewI18n]::T('numberless_image'))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($caption))"))
            $this.doc_status.caption = $null
        }

        $bound = [bool]$this.Chapter.GetImage($id).Path()
        if ($bound) {
            $this.puts("\begin{reviewimage}%%$id")
            if ($this.caption_top('image') -and $captionStr) { $this.puts($captionStr) }
            $this.puts($this.include_graphics_line($id, $metrics))
        }
        else {
            Write-Warning "image not bound: $id"
            $this.puts('\begin{reviewdummyimage}')
            $this.puts($this.escape("--[[path = $($this.escape($id)) ($($this.existence($id)))]]--"))
            foreach ($line in @($Lines)) {
                $this.puts("`n")
                $this.puts($this.detab($line.TrimEnd()))
            }
        }

        if (-not $this.caption_top('image') -and $captionStr) { $this.puts($captionStr) }

        if ($bound) { $this.puts('\end{reviewimage}') } else { $this.puts('\end{reviewdummyimage}') }
    }

    [void] numberlessimage([string[]]$Lines, [string[]]$ArgList) { $this.indepimage($Lines, $ArgList) }

    [void] imgtable([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $metric = if ($ArgList.Count -gt 2) { $ArgList[2] } else { $null }

        if (-not $this.Chapter.ImageBound($id)) {
            Write-Warning "image not bound: $id"
            $this.image_dummy($id, $caption, $Lines)
            return
        }

        $captionStr = $null
        if ($caption) {
            $this.puts("\begin{table}[h]%%$id")
            $this.doc_status.caption = $true
            $captionStr = $this.macro('reviewimgtablecaption', @($this.compile_inline($caption)))
            $this.doc_status.caption = $null
            if ($this.caption_top('table')) { $this.puts($captionStr) }
        }
        $this.puts($this.macro('label', @($this.table_label($id, $null))))

        $metrics = $this.parse_metric('latex', [string]$metric)
        $this.puts("\begin{reviewimage}%%$id")
        $this.puts($this.include_graphics_line($id, $metrics))
        $this.puts('\end{reviewimage}')

        if ($caption) {
            if (-not $this.caption_top('table')) { $this.puts($captionStr) }
            $this.puts('\end{table}')
        }
        $this.blank()
    }

    # ---------------------------------------------------------------------------------
    # M5: tables
    # ---------------------------------------------------------------------------------

    [void] table([string[]]$Lines, [string[]]$ArgList) {
        $id = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $this.render_table($Lines, $id, $caption)
    }

    [void] emtable([string[]]$Lines, [string[]]$ArgList) {
        $caption = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
        $this.render_table($Lines, $null, $caption)
    }

    hidden [void] render_table([string[]]$Lines, [object]$Id, [object]$Caption) {
        if ($Caption) {
            if ($this.Book.Config.CheckVersion('2', $false)) { $this.puts("\begin{table}[h]%%$Id") }
            else { $this.puts("\begin{table}%%$Id") }
        }

        $parsed = $this.parse_table_rows($Lines)
        $sepIdx = $parsed[0]
        $rows = $parsed[1]
        if ($this.caption_top('table') -and $Caption) { $this.table_header($Id, $Caption) }
        $this.table_begin($rows[0].Count)
        $this.table_rows($sepIdx, $rows)
        $this.table_end()
        if ($Caption) {
            if (-not $this.caption_top('table')) { $this.table_header($Id, $Caption) }
            $this.puts('\end{table}')
        }
        $this.blank()
    }

    hidden [string] cell_width_at([int]$Index) {
        if ($null -eq $this.CellWidth -or $Index -ge $this.CellWidth.Count) { return $null }
        return [string]$this.CellWidth[$Index]
    }

    [void] table_rows([object]$SepIdx, [System.Collections.Generic.List[object]]$Rows) {
        if ($null -ne $SepIdx) {
            for ($r = 0; $r -lt $SepIdx; $r++) {
                $cols = $Rows[0]; $Rows.RemoveAt(0)
                $cells = for ($c = 0; $c -lt $cols.Count; $c++) { $this.th($cols[$c], $this.cell_width_at($c)) }
                $this.tr(@($cells))
            }
            foreach ($cols in $Rows) {
                $cells = for ($c = 0; $c -lt $cols.Count; $c++) { $this.td($cols[$c], $this.cell_width_at($c)) }
                $this.tr(@($cells))
            }
        }
        else {
            foreach ($cols in $Rows) {
                $cells = [System.Collections.Generic.List[string]]::new()
                $cells.Add($this.th($cols[0], $this.cell_width_at(0)))
                for ($c = 1; $c -lt $cols.Count; $c++) { $cells.Add($this.td($cols[$c], $this.cell_width_at($c))) }
                $this.tr($cells.ToArray())
            }
        }
    }

    [void] table_header([object]$Id, [object]$Caption) {
        if ($null -eq $Id) {
            if ($Caption) {
                $this.doc_status.caption = $true
                $this.puts($this.macro('reviewtablecaption*', @($this.compile_inline([string]$Caption))))
                $this.doc_status.caption = $null
            }
        }
        else {
            if ($Caption) {
                $this.doc_status.caption = $true
                $this.puts($this.macro('reviewtablecaption', @($this.compile_inline([string]$Caption))))
                $this.doc_status.caption = $null
            }
            $this.puts($this.macro('label', @($this.table_label([string]$Id, $null))))
        }
    }

    [void] table_begin([int]$NCols) {
        if ($this.LatexTSizeValue) { $this.TSizeValue = $this.LatexTSizeValue }

        if ($this.TSizeValue) {
            if ($this.TSizeValue -match '^[\d., ]+$') {
                $widths = @([regex]::Split($this.TSizeValue, '\s*,\s*') | ForEach-Object { "p{${_}mm}" })
                $this.CellWidth = $widths
                $this.puts($this.macro('begin', @('reviewtable', '|' + ($widths -join '|') + '|')))
            }
            else {
                $this.CellWidth = $this.separate_tsize($this.TSizeValue)
                $this.puts($this.macro('begin', @('reviewtable', $this.TSizeValue)))
            }
        }
        else {
            $this.puts($this.macro('begin', @('reviewtable', ((@('|') * ($NCols + 1)) -join 'l'))))
            $this.CellWidth = @('l') * $NCols
        }
        $this.puts('\hline')
    }

    [object[]] separate_tsize([string]$Size) {
        $ret = [System.Collections.Generic.List[string]]::new()
        $s = [System.Text.StringBuilder]::new()
        $brace = $false
        foreach ($ch in $Size.ToCharArray()) {
            if ($ch -eq '|') { continue }
            if ($ch -eq '{') { $brace = $true; [void]$s.Append($ch); continue }
            if ($ch -eq '}') { $brace = $false; [void]$s.Append($ch); $ret.Add($s.ToString()); [void]$s.Clear(); continue }
            if ($brace -or $s.Length -eq 0) {
                [void]$s.Append($ch)
            }
            else {
                $ret.Add($s.ToString())
                [void]$s.Clear()
                [void]$s.Append($ch)
            }
        }
        if ($s.Length -gt 0) { $ret.Add($s.ToString()) }
        return $ret.ToArray()
    }

    [string] th([string]$S, [object]$Width) {
        if ($S.Contains('\\')) {
            if (-not $this.Book.Config.CheckVersion('2', $false) -and [string]$Width -match '\{') {
                return $this.macro('reviewth', @($S.Replace("\\`n", '\newline{}')))
            }
            return $this.macro('reviewth', @($this.macro('shortstack[l]', @($S))))
        }
        return $this.macro('reviewth', @($S))
    }

    [string] td([string]$S, [object]$Width) {
        if ($S.Contains('\\')) {
            if (-not $this.Book.Config.CheckVersion('2', $false) -and [string]$Width -match '\{') {
                return $S.Replace("\\`n", '\newline{}')
            }
            return $this.macro('shortstack[l]', @($S))
        }
        return $S
    }

    [void] tr([string[]]$Cells) {
        $this.print($Cells -join ' & ')
        $this.puts(' \\  \hline')
    }

    [void] table_end() {
        $this.puts($this.macro('end', @('reviewtable')))
        $this.TSizeValue = $null
        $this.LatexTSizeValue = $null
        $this.CellWidth = $null
    }

    # ---------------------------------------------------------------------------------
    # M5: bibliography
    # ---------------------------------------------------------------------------------

    [void] bibpaper_header([string]$Id, [object]$Caption) {
        $this.puts("[$($this.Chapter.GetBibpaper($Id).Number)] $($this.compile_inline([string]$Caption))")
        $this.puts($this.macro('label', @("bib:$Id")))
    }

    [void] bibpaper_bibpaper([string]$Id, [object]$Caption, [string[]]$Lines) {
        $this.print((@($this.split_paragraph($Lines) | ForEach-Object { $_.TrimEnd("`r", "`n") }) -join "`n"))
        $this.puts('')
    }
}
