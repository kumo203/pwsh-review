# Port of review/lib/review/htmlbuilder.rb (5.9.0) and htmlutils.rb -- the XHTML builder
# used for EPUB output. Mirrors the Ruby method-for-method (snake_case names, for the
# Compiler's dynamic dispatch -- see 13.Compiler.ps1), so EPUB chapter files are
# byte-identical to review-epubmaker's.
#
# Not ported (documented non-goals): syntax highlighting (config `highlight: html:`
# rouge/pygments -- the plain, unhighlighted output Ruby produces without it is
# implemented), math_format mathml/mathjax/imgmath (the default plain-text math is),
# //graph, and webmaker's layout/TOC.
#
# Loaded after 18b.ErbLiteTemplate.ps1: a project-local layouts/layout.html.erb is
# rendered through ReviewErbLiteTemplate.

# CGI.escapeHTML / CGI.escape / HTMLUtils helpers, shared with the EPUB maker.
class ReviewHtmlUtils {
    # CGI.escapeHTML: & < > " ' (the apostrophe as &#39;).
    static [string] Escape([string]$Str) {
        if ($null -eq $Str) { return '' }
        return $Str.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
    }

    static [string] Unescape([string]$Str) {
        return $Str.Replace('&quot;', '"').Replace('&gt;', '>').Replace('&lt;', '<').Replace('&amp;', '&')
    }

    static [string] StripHtml([string]$Str) { return [regex]::Replace($Str, '</?[^>]*>', '') }

    static [string] EscapeComment([string]$Str) { return $Str.Replace('-', '&#45;') }

    # CGI.escape (URL form encoding): UTF-8 bytes, everything except a-zA-Z0-9 _ . - ~
    # percent-encoded (uppercase hex), space as '+'.
    static [string] CgiEscape([string]$Str) {
        $sb = [System.Text.StringBuilder]::new()
        foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($Str)) {
            $c = [char]$b
            if (($b -ge 0x30 -and $b -le 0x39) -or ($b -ge 0x41 -and $b -le 0x5A) -or ($b -ge 0x61 -and $b -le 0x7A) -or
                $c -eq '_' -or $c -eq '.' -or $c -eq '-' -or $c -eq '~') {
                [void]$sb.Append($c)
            }
            elseif ($b -eq 0x20) {
                [void]$sb.Append('+')
            }
            else {
                [void]$sb.Append('%').Append($b.ToString('X2'))
            }
        }
        return $sb.ToString()
    }

    static [string] NormalizeId([string]$Id) {
        if ($Id -cmatch '^(?i)[a-z][a-z0-9_.-]*$') { return $Id }
        if ($Id -cmatch '^(?i)[0-9_.-][a-z0-9_.-]*$') { return "id_$Id" }
        return 'id_' + [ReviewHtmlUtils]::CgiEscape($Id.Replace('_', '__')).Replace('%', '_').Replace('+', '-')
    }
}

class ReviewHTMLBuilder : ReviewBuilder {
    hidden [bool] $NoIndentFlag = $false
    hidden [Nullable[int]] $OlNumValue = $null
    hidden [int] $ColumnCount = 0
    hidden [int] $NonumCounter = 0
    hidden [bool] $UseSectionValue = $false
    hidden [System.Collections.Generic.List[int]] $SectionStack

    ReviewHTMLBuilder() : base($false) {}

    [object] pre_paragraph() { return '<p>' }
    [object] post_paragraph() { return '</p>' }

    [string] extname() { return ".$($this.Book.Config.Get('htmlext'))" }

    [void] builder_init_file() {
        ([ReviewBuilder]$this).builder_init_file()
        $this.NoIndentFlag = $false
        $this.OlNumValue = $null
        # Ruby: @chapter.book.image_types = %w[.png .jpg .jpeg .gif .svg]
        $this.Book.Config.Set('image_types', @('.png', '.jpg', '.jpeg', '.gif', '.svg'))
        $this.ColumnCount = 0
        $this.NonumCounter = 0
        $this.FirstLineNumValue = $null
        $this.SectionStack = [System.Collections.Generic.List[int]]::new()
        $maker = if ($this.Book.Config.Maker) { $this.Book.Config.Maker } else { 'epubmaker' }
        $makerCfg = $this.Book.Config.Get($maker)
        $this.UseSectionValue = [bool]($makerCfg -is [hashtable] -and $makerCfg['use_section'])
    }

    hidden [bool] html5() { return [int]$this.Book.Config.Get('htmlversion') -eq 5 }
    hidden [bool] epub3() { return [int]$this.Book.Config.Get('epubversion') -eq 3 }
    [string] escape([string]$Str) { return [ReviewHtmlUtils]::Escape($Str) }
    [string] escape_html([string]$Str) { return [ReviewHtmlUtils]::Escape($Str) }
    hidden [string] normalize_id([string]$Id) { return [ReviewHtmlUtils]::NormalizeId($Id) }
    hidden [string] escape_comment([string]$Str) { return [ReviewHtmlUtils]::EscapeComment($Str) }
    hidden [string] strip_html([string]$Str) { return [ReviewHtmlUtils]::StripHtml($Str) }

    [bool] highlight() {
        $h = $this.Book.Config.Get('highlight')
        return [bool]($h -is [hashtable] -and $h['html'])
    }

    hidden [string] highlight_body([string]$Body) {
        if ($this.highlight()) {
            throw [ReviewApplicationError]::new("syntax highlighting (highlight: html: $($this.Book.Config.Get('highlight')['html'])) is not supported by this port")
        }
        return $Body
    }

    hidden [string] code_body([string[]]$Lines) {
        $sb = [System.Text.StringBuilder]::new()
        foreach ($l in @($Lines)) { [void]$sb.Append($this.detab($l)).Append("`n") }
        return $sb.ToString()
    }

    # --- sections (epubmaker.use_section) ------------------------------------------

    hidden [string] open_section([int]$Level) {
        $result = [System.Collections.Generic.List[string]]::new()
        while ($this.SectionStack.Count -gt 0 -and $Level -le $this.SectionStack[$this.SectionStack.Count - 1]) {
            $result.Add('</section>')
            $this.SectionStack.RemoveAt($this.SectionStack.Count - 1)
        }
        $this.SectionStack.Add($Level)
        $result.Add("<section class=`"level$Level`">")
        return ($result -join "`n")
    }

    hidden [string] close_sections() { return "</section>`n" * $this.SectionStack.Count }

    # --- document ------------------------------------------------------------------

    [string] result() {
        $this.check_printendnotes()
        if ($this.UseSectionValue) { $this.print($this.close_sections()) }

        $binding = [hashtable]::new([System.StringComparer]::Ordinal)
        $binding['@title'] = $this.strip_html($this.compile_inline($this.Chapter.Title()))
        $binding['@body'] = $this.solve_nest($this.Output.ToString())
        $binding['@language'] = $this.Book.Config.Get('language')
        $binding['@stylesheets'] = $this.Book.Config.Get('stylesheet')
        $binding['@javascripts'] = @()
        $binding['@body_ext'] = $null
        $nextChap = $this.Chapter.NextChapter()
        $prevChap = $this.Chapter.PrevChapter()
        $binding['@next'] = $nextChap
        $binding['@prev'] = $prevChap
        $binding['@next_title'] = if ($nextChap) { $this.compile_inline($nextChap.Title()) } else { '' }
        $binding['@prev_title'] = if ($prevChap) { $this.compile_inline($prevChap.Title()) } else { '' }
        return Format-ReviewHtmlLayout -BaseDir $this.Book.BaseDir -Binding $binding
    }

    [string] solve_nest([string]$S) {
        $this.check_nest()
        $r = $S
        $r = $r.Replace("</dd>`n</dl>`n`u{1}→dl←`u{1}", '')
        $r = $r.Replace("`u{1}→/dl←`u{1}", "</dd>`n</dl>←END`u{1}")
        $r = $r.Replace("</li>`n</ul>`n`u{1}→ul←`u{1}", '')
        $r = $r.Replace("`u{1}→/ul←`u{1}", "</li>`n</ul>←END`u{1}")
        $r = $r.Replace("</li>`n</ol>`n`u{1}→ol←`u{1}", '')
        $r = $r.Replace("`u{1}→/ol←`u{1}", "</li>`n</ol>←END`u{1}")
        $r = $r.Replace("</dl>←END`u{1}`n<dl>", '')
        $r = $r.Replace("</ul>←END`u{1}`n<ul>", '')
        $r = $r.Replace("</ol>←END`u{1}`n<ol>", '')
        $r = $r.Replace("←END`u{1}", '')
        return $r
    }

    # --- headlines -----------------------------------------------------------------

    [void] headline([int]$Level, [object]$Label, [string]$Caption) {
        if ($this.UseSectionValue) { $this.print($this.open_section($Level)) }
        $prefixAnchor = $this.headline_prefix($Level)
        $prefix = $prefixAnchor[0]
        $anchor = $prefixAnchor[1]
        # Ruby truthiness: an unnumbered chapter's anchor is "" -- still truthy, so it
        # still emits <a id="h"></a>. Only nil skips.
        if ($null -ne $prefix) { $prefix = "<span class=`"secno`">$prefix</span>" }
        if ($Level -gt 1) { $this.puts('') }
        $aId = ''
        if ($null -ne $anchor) { $aId = "<a id=`"h$anchor`"></a>" }

        if ($Caption.Length -eq 0) {
            if ($Label) { $this.puts($aId) }
        }
        elseif ($Label) {
            $this.puts("<h$Level id=`"$($this.normalize_id($Label))`">$aId$prefix$($this.compile_inline($Caption))</h$Level>")
        }
        else {
            $this.puts("<h$Level>$aId$prefix$($this.compile_inline($Caption))</h$Level>")
        }
    }

    hidden [string] nonum_id([object]$Label) {
        if ($Label) { return $this.normalize_id($Label) }
        return $this.normalize_id("$($this.Chapter.NameValue())_nonum$($this.NonumCounter)")
    }

    [void] nonum_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.NonumCounter++
        if ($Level -gt 1) { $this.puts() }
        if ([string]::IsNullOrWhiteSpace($Caption)) { return }
        $this.puts("<h$Level id=`"$($this.nonum_id($Label))`">$($this.compile_inline($Caption))</h$Level>")
    }
    [void] nonum_end([int]$Level) {}

    [void] notoc_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.NonumCounter++
        if ($Level -gt 1) { $this.puts() }
        if ([string]::IsNullOrWhiteSpace($Caption)) { return }
        $this.puts("<h$Level id=`"$($this.nonum_id($Label))`" notoc=`"true`">$($this.compile_inline($Caption))</h$Level>")
    }
    [void] notoc_end([int]$Level) {}

    [void] nodisp_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.NonumCounter++
        if ($Level -gt 1) { $this.puts('') }
        if ([string]::IsNullOrWhiteSpace($Caption)) { return }
        $id = $this.nonum_id($Label)
        $this.puts("<a id=`"$id`" /><h$Level id=`"$id`" hidden=`"true`">$($this.compile_inline($Caption))</h$Level>")
    }
    [void] nodisp_end([int]$Level) {}

    [void] column_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.puts('<div class="column">')
        $this.ColumnCount++
        if ($Level -gt 1) { $this.puts() }
        $aId = "<a id=`"column-$($this.ColumnCount)`"></a>"
        if ($Caption.Length -eq 0) {
            if ($Label) { $this.puts($aId) }
        }
        elseif ($Label) {
            $this.puts("<h$Level id=`"$($this.normalize_id($Label))`">$aId$($this.compile_inline($Caption))</h$Level>")
        }
        else {
            $this.puts("<h$Level>$aId$($this.compile_inline($Caption))</h$Level>")
        }
    }
    [void] column_end([int]$Level) { $this.puts('</div>') }

    [void] xcolumn_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.puts('<div class="xcolumn">')
        $this.headline($Level, $Label, $Caption)
    }
    [void] xcolumn_end([int]$Level) { $this.puts('</div>') }

    [void] ref_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.print('<div class="reference">')
        $this.headline($Level, $Label, $Caption)
    }
    [void] ref_end([int]$Level) { $this.puts('</div>') }

    [void] sup_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.print('<div class="supplement">')
        $this.headline($Level, $Label, $Caption)
    }
    [void] sup_end([int]$Level) { $this.puts('</div>') }

    # --- caption blocks / minicolumns ----------------------------------------------

    hidden [void] captionblock([string]$Type, [string[]]$Lines, [object]$Caption) {
        $this.check_nested_minicolumn()
        $this.puts("<div class=`"$Type`">")
        if (-not [string]::IsNullOrWhiteSpace([string]$Caption)) {
            $this.puts("<p class=`"caption`">$($this.compile_inline([string]$Caption))</p>")
        }
        $this.puts(($this.split_paragraph($Lines) -join "`n"))
        $this.puts('</div>')
    }

    [void] planning([string[]]$Lines, [string[]]$ArgList) { $this.captionblock('planning', $Lines, $ArgList[0]) }
    [void] best([string[]]$Lines, [string[]]$ArgList) { $this.captionblock('best', $Lines, $ArgList[0]) }
    [void] security([string[]]$Lines, [string[]]$ArgList) { $this.captionblock('security', $Lines, $ArgList[0]) }
    [void] point([string[]]$Lines, [string[]]$ArgList) { $this.captionblock('point', $Lines, $ArgList[0]) }
    [void] shoot([string[]]$Lines, [string[]]$ArgList) { $this.captionblock('shoot', $Lines, $ArgList[0]) }

    # //note{ ... //} etc. (Ruby's metaprogrammed CAPTION_TITLES #{name}_begin/_end)
    [void] common_block_begin([string]$Type, [object]$Caption) {
        $this.check_nested_minicolumn()
        $this.doc_status.minicolumn = $Type
        $this.puts("<div class=`"$Type`">")
        if (-not [string]::IsNullOrWhiteSpace([string]$Caption)) {
            $this.puts("<p class=`"caption`">$($this.compile_inline([string]$Caption))</p>")
        }
    }

    [void] common_block_end([string]$Type) {
        $this.puts('</div>')
        $this.doc_status.minicolumn = $null
    }

    [void] box([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $captionStr = $null
        $hasCaption = -not [string]::IsNullOrWhiteSpace($caption)
        if ($hasCaption) { $captionStr = "<p class=`"caption`">$($this.compile_inline($caption))</p>" }
        $this.puts('<div class="syntax">')
        if ($this.caption_top('list') -and $hasCaption) { $this.puts($captionStr) }
        $this.print('<pre class="syntax">')
        foreach ($line in @($Lines)) { $this.puts($this.detab($line)) }
        $this.puts('</pre>')
        if (-not $this.caption_top('list') -and $hasCaption) { $this.puts($captionStr) }
        $this.puts('</div>')
    }

    # --- lists ---------------------------------------------------------------------

    [void] ul_begin() { $this.puts('<ul>') }
    [void] ul_item_begin([string[]]$Lines) { $this.print("<li>$($this.join_lines_to_paragraph($Lines))") }
    [void] ul_item_end() { $this.puts('</li>') }
    [void] ul_end() { $this.puts('</ul>') }

    [void] ol_begin() {
        if ($null -ne $this.OlNumValue) {
            $this.puts("<ol start=`"$($this.OlNumValue)`">")
            $this.OlNumValue = $null
        }
        else {
            $this.puts('<ol>')
        }
    }
    [void] ol_item([string[]]$Lines, [string]$Num) { $this.puts("<li>$($this.join_lines_to_paragraph($Lines))</li>") }
    [void] ol_end() { $this.puts('</ol>') }
    [void] olnum([string[]]$ArgList) { $this.OlNumValue = [int]$ArgList[0] }

    [void] dl_begin() { $this.puts('<dl>') }
    [void] dt([string]$Line) { $this.puts("<dt>$Line</dt>") }
    [void] dd([string[]]$Lines) { $this.puts("<dd>$($this.join_lines_to_paragraph($Lines))</dd>") }
    [void] dl_end() { $this.puts('</dl>') }

    # --- paragraphs and simple blocks ----------------------------------------------

    [void] paragraph([string[]]$Lines) {
        if ($this.NoIndentFlag) {
            $this.puts("<p class=`"noindent`">$($this.join_lines_to_paragraph($Lines))</p>")
            $this.NoIndentFlag = $false
        }
        else {
            $this.puts("<p>$($this.join_lines_to_paragraph($Lines))</p>")
        }
    }

    [void] parasep() { $this.puts('<br />') }

    [void] read([string[]]$Lines) {
        $this.puts("<div class=`"lead`">`n$($this.split_paragraph($Lines) -join "`n")`n</div>")
    }
    [void] lead([string[]]$Lines) { $this.read($Lines) }

    [void] quote([string[]]$Lines) {
        $this.puts("<blockquote>$($this.split_paragraph($Lines) -join "`n")</blockquote>")
    }

    [void] doorquote([string[]]$Lines, [string[]]$ArgList) {
        $this.puts('<blockquote style="text-align:right;">')
        $this.puts(($this.split_paragraph($Lines) -join "`n"))
        $this.puts("<p>$($ArgList[0])より</p>")
        $this.puts('</blockquote>')
    }

    [void] talk([string[]]$Lines) {
        $this.puts('<div class="talk">')
        $this.puts(($this.split_paragraph($Lines) -join "`n"))
        $this.puts('</div>')
    }

    [void] flushright([string[]]$Lines) {
        $this.puts(($this.split_paragraph($Lines) -join "`n").Replace('<p>', '<p class="flushright">'))
    }

    [void] centering([string[]]$Lines) {
        $this.puts(($this.split_paragraph($Lines) -join "`n").Replace('<p>', '<p class="center">'))
    }

    [void] bpo([string[]]$Lines) {
        $this.puts('<bpo>')
        foreach ($line in @($Lines)) { $this.puts($this.detab($line)) }
        $this.puts('</bpo>')
    }

    [void] hr() { $this.puts('<hr />') }
    [void] label([string[]]$ArgList) { $this.puts("<a id=`"$($this.normalize_id($ArgList[0]))`"></a>") }
    [void] blankline() { $this.puts('<p><br /></p>') }
    [void] pagebreak() { $this.puts('<br class="pagebreak" />') }
    [void] noindent() { $this.NoIndentFlag = $true }

    [void] comment([string[]]$Lines, [string[]]$ArgList) {
        if (-not $this.Book.Config.Get('draft')) { return }
        $all = [System.Collections.Generic.List[string]]::new()
        if ($ArgList.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($ArgList[0])) { $all.Add($this.escape($ArgList[0])) }
        foreach ($l in @($Lines)) { $all.Add($l) }
        $this.puts("<div class=`"draft-comment`">$($all -join '<br />')</div>")
    }

    # --- code blocks ---------------------------------------------------------------

    hidden [string] list_caption_number([string]$Kind, [object]$Num) {
        $chap = $this.get_chap($null)
        if ($null -ne $chap) { return [ReviewI18n]::T('format_number_header', @($chap, $Num)) }
        return [ReviewI18n]::T('format_number_header_without_chapter', @($Num))
    }

    hidden [void] list_header([string]$Id, [string]$Caption) {
        $num = $this.Chapter.GetList($Id).Number
        $this.puts("<p class=`"caption`">$([ReviewI18n]::T('list'))$($this.list_caption_number('list', $num))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($Caption))</p>")
    }

    hidden [void] list_body([string[]]$Lines, [object]$Lang) {
        $classNames = [System.Collections.Generic.List[string]]::new()
        $classNames.Add('list')
        if (-not [string]::IsNullOrWhiteSpace([string]$Lang)) { $classNames.Add("language-$Lang") }
        if ($this.highlight()) { $classNames.Add('highlight') }
        $this.print("<pre class=`"$($classNames -join ' ')`">")
        $this.puts($this.highlight_body($this.code_body($Lines)))
        $this.puts('</pre>')
    }

    hidden [void] numbered_body([string[]]$Lines, [string]$CssClass, [object]$Lang) {
        $firstLineNumber = $this.line_num()
        $hs = $this.highlight_body($this.code_body($Lines))
        $classNames = [System.Collections.Generic.List[string]]::new()
        $classNames.Add($CssClass)
        if (-not [string]::IsNullOrWhiteSpace([string]$Lang)) { $classNames.Add("language-$Lang") }
        $this.print("<pre class=`"$($classNames -join ' ')`">")
        # Ruby String#split("\n") drops trailing empty fields.
        $hsLines = [System.Collections.Generic.List[string]]::new([string[]]$hs.Split("`n"))
        while ($hsLines.Count -gt 0 -and $hsLines[$hsLines.Count - 1].Length -eq 0) { $hsLines.RemoveAt($hsLines.Count - 1) }
        for ($i = 0; $i -lt $hsLines.Count; $i++) {
            $this.puts($this.detab("$($i + $firstLineNumber)".PadLeft(2) + ': ' + $hsLines[$i]))
        }
        $this.puts('</pre>')
    }

    [void] list([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]; $lang = if ($ArgList.Count -gt 2) { $ArgList[2] } else { $null }
        $this.puts("<div id=`"$($this.normalize_id($id))`" class=`"caption-code`">")
        try {
            if ($this.caption_top('list')) { $this.list_header($id, $caption) }
            $this.list_body($Lines, $lang)
            if (-not $this.caption_top('list')) { $this.list_header($id, $caption) }
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("no such list: $id")
        }
        $this.puts('</div>')
    }

    [void] listnum([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]; $lang = if ($ArgList.Count -gt 2) { $ArgList[2] } else { $null }
        $this.puts("<div id=`"$($this.normalize_id($id))`" class=`"code`">")
        try {
            if ($this.caption_top('list')) { $this.list_header($id, $caption) }
            $this.numbered_body($Lines, 'list', $lang)
            if (-not $this.caption_top('list')) { $this.list_header($id, $caption) }
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("no such list: $id")
        }
        $this.puts('</div>')
    }

    [void] source([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $hasCaption = -not [string]::IsNullOrWhiteSpace($caption)
        $this.puts('<div class="source-code">')
        if ($this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.print('<pre class="source">')
        $this.puts($this.highlight_body($this.code_body($Lines)))
        $this.puts('</pre>')
        if (-not $this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.puts('</div>')
    }

    [void] emlist([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]; $lang = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $hasCaption = -not [string]::IsNullOrWhiteSpace($caption)
        $this.puts('<div class="emlist-code">')
        if ($this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $classNames = [System.Collections.Generic.List[string]]::new()
        $classNames.Add('emlist')
        if (-not [string]::IsNullOrWhiteSpace([string]$lang)) { $classNames.Add("language-$lang") }
        if ($this.highlight()) { $classNames.Add('highlight') }
        $this.print("<pre class=`"$($classNames -join ' ')`">")
        $this.puts($this.highlight_body($this.code_body($Lines)))
        $this.puts('</pre>')
        if (-not $this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.puts('</div>')
    }

    [void] emlistnum([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]; $lang = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $hasCaption = -not [string]::IsNullOrWhiteSpace($caption)
        $this.puts('<div class="emlistnum-code">')
        if ($this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.numbered_body($Lines, 'emlist', $lang)
        if (-not $this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.puts('</div>')
    }

    [void] cmd([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        $hasCaption = -not [string]::IsNullOrWhiteSpace($caption)
        $this.puts('<div class="cmd-code">')
        if ($this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.print('<pre class="cmd">')
        $this.puts($this.highlight_body($this.code_body($Lines)))
        $this.puts('</pre>')
        if (-not $this.caption_top('list') -and $hasCaption) { $this.puts("<p class=`"caption`">$($this.compile_inline($caption))</p>") }
        $this.puts('</div>')
    }

    # --- equations (math_format unset: LaTeX source shown as text) --------------------

    hidden [void] assert_plain_math() {
        $fmt = $this.Book.Config.Get('math_format')
        if ($fmt) {
            throw [ReviewApplicationError]::new("math_format: $fmt is not supported by this port (only the default plain-text math)")
        }
    }

    [void] texequation([string[]]$Lines, [string[]]$ArgList) {
        $id = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { '' }
        if ($id) {
            $this.puts("<div id=`"$($this.normalize_id($id))`" class=`"caption-equation`">")
            if ($this.caption_top('equation')) { $this.texequation_header($id, $caption) }
        }
        $this.assert_plain_math()
        $this.puts('<div class="equation">')
        $this.print('<pre>')
        $this.puts($this.escape(($Lines -join "`n")))
        $this.puts('</pre>')
        $this.puts('</div>')
        if ($id) {
            if (-not $this.caption_top('equation')) { $this.texequation_header($id, $caption) }
            $this.puts('</div>')
        }
    }

    hidden [void] texequation_header([string]$Id, [string]$Caption) {
        $num = $this.Chapter.GetEquation($Id).Number
        $this.puts("<p class=`"caption`">$([ReviewI18n]::T('equation'))$($this.list_caption_number('equation', $num))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($Caption))</p>")
    }

    [string] inline_m([string]$Str) {
        $this.assert_plain_math()
        return "<span class=`"equation`">$($this.escape($Str))</span>"
    }

    # --- images --------------------------------------------------------------------

    [string] image_ext() { return 'png' }

    [object] handle_metric([string]$Str) {
        if ($Str -match '^scale=([\d.]+)$') {
            return @{ 'class' = ('width-{0:000}per' -f [int][Math]::Round([double]$Matches[1] * 100, [MidpointRounding]::AwayFromZero)) }
        }
        $kv = $Str.Split('=', 2)
        $v = if ($kv.Count -gt 1) { $kv[1] } else { '' }
        return @{ $kv[0] = ($v -replace '^["'']', '' -replace '["'']$', '') }
    }

    # Ruby builds each metric as a one-entry Hash and groups by key in first-seen order.
    [string] parse_metric([string]$Type, [string]$Metric) {
        if ([string]::IsNullOrWhiteSpace($Metric)) { return '' }
        $keys = [System.Collections.Generic.List[string]]::new()
        $values = [hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($param in [regex]::Split($Metric, ',\s*')) {
            $p = $param
            if ($p -match '^.+?::') {
                if ($p -notmatch "^${Type}::") { continue }
                $p = $p -replace "^${Type}::", ''
            }
            $h = $this.handle_metric($p)
            foreach ($k in $h.Keys) {
                if (-not $values.ContainsKey($k)) { $keys.Add($k); $values[$k] = [System.Collections.Generic.List[string]]::new() }
                $values[$k].Add([string]$h[$k])
            }
        }
        # result_metric: ' ' + attrs.join(' ') -- a lone space even when every metric
        # was filtered out by another builder's prefix.
        return ' ' + (@($keys | ForEach-Object { "$_=`"$($values[$_] -join ' ')`"" }) -join ' ')
    }

    hidden [string] image_src([string]$Id) { return ([string]$this.Chapter.GetImage($Id).Path()) -replace '^\./', '' }

    hidden [void] image_header([string]$Id, [object]$Caption) {
        $num = $this.Chapter.GetImage($Id).Number
        $this.puts('<p class="caption">')
        $this.puts("$([ReviewI18n]::T('image'))$($this.list_caption_number('image', $num))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline([string]$Caption))")
        $this.puts('</p>')
    }

    [void] image_image([string]$Id, [object]$Caption, [object]$Metric) {
        $metrics = $this.parse_metric('html', [string]$Metric)
        $this.puts("<div id=`"$($this.normalize_id($Id))`" class=`"image`">")
        if ($this.caption_top('image')) { $this.image_header($Id, $Caption) }
        $this.puts("<img src=`"$($this.image_src($Id))`" alt=`"$($this.escape($this.compile_inline([string]$Caption)))`"$metrics />")
        if (-not $this.caption_top('image')) { $this.image_header($Id, $Caption) }
        $this.puts('</div>')
    }

    [void] image_dummy([string]$Id, [object]$Caption, [string[]]$Lines) {
        Write-Warning "image not bound: $Id"
        $this.puts("<div id=`"$($this.normalize_id($Id))`" class=`"image`">")
        if ($this.caption_top('image')) { $this.image_header($Id, $Caption) }
        $this.puts('<pre class="dummyimage">')
        foreach ($line in @($Lines)) { $this.puts($this.detab($line)) }
        $this.puts('</pre>')
        if (-not $this.caption_top('image')) { $this.image_header($Id, $Caption) }
        $this.puts('</div>')
    }

    [void] indepimage([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]
        $caption = if ($ArgList.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($ArgList[1])) { $ArgList[1] } else { '' }
        $metric = if ($ArgList.Count -gt 2) { $ArgList[2] } else { $null }
        $metrics = $this.parse_metric('html', [string]$metric)
        $captionStr = $null
        if ($caption) {
            $captionStr = "<p class=`"caption`">`n$([ReviewI18n]::T('numberless_image'))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline($caption))`n</p>`n"
        }
        $this.puts("<div id=`"$($this.normalize_id($id))`" class=`"image`">")
        if ($this.caption_top('image') -and $caption) { $this.puts($captionStr) }
        $src = $this.Chapter.GetImage($id).Path()
        if ($src) {
            $this.puts("<img src=`"$(([string]$src) -replace '^\./', '')`" alt=`"$($this.escape($this.compile_inline($caption)))`"$metrics />")
        }
        else {
            Write-Warning "image not bound: $id"
            if ($Lines) {
                $this.puts('<pre class="dummyimage">')
                foreach ($line in @($Lines)) { $this.puts($this.detab($line)) }
                $this.puts('</pre>')
            }
        }
        if (-not $this.caption_top('image') -and $caption) { $this.puts($captionStr) }
        $this.puts('</div>')
    }

    [void] numberlessimage([string[]]$Lines, [string[]]$ArgList) { $this.indepimage($Lines, $ArgList) }

    [string] inline_icon([string]$Id) {
        $p = $this.Chapter.GetImage($Id).Path()
        if ($p) { return "<img src=`"$(([string]$p) -replace '^\./', '')`" alt=`"[$Id]`" />" }
        Write-Warning "image not bound: $Id"
        return "<pre>missing image: $Id</pre>"
    }

    # --- tables --------------------------------------------------------------------

    [void] table([string[]]$Lines, [string[]]$ArgList) {
        $id = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $this.render_table($Lines, $id, $caption)
    }

    [void] emtable([string[]]$Lines, [string[]]$ArgList) {
        $this.render_table($Lines, $null, $ArgList[0])
    }

    hidden [void] render_table([string[]]$Lines, [object]$Id, [object]$Caption) {
        if ($Id) { $this.puts("<div id=`"$($this.normalize_id($Id))`" class=`"table`">") }
        else { $this.puts('<div class="table">') }
        $parsed = $this.parse_table_rows($Lines)
        $sepIdx = $parsed[0]; $rows = $parsed[1]
        $hasCaption = -not [string]::IsNullOrWhiteSpace([string]$Caption)
        try {
            if ($this.caption_top('table') -and $hasCaption) { $this.table_header($Id, $Caption) }
            $this.puts('<table>')
            $this.table_rows($sepIdx, $rows)
            $this.puts('</table>')
            if (-not $this.caption_top('table') -and $hasCaption) { $this.table_header($Id, $Caption) }
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("no such table: $Id")
        }
        $this.puts('</div>')
    }

    [void] table_rows([object]$SepIdx, [System.Collections.Generic.List[object]]$Rows) {
        if ($null -ne $SepIdx) {
            for ($r = 0; $r -lt $SepIdx; $r++) {
                $cols = $Rows[0]; $Rows.RemoveAt(0)
                $this.tr(@($cols | ForEach-Object { $this.th($_) }))
            }
            foreach ($cols in $Rows) { $this.tr(@($cols | ForEach-Object { $this.td($_) })) }
        }
        else {
            foreach ($cols in $Rows) {
                $cells = [System.Collections.Generic.List[string]]::new()
                $cells.Add($this.th($cols[0]))
                for ($c = 1; $c -lt $cols.Count; $c++) { $cells.Add($this.td($cols[$c])) }
                $this.tr($cells.ToArray())
            }
        }
    }

    [void] table_header([object]$Id, [object]$Caption) {
        if ($null -eq $Id) {
            $this.puts("<p class=`"caption`">$($this.compile_inline([string]$Caption))</p>")
            return
        }
        $num = $this.Chapter.GetTable([string]$Id).Number
        $this.puts("<p class=`"caption`">$([ReviewI18n]::T('table'))$($this.list_caption_number('table', $num))$([ReviewI18n]::T('caption_prefix'))$($this.compile_inline([string]$Caption))</p>")
    }

    [string] th([string]$S) { return "<th>$S</th>" }
    [string] td([string]$S) { return "<td>$S</td>" }
    [void] tr([string[]]$Cells) { $this.puts("<tr>$($Cells -join '')</tr>") }

    [void] imgtable([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $metric = if ($ArgList.Count -gt 2) { $ArgList[2] } else { $null }
        if (-not $this.Chapter.ImageBound($id)) {
            Write-Warning "image not bound: $id"
            $this.image_dummy($id, $caption, $Lines)
            return
        }
        $hasCaption = -not [string]::IsNullOrWhiteSpace([string]$caption)
        $this.puts("<div id=`"$($this.normalize_id($id))`" class=`"imgtable image`">")
        try {
            if ($this.caption_top('table') -and $hasCaption) { $this.table_header($id, $caption) }
            $metrics = $this.parse_metric('html', [string]$metric)
            $this.puts("<img src=`"$($this.image_src($id))`" alt=`"$($this.escape($this.compile_inline([string]$caption)))`"$metrics />")
            if (-not $this.caption_top('table') -and $hasCaption) { $this.table_header($id, $caption) }
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("no such table: $id")
        }
        $this.puts('</div>')
    }

    # --- footnotes / endnotes ------------------------------------------------------

    hidden [bool] back_footnote() {
        $epubCfg = $this.Book.Config.Get('epubmaker')
        return [bool]($epubCfg -is [hashtable] -and $epubCfg['back_footnote'])
    }

    [void] footnote([string[]]$ArgList) {
        $id = $ArgList[0]; $str = $ArgList[1]
        $nid = $this.normalize_id($id)
        $num = $this.Chapter.GetFootnote($id).Number
        if ($this.epub3()) {
            $back = ''
            if ($this.back_footnote()) { $back = "<a href=`"#fnb-$nid`">$([ReviewI18n]::T('html_footnote_backmark'))</a>" }
            $this.puts("<div class=`"footnote`" epub:type=`"footnote`" id=`"fn-$nid`"><p class=`"footnote`">$back$([ReviewI18n]::T('html_footnote_textmark', $num))$($this.compile_inline($str))</p></div>")
        }
        else {
            $this.puts("<div class=`"footnote`" id=`"fn-$nid`"><p class=`"footnote`">[<a href=`"#fnb-$nid`">*$num</a>] $($this.compile_inline($str))</p></div>")
        }
    }

    [void] endnote_begin() { $this.puts('<div class="endnotes">') }
    [void] endnote_end() { $this.puts('</div>') }

    [void] endnote_item([string]$Id) {
        $nid = $this.normalize_id($Id)
        $back = ''
        if ($this.back_footnote()) { $back = "<a href=`"#endnoteb-$nid`">$([ReviewI18n]::T('html_footnote_backmark'))</a>" }
        $en = $this.Chapter.GetEndnote($Id)
        $this.puts("<div class=`"endnote`" id=`"endnote-$nid`"><p class=`"endnote`">$back$([ReviewI18n]::T('html_endnote_textmark', $en.Number))$($this.compile_inline([string]$en.Content()))</p></div>")
    }

    [string] inline_fn([string]$Id) {
        try {
            $nid = $this.normalize_id($Id)
            $num = $this.Chapter.GetFootnote($Id).Number
            if ($this.epub3()) {
                return "<a id=`"fnb-$nid`" href=`"#fn-$nid`" class=`"noteref`" epub:type=`"noteref`">$([ReviewI18n]::T('html_footnote_refmark', $num))</a>"
            }
            return "<a id=`"fnb-$nid`" href=`"#fn-$nid`" class=`"noteref`">*$num</a>"
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown footnote: $Id")
        }
    }

    [string] inline_endnote([string]$Id) {
        try {
            $nid = $this.normalize_id($Id)
            return "<a id=`"endnoteb-$nid`" href=`"#endnote-$nid`" class=`"noteref`" epub:type=`"noteref`">$([ReviewI18n]::T('html_endnote_refmark', $this.Chapter.GetEndnote($Id).Number))</a>"
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown endnote: $Id")
        }
    }

    # --- bibliography --------------------------------------------------------------

    [void] bibpaper([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]
        $caption = if ($ArgList.Count -gt 1) { $ArgList[1] } else { $null }
        $this.puts('<div class="bibpaper">')
        $this.bibpaper_header($id, $caption)
        if (@($Lines).Count -gt 0) { $this.bibpaper_bibpaper($id, $caption, $Lines) }
        $this.puts('</div>')
    }

    [void] bibpaper_header([string]$Id, [object]$Caption) {
        $this.print("<a id=`"bib-$($this.normalize_id($Id))`">")
        $this.print("[$($this.Chapter.GetBibpaper($Id).Number)]")
        $this.print('</a>')
        $this.puts(" $($this.compile_inline([string]$Caption))")
    }

    [void] bibpaper_bibpaper([string]$Id, [object]$Caption, [string[]]$Lines) {
        $this.print(($this.split_paragraph($Lines) -join ''))
    }

    [string] inline_bib([string]$Id) {
        try {
            $file = $this.Book.BibFile() -replace '\.re$', ".$($this.Book.Config.Get('htmlext'))"
            return "<a href=`"$file#bib-$($this.normalize_id($Id))`">[$($this.Chapter.GetBibpaper($Id).Number)]</a>"
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown bib: $Id")
        }
    }

    # --- references ----------------------------------------------------------------

    [string] inline_labelref([string]$IdRef) {
        return "<a target='$($this.escape($IdRef))'>「$([ReviewI18n]::T('label_marker'))$($this.escape($IdRef))」</a>"
    }
    [string] inline_ref([string]$IdRef) { return $this.inline_labelref($IdRef) }

    [string] inline_pageref([string]$Id) {
        throw [ReviewApplicationError]::new("pageref op is unsupported on this builder: $Id")
    }

    [string] inline_chapref([string]$Id) {
        $title = ([ReviewBuilder]$this).inline_chapref($Id)
        if ($this.Book.Config.Get('chapterlink')) { return "<a href=`"./$Id$($this.extname())`">$title</a>" }
        return $title
    }

    [string] inline_chap([string]$Id) {
        $num = ([ReviewBuilder]$this).inline_chap($Id)
        if ($this.Book.Config.Get('chapterlink')) { return "<a href=`"./$Id$($this.extname())`">$num</a>" }
        return $num
    }

    [string] inline_title([string]$Id) {
        $title = ([ReviewBuilder]$this).inline_title($Id)
        if ($this.Book.Config.Get('chapterlink')) { return "<a href=`"./$Id$($this.extname())`">$title</a>" }
        return $title
    }

    [string] inline_hd_chap([object]$Chap, [string]$Id) {
        try {
            $n = $Chap.HeadlineIndex.NumberOf($Id)
            $caption = $this.compile_inline([string]$Chap.GetHeadline($Id).Content())
            $str = if ($n -and $null -ne $Chap.Number -and $this.over_secnolevel($n)) {
                [ReviewI18n]::T('hd_quote', @($n, $caption))
            }
            else {
                [ReviewI18n]::T('hd_quote_without_number', $caption)
            }
            if ($this.Book.Config.Get('chapterlink')) {
                return "<a href=`"$($Chap.Id())$($this.extname())#h$("$n".Replace('.', '-'))`">$str</a>"
            }
            return $str
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown headline: $Id")
        }
    }

    [string] inline_sec([string]$Id) {
        $n = ([ReviewBuilder]$this).inline_sec($Id)
        if ($this.Book.Config.Get('chapterlink')) {
            $resolved = $this.extract_chapter_id($Id)
            $anchor = 'h' + "$($resolved[0].HeadlineIndex.NumberOf($resolved[1]))".Replace('.', '-')
            return "<a href=`"$($resolved[0].Id())$($this.extname())#$anchor`">$n</a>"
        }
        return $n
    }

    [string] inline_sectitle([string]$Id) {
        $title = ([ReviewBuilder]$this).inline_sectitle($Id)
        if ($this.Book.Config.Get('chapterlink')) {
            $resolved = $this.extract_chapter_id($Id)
            $anchor = 'h' + "$($resolved[0].HeadlineIndex.NumberOf($resolved[1]))".Replace('.', '-')
            return "<a href=`"$($resolved[0].Id())$($this.extname())#$anchor`">$title</a>"
        }
        return $title
    }

    [string] inline_column_chap([object]$Chap, [string]$Id) {
        try {
            $col = $Chap.GetColumn($Id)
            $str = [ReviewI18n]::T('column', $this.compile_inline([string]$col.Content()))
            if ($this.Book.Config.Get('chapterlink')) {
                return "<a href=`"$($Chap.Id())$($this.extname())#column-$($col.Number)`" class=`"columnref`">$str</a>"
            }
            return $str
        }
        catch [ReviewKeyError] {
            throw [ReviewApplicationError]::new("unknown column: $Id")
        }
    }

    hidden [string] item_ref([string]$Kind, [string]$Str, [string]$Id) {
        $resolved = $this.extract_chapter_id($Id)
        if ($this.Book.Config.Get('chapterlink')) {
            return "<span class=`"$Kind`"><a href=`"./$($resolved[0].Id())$($this.extname())#$($this.normalize_id($resolved[1]))`">$Str</a></span>"
        }
        return "<span class=`"$Kind`">$Str</span>"
    }

    [string] inline_list([string]$Id) { return $this.item_ref('listref', ([ReviewBuilder]$this).inline_list($Id), $Id) }
    [string] inline_table([string]$Id) { return $this.item_ref('tableref', ([ReviewBuilder]$this).inline_table($Id), $Id) }
    [string] inline_img([string]$Id) { return $this.item_ref('imgref', ([ReviewBuilder]$this).inline_img($Id), $Id) }
    [string] inline_eq([string]$Id) { return $this.item_ref('eqref', ([ReviewBuilder]$this).inline_eq($Id), $Id) }

    # --- inline formatting ---------------------------------------------------------

    [string] compile_ruby([object]$Base, [object]$Ruby) {
        if ($this.html5()) {
            return "<ruby>$($this.escape([string]$Base))<rp>$([ReviewI18n]::T('ruby_prefix'))</rp><rt>$($this.escape([string]$Ruby))</rt><rp>$([ReviewI18n]::T('ruby_postfix'))</rp></ruby>"
        }
        return "<ruby><rb>$($this.escape([string]$Base))</rb><rp>$([ReviewI18n]::T('ruby_prefix'))</rp><rt>$Ruby</rt><rp>$([ReviewI18n]::T('ruby_postfix'))</rp></ruby>"
    }

    [string] compile_kw([string]$Word, [object]$Alt) {
        $inner = if ($Alt) { $this.escape($Word + " ($(([string]$Alt).Trim()))") } else { $this.escape($Word) }
        return "<b class=`"kw`">$inner</b><!-- IDX:$($this.escape_comment($this.escape($Word))) -->"
    }

    [string] compile_href([string]$Url, [object]$Label) {
        if ($this.Book.Config.Get('externallink')) {
            $text = if ($null -eq $Label) { $this.escape($Url) } else { $this.escape([string]$Label) }
            return "<a href=`"$($this.escape($Url))`" class=`"link`">$text</a>"
        }
        if ($null -eq $Label) { return $this.escape($Url) }
        return [ReviewI18n]::T('external_link', @($this.escape([string]$Label), $this.escape($Url)))
    }

    hidden [string] asis([string]$Str, [string]$Tag) { return "<$Tag>$($this.escape($Str))</$Tag>" }

    [string] inline_i([string]$Str) { return "<i>$($this.escape($Str))</i>" }
    [string] inline_b([string]$Str) { return "<b>$($this.escape($Str))</b>" }
    [string] inline_ami([string]$Str) { return "<span class=`"ami`">$($this.escape($Str))</span>" }
    [string] inline_bou([string]$Str) { return "<span class=`"bou`">$($this.escape($Str))</span>" }
    [string] inline_tti([string]$Str) {
        if ($this.html5()) { return "<code class=`"tt`"><i>$($this.escape($Str))</i></code>" }
        return "<tt><i>$($this.escape($Str))</i></tt>"
    }
    [string] inline_ttb([string]$Str) {
        if ($this.html5()) { return "<code class=`"tt`"><b>$($this.escape($Str))</b></code>" }
        return "<tt><b>$($this.escape($Str))</b></tt>"
    }
    [string] inline_dtp([string]$Str) { return "<?dtp $Str ?>" }
    [string] inline_code([string]$Str) {
        if ($this.html5()) { return "<code class=`"inline-code tt`">$($this.escape($Str))</code>" }
        return "<tt class=`"inline-code`">$($this.escape($Str))</tt>"
    }
    [string] inline_idx([string]$Str) { return "$($this.escape($Str))<!-- IDX:$($this.escape_comment($this.escape($Str))) -->" }
    [string] inline_hidx([string]$Str) { return "<!-- IDX:$($this.escape_comment($this.escape($Str))) -->" }
    [string] inline_br([string]$Str) { return '<br />' }

    [string] inline_abbr([string]$Str) { return $this.asis($Str, 'abbr') }
    [string] inline_acronym([string]$Str) { return $this.asis($Str, 'acronym') }
    [string] inline_cite([string]$Str) { return $this.asis($Str, 'cite') }
    [string] inline_dfn([string]$Str) { return $this.asis($Str, 'dfn') }
    [string] inline_em([string]$Str) { return $this.asis($Str, 'em') }
    [string] inline_kbd([string]$Str) { return $this.asis($Str, 'kbd') }
    [string] inline_samp([string]$Str) { return $this.asis($Str, 'samp') }
    [string] inline_strong([string]$Str) { return $this.asis($Str, 'strong') }
    [string] inline_var([string]$Str) { return $this.asis($Str, 'var') }
    [string] inline_big([string]$Str) { return $this.asis($Str, 'big') }
    [string] inline_small([string]$Str) { return $this.asis($Str, 'small') }
    [string] inline_sub([string]$Str) { return $this.asis($Str, 'sub') }
    [string] inline_sup([string]$Str) { return $this.asis($Str, 'sup') }
    [string] inline_del([string]$Str) { return $this.asis($Str, 'del') }
    [string] inline_ins([string]$Str) { return $this.asis($Str, 'ins') }
    [string] inline_tt([string]$Str) {
        if ($this.html5()) { return "<code class=`"tt`">$($this.escape($Str))</code>" }
        return "<tt>$($this.escape($Str))</tt>"
    }
    [string] inline_u([string]$Str) { return "<u>$($this.escape($Str))</u>" }
    [string] inline_recipe([string]$Str) { return "<span class=`"recipe`">「$($this.escape($Str))」</span>" }
    [string] inline_uchar([string]$Str) { return "&#x$Str;" }
    [string] inline_comment([string]$Str) {
        if ($this.Book.Config.Get('draft')) { return "<span class=`"draft-comment`">$($this.escape($Str))</span>" }
        return ''
    }

    # Ruby: str.size == 1 && str.match(/[[:ascii:]]/) -- size counts characters.
    [string] inline_tcy([string]$Str) {
        $style = 'tcy'
        $chars = [System.Globalization.StringInfo]::new($Str).LengthInTextElements
        if ($chars -eq 1 -and $Str -match '[\x00-\x7F]') { $style = 'upright' }
        return "<span class=`"$style`">$($this.escape($Str))</span>"
    }

    [string] inline_balloon([string]$Str) { return "<span class=`"balloon`">$($this.escape($Str))</span>" }

    [string] text([string]$Str) { return $Str }
    [string] nofunc_text([string]$Str) { return $this.escape($Str) }
}
