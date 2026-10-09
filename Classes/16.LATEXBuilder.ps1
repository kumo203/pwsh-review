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

    static [hashtable] $Headline = @{
        1 = 'chapter'; 2 = 'section'; 3 = 'subsection'; 4 = 'subsubsection'; 5 = 'paragraph'; 6 = 'subparagraph'
    }

    ReviewLATEXBuilder() : base($false) {}

    [string] extname() { return '.tex' }

    [void] builder_init_file() {
        ([ReviewBuilder]$this).builder_init_file()
        $this.BlankNeeded = $false
        $this.FootText = @{}
        $this.Escaper = [ReviewLaTeXEscaper]::new([string]$this.Book.Config.Get('texcommand'))
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
            $headlineName = [ReviewLATEXBuilder]::Headline[$Level]
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
        $this.puts($this.macro([ReviewLATEXBuilder]::Headline[$Level] + '*', @($this.compile_inline($Caption))))
        $this.doc_status.caption = $null
        $this.puts($this.macro('addcontentsline', @('toc', [ReviewLATEXBuilder]::Headline[$Level], $this.compile_inline($Caption))))
    }
    [void] nonum_end([int]$Level) {}

    [void] notoc_begin([int]$Level, [object]$Label, [string]$Caption) {
        if ($this.Output.Length -ne 0) { $this.blank() }
        $this.doc_status.caption = $true
        $this.puts($this.macro([ReviewLATEXBuilder]::Headline[$Level] + '*', @($this.compile_inline($Caption))))
        $this.doc_status.caption = $null
    }
    [void] notoc_end([int]$Level) {}

    [void] nodisp_begin([int]$Level, [object]$Label, [string]$Caption) {
        if ($this.Output.Length -eq 0) { $this.puts($this.macro('clearpage', @())) } else { $this.blank() }
        $this.puts($this.macro('addcontentsline', @('toc', [ReviewLATEXBuilder]::Headline[$Level], $this.compile_inline($Caption))))
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
            $this.puts("\addcontentsline{toc}{$([ReviewLATEXBuilder]::Headline[$Level])}{$($this.compile_inline($Caption))}")
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

    [void] ol_begin() { $this.blank(); $this.puts('\begin{enumerate}') }
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

    [void] read([string[]]$Lines, [string[]]$ArgList) { $this.latex_block('quotation', $Lines) }
    [void] lead([string[]]$Lines, [string[]]$ArgList) { $this.latex_block('quotation', $Lines) }

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

    [string] inline_idx([string]$Str) { return $this.escape($Str) }
    [string] inline_hidx([string]$Str) { return '' }

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

    [string] compile_href([string]$Url, [object]$Label) {
        if ($Url.StartsWith('#')) {
            $anchor = $Url -replace '^#', ''
            if ($Label) { return "\hyperref[$($this.escape($anchor))]{$($this.escape($Label))}" }
            return "\hyperref[$($this.escape($anchor))]{$($this.escape($Url))}"
        }
        elseif ($Url -match '^[a-z]+:') {
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
}
