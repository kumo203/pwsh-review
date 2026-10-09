# Port of review/lib/review/builder.rb -- the base class every format builder (only
# ReviewLATEXBuilder in v1) extends. Method names are snake_case, matching Ruby exactly,
# because Compiler dispatches to them by constructing name strings dynamically -- see
# 13.Compiler.ps1's header comment.
#
# Scope note: Ruby's Builder defines generic wrappers for `list`/`listnum`/`source`
# (delegating to list_header/list_body/etc., which raise NoMethodError if a subclass
# doesn't override them) and for `image`/`table`/`bibpaper`/`graph` (delegating to
# image_image/table_header/etc.). This port's v1 LATEXBuilder subset (M2) only overrides
# list/listnum/source/emlist directly with LaTeX-specific bodies, not through this
# generic indirection, and does not yet implement image/table/bibpaper/graph at all (on
# either this base class or LATEXBuilder) -- deferred to M5. Since Compiler's dispatch
# gates on "does the builder have a method with this name" (Test-ReviewBuilderMethod),
# simply not defining these methods here produces the same graceful "builder does not
# support command" compile error Ruby would show if a subclass genuinely lacked them.

class ReviewBuilder {
    [bool] $Strict
    [object] $Output        # System.Text.StringBuilder
    # Public (not hidden): Compiler sets dynamic keys on this from outside the class
    # (`$Builder.doc_status.$name = $true`), which only round-trips through the SAME
    # hashtable instance if this is a plain property, never a method -- `$obj.Method`
    # without parens returns a method-reference object, not the method's return value,
    # so a method named doc_status() looked correct but silently did nothing useful here.
    [hashtable] $doc_status
    [object] $Compiler
    [object] $Chapter
    [object] $Book
    [object] $Location       # the bound ReviewLineInput (used for Compiler's line-number context)
    hidden [ReviewSecCounter] $SecCounter
    hidden [hashtable] $Dictionary
    hidden [bool] $ShownEndnotes = $true
    hidden [Nullable[int]] $TabWidth = $null
    hidden [Nullable[int]] $FirstLineNum = $null
    hidden [System.Collections.Generic.List[string]] $Children = $null

    ReviewBuilder() { $this.Init($false) }
    ReviewBuilder([bool]$Strict) { $this.Init($Strict) }

    hidden [void] Init([bool]$Strict) {
        $this.Strict = $Strict
        $this.doc_status = @{}
        $this.Dictionary = @{}
    }

    [object] pre_paragraph() { return $null }
    [object] post_paragraph() { return $null }

    [void] bind([object]$Compiler, [object]$Chapter, [object]$Location) {
        $this.Compiler = $Compiler
        $this.Chapter = $Chapter
        $this.Location = $Location
        $this.Output = [System.Text.StringBuilder]::new()
        if ($Chapter) { $this.Book = $Chapter.Book }
        $Chapter.GenerateIndexes($false)
        if ($this.Book) { $this.Book.GenerateIndexes() }
        $this.TabWidth = $null
        $this.builder_init_file()
    }

    [void] builder_init_file() {
        $this.SecCounter = [ReviewSecCounter]::new(5, $this.Chapter)
        $this.doc_status = @{}
    }

    [bool] highlight() { return $false }

    [string] solve_nest([string]$S) {
        $this.check_nest()
        return [regex]::Replace($S, "`u{1}→.+?←`u{1}", '')
    }

    [void] check_nest() {
        if ($this.Children -and $this.Children.Count -gt 0) {
            $reversed = $this.Children.ToArray()
            [array]::Reverse($reversed)
            throw [ReviewApplicationError]::new("$($this.Location): //beginchild of $($reversed -join ',') misses //endchild")
        }
    }

    [void] check_printendnotes() {
        if (-not $this.ShownEndnotes) {
            throw [ReviewApplicationError]::new("$($this.Location): //endnote is found but //printendnotes is not found.")
        }
    }

    [string] result() {
        $this.check_printendnotes()
        return $this.solve_nest($this.Output.ToString())
    }

    [void] print([string]$S) { [void]$this.Output.Append($S) }
    [void] puts([string]$S) { [void]$this.Output.Append($S).Append("`n") }
    [void] puts() { [void]$this.Output.Append("`n") }

    [string] target_name() {
        return ($this.GetType().Name -replace '^Review', '' -replace 'Builder$', '').ToLowerInvariant()
    }

    hidden [object[]] headline_prefix([int]$Level) {
        $this.SecCounter.Inc($Level)
        $anchor = $this.SecCounter.Anchor($Level)
        $prefix = $this.SecCounter.Prefix($Level, [int]$this.Book.Config.Get('secnolevel'))
        return @($prefix, $anchor)
    }

    [void] firstlinenum([string[]]$ArgList) {
        $this.FirstLineNum = [int]$ArgList[0]
    }

    [int] line_num() {
        if ($null -eq $this.FirstLineNum) { return 1 }
        $n = $this.FirstLineNum
        $this.FirstLineNum = $null
        return $n
    }

    [string] text([string]$Str) { return $Str }

    [string] compile_inline([string]$S) { return $this.Compiler.Text($S) }

    [string] nofunc_text([string]$Str) { return $Str }

    [void] blankline() { $this.puts('') }

    # --- minicolumn generic default (overridden by LATEXBuilder's LaTeX-specific body) ---
    [void] check_nested_minicolumn() {
        if ($this.doc_status.minicolumn) {
            throw [ReviewApplicationError]::new("$($this.Location): nested mini-column is not allowed")
        }
    }

    [bool] in_minicolumn() { return [bool]$this.doc_status.minicolumn }

    hidden static [string[]] $MinicolumnNames = @('note', 'memo', 'tip', 'info', 'warning', 'important', 'caution', 'notice')

    [bool] minicolumn_block_name([string]$Name) { return [ReviewBuilder]::MinicolumnNames -contains $Name }

    [void] common_block_begin([string]$Kind, [object]$Caption) {
        $this.check_nested_minicolumn()
        $this.doc_status.minicolumn = $Kind
        if ($Caption) { $this.puts($this.compile_inline($Caption)) }
    }

    [void] common_block_end([string]$Kind) {
        $this.doc_status.minicolumn = $null
    }

    # --- ul/ol/dl generic hooks ---
    [void] ul_item_begin([string[]]$Lines) { $this.ul_item($Lines) }
    [void] ul_item([string[]]$Lines) { throw [System.NotImplementedException]::new('ul_item must be overridden') }
    [void] ul_item_end() {}

    # --- endnote generic default ---
    [void] endnote_begin() {}
    [void] endnote_end() {}
    [void] endnote_item([string]$Id) {
        $this.puts("($($this.Chapter.GetEndnote($Id).Number)) $($this.compile_inline($this.Chapter.GetEndnote($Id).Content()))")
    }

    [void] printendnotes() {
        $this.ShownEndnotes = $true
        $this.endnote_begin()
        foreach ($en in $this.Chapter.EndnoteIndex.Each()) { $this.endnote_item($en.Id) }
        $this.endnote_end()
    }

    [void] endnote([string[]]$ArgList) {
        $this.ShownEndnotes = $false
    }

    # --- inline generics that resolve via the book/chapter index (cross-chapter aware) ---
    [string] inline_chapref([string]$Id) {
        try { return $this.compile_inline($this.Book.ChapterIndexValue().DisplayString($Id)) }
        catch [ReviewKeyError] { throw [ReviewApplicationError]::new("unknown chapter: $Id") }
    }

    [string] inline_chap([string]$Id) {
        try { return $this.Book.ChapterIndexValue().NumberOf($Id) }
        catch [ReviewKeyError] { throw [ReviewApplicationError]::new("unknown chapter: $Id") }
    }

    [string] inline_title([string]$Id) {
        try { return $this.compile_inline($this.Book.ChapterIndexValue().TitleOf($Id)) }
        catch [ReviewKeyError] { throw [ReviewApplicationError]::new("unknown chapter: $Id") }
    }

    hidden [object[]] extract_chapter_id([string]$ChapRef) {
        $m = [regex]::Match($ChapRef, '^([\w+-]+)\|(.+)')
        if ($m.Success) {
            $target = $m.Groups[1].Value
            $ch = $null
            foreach ($c in @($this.Book.Chapters()) + @($this.Book.Parts())) {
                if ($c.Id() -eq $target) { $ch = $c; break }
            }
            if (-not $ch) { throw [ReviewKeyError]::new("unknown chapter: $target") }
            return @($ch, $m.Groups[2].Value)
        }
        return @($this.Chapter, $ChapRef)
    }

    hidden [object] get_chap([object]$ChapterArg) {
        $chap = if ($ChapterArg) { $ChapterArg } else { $this.Chapter }
        $secnolevel = [int]$this.Book.Config.Get('secnolevel')
        if ($secnolevel -gt 0 -and $null -ne $chap.Number -and "$($chap.Number)".Length -gt 0) {
            if ($chap.IsPart()) { return [ReviewI18n]::T('part_short', $chap.Number) }
            return $chap.FormatNumber($null)
        }
        return $null
    }

    [string] inline_fn([string]$Id) {
        try { return $this.Chapter.GetFootnote($Id).Content() }
        catch [ReviewKeyError] { throw [ReviewApplicationError]::new("unknown footnote: $Id") }
    }

    [string] inline_endnote([string]$Id) {
        try { return "($($this.Chapter.GetEndnote($Id).Number))" }
        catch [ReviewKeyError] { throw [ReviewApplicationError]::new("unknown endnote: $Id") }
    }

    [string] inline_bou([string]$Str) { return $this.text($Str) }

    [string] compile_kw([string]$Word, [object]$Alt) {
        throw [System.NotImplementedException]::new('compile_kw must be overridden')
    }

    [string] inline_kw([string]$Arg) {
        $parts = $Arg.Split(',', 2)
        $word = $parts[0]
        $alt = if ($parts.Count -gt 1) { $parts[1] } else { $null }
        return $this.compile_kw($word, $alt)
    }

    [string] compile_href([string]$Url, [object]$Label) {
        throw [System.NotImplementedException]::new('compile_href must be overridden')
    }

    # @(...) forces array wrapping: a regex with exactly one match otherwise collapses
    # PowerShell's pipeline result to a bare [string] scalar, so $parts[0] silently
    # indexes a CHARACTER out of that string instead of the whole match (confirmed by a
    # real failure here: "[System.Char] does not contain a method named 'Replace'").
    [string] inline_href([string]$Arg) {
        $parts = @([regex]::Matches($Arg, '(?:(?:(?:\\\\)*\\,)|[^,\\]+)+') | ForEach-Object { $_.Value.TrimStart() })
        $url = ([string]$parts[0]).Replace('\,', ',').Trim()
        $label = if ($parts.Count -gt 1) { ([string]$parts[1]).Replace('\,', ',').Trim() } else { $null }
        return $this.compile_href($url, $label)
    }

    [string] compile_ruby([object]$Base, [object]$Ruby) {
        throw [System.NotImplementedException]::new('compile_ruby must be overridden')
    }

    [string] inline_ruby([string]$Arg) {
        $parts = @([regex]::Matches($Arg, '(?:(?:(?:\\\\)*\\,)|[^,\\]+)+') | ForEach-Object { $_.Value })
        $base = if ($parts.Count -gt 0) { ([string]$parts[0]).Replace('\,', ',').Trim() } else { $null }
        $ruby = if ($parts.Count -gt 1) { (($parts[1..($parts.Count - 1)]) -join ',').Replace('\,', ',').Trim() } else { $null }
        return $this.compile_ruby($base, $ruby)
    }

    [string] inline_pageref([string]$Id) { return "[link:$Id]" }
    [string] inline_tcy([string]$Arg) { return "$Arg[rotate 90 degree]" }
    [string] inline_balloon([string]$Arg) { return "← $Arg" }

    [string] inline_w([string]$S) {
        $translated = $this.Dictionary[$S]
        if ($translated) { return $this.escape($translated) }
        Write-Warning "word not bound: $S"
        return $this.escape("[missing word: $S]")
    }

    [string] inline_wb([string]$S) {
        $v = $this.Dictionary[$S]
        return $this.inline_b($(if ($v) { $v } else { "[missing word: $S]" }))
    }

    [string] inline_b([string]$Str) { throw [System.NotImplementedException]::new('inline_b must be overridden') }

    [void] raw([string[]]$ArgList) {
        $str = $ArgList[0]
        $m = [regex]::Match($str, '\|(.*?)\|(.*)')
        if ($m.Success) {
            $builders = $m.Groups[1].Value.Split(',') | ForEach-Object { $_ -replace '\s', '' }
            if ($builders -contains $this.target_name()) {
                $this.print($m.Groups[2].Value.Replace('\n', "`n"))
            }
        }
        else {
            $this.print($str.Replace('\n', "`n"))
        }
    }

    [void] embed([string[]]$Lines, [string[]]$ArgList) {
        $arg = $ArgList[0]
        if ($arg) {
            $builders = ($arg -replace '^\s*\|', '' -replace '\|\s*$', '' -replace '\s', '').Split(',')
            if ($builders -contains $this.target_name()) {
                $this.print(($Lines -join "`n") + "`n")
            }
        }
        else {
            $this.print(($Lines -join "`n") + "`n")
        }
    }

    [object] handle_metric([string]$Str) { return $Str }
    [string] result_metric([string[]]$Array) { return ($Array -join ',') }

    [string] parse_metric([string]$Type, [string]$Metric) {
        if ([string]::IsNullOrWhiteSpace($Metric)) { return '' }
        $params = [regex]::Split($Metric, ',\s*')
        $results = [System.Collections.Generic.List[string]]::new()
        foreach ($param in $params) {
            $p = $param
            if ($p -match '^.+?::') {
                if ($p -notmatch "^${Type}::") { continue }
                $p = $p -replace "^${Type}::", ''
            }
            $results.Add([string]$this.handle_metric($p))
        }
        return $this.result_metric($results.ToArray())
    }

    hidden [string] $TSize = $null

    [void] tsize([string[]]$ArgList) {
        $str = $ArgList[0]
        $m = [regex]::Match($str, '^\|(.*?)\|(.*)')
        if ($m.Success) {
            $builders = $m.Groups[1].Value.Split(',') | ForEach-Object { $_ -replace '\s', '' }
            if ($builders -contains $this.target_name()) { $this.TSize = $m.Groups[2].Value }
        }
        else {
            $this.TSize = $str
        }
    }

    [string] inline_raw([string]$Args0) {
        $m = [regex]::Match($Args0, '\|(.*?)\|(.*)')
        if ($m.Success) {
            $builders = $m.Groups[1].Value.Split(',') | ForEach-Object { $_ -replace '\s', '' }
            if ($builders -contains $this.target_name()) { return $m.Groups[2].Value.Replace('\n', "`n") }
            return ''
        }
        return $Args0.Replace('\n', "`n")
    }

    [string] inline_embed([string]$Args0) {
        $m = [regex]::Match($Args0, '\|(.*?)\|(.*)')
        if ($m.Success) {
            $builders = $m.Groups[1].Value.Split(',') | ForEach-Object { $_ -replace '\s', '' }
            if ($builders -contains $this.target_name()) { return $m.Groups[2].Value }
            return ''
        }
        return $Args0
    }

    [bool] over_secnolevel([object]$N) {
        return [int]$this.Book.Config.Get('secnolevel') -ge ("$N".Split('.').Count)
    }

    [string] detab([string]$Str) {
        if ($this.TabWidth) { return $this.detab($Str, $this.TabWidth) }
        return $this.detab($Str, 8)
    }

    [string] detab([string]$Str, [int]$Ts) {
        $add = 0
        $sb = [System.Text.StringBuilder]::new()
        $col = 0
        foreach ($ch in $Str.ToCharArray()) {
            if ($ch -eq "`t") {
                $len = $Ts - (($col + $add) % $Ts)
                $add += $len - 1
                [void]$sb.Append(' ' * $len)
                $col++
            }
            else {
                [void]$sb.Append($ch)
                $col++
            }
        }
        return $sb.ToString()
    }

    [string] escape([string]$Str) { return $Str }

    [string] previous_list_type() { return $this.Compiler.PreviousListType }

    [void] beginchild() {
        if ($null -eq $this.Children) { $this.Children = [System.Collections.Generic.List[string]]::new() }
        $prevType = $this.previous_list_type()
        if (-not $prevType) {
            throw [ReviewApplicationError]::new("$($this.Location): //beginchild is shown, but previous element isn't ul, ol, or dl")
        }
        $this.puts("`u{1}→${prevType}←`u{1}")
        $this.Children.Add($prevType)
    }

    [void] endchild() {
        if ($null -eq $this.Children -or $this.Children.Count -eq 0) {
            throw [ReviewApplicationError]::new("$($this.Location): //endchild is shown, but any opened //beginchild doesn't exist")
        }
        else {
            $last = $this.Children[$this.Children.Count - 1]
            $this.Children.RemoveAt($this.Children.Count - 1)
            $this.puts("`u{1}→/${last}←`u{1}")
        }
    }

    [bool] caption_top([string]$Type) {
        $pos = $this.Book.Config.Get('caption_position')[$Type]
        if ($pos -ne 'top' -and $pos -ne 'bottom') {
            Write-Warning "invalid caption_position/$Type parameter. 'top' is assumed"
        }
        return $pos -ne 'bottom'
    }

    # --- join_lines_to_paragraph / split_paragraph (review/lib/review/textutils.rb) ---
    # Gap: Ruby's add_space? (CJK-aware line joining via unicode/eaw) is not ported;
    # join_lines_by_lang is treated as always falsy, matching its default and the
    # short-circuit path Ruby itself takes when the config flag is off.
    [string] join_lines_to_paragraph([string[]]$Lines) {
        return ($Lines -join '')
    }

    hidden [string[]] trim_lines([string[]]$Lines) {
        $list = [System.Collections.Generic.List[string]]::new($Lines)
        while ($list.Count -gt 0 -and $list[$list.Count - 1].Trim().Length -eq 0) {
            $list.RemoveAt($list.Count - 1)
        }
        return $list.ToArray()
    }

    [string[]] split_paragraph([string[]]$Lines) {
        $trimmed = $this.trim_lines($Lines)
        $blocks = [System.Collections.Generic.List[System.Collections.Generic.List[string]]]::new()
        $blocks.Add([System.Collections.Generic.List[string]]::new())
        foreach ($element in $trimmed) {
            if ($element.Length -eq 0) {
                if ($blocks[$blocks.Count - 1].Count -gt 0) {
                    $blocks.Add([System.Collections.Generic.List[string]]::new())
                }
            }
            else {
                $blocks[$blocks.Count - 1].Add($element)
            }
        }
        return @($blocks | ForEach-Object { $this.join_lines_to_paragraph($_.ToArray()) })
    }
}
