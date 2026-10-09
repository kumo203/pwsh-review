# Port of review/lib/review/index_builder.rb -- the silent, pass-1 builder that only
# records numbering/index entries. Nearly every method is a near-no-op that optionally
# registers an Index::Item and recurses into inline text via compile_inline; errors are
# swallowed (Error() is a no-op) so a construct this pass doesn't understand never halts
# indexing.

class ReviewIndexBuilder : ReviewBuilder {
    [ReviewListIndex] $ListIndex
    [ReviewTableIndex] $TableIndex
    [ReviewEquationIndex] $EquationIndex
    [ReviewFootnoteIndex] $FootnoteIndex
    [ReviewEndnoteIndex] $EndnoteIndex
    [ReviewNumberlessImageIndex] $NumberlessImageIndex
    [ReviewImageIndex] $ImageIndex
    [ReviewIconIndex] $IconIndex
    [ReviewIndepImageIndex] $IndepImageIndex
    [ReviewHeadlineIndex] $HeadlineIndex
    [ReviewColumnIndex] $ColumnIndex
    [ReviewBibpaperIndex] $BibpaperIndex

    hidden [System.Collections.Generic.List[string]] $HeadlineStack
    hidden [hashtable] $CrossrefFootnote
    hidden [hashtable] $CrossrefEndnote

    ReviewIndexBuilder() : base($false) {}

    [object] pre_paragraph() { return '' }
    [object] post_paragraph() { return '' }

    [void] bind([object]$Compiler, [object]$Chapter, [object]$Location) {
        # Deliberately does NOT call Chapter/Book GenerateIndexes -- this IS the
        # indexing pass; calling them again here would recurse infinitely.
        $this.Compiler = $Compiler
        $this.Chapter = $Chapter
        $this.Location = $Location
        $this.Output = [System.Text.StringBuilder]::new()
        if ($Chapter) { $this.Book = $Chapter.Book }
        $this.builder_init_file()
    }

    [void] builder_init_file() {
        ([ReviewBuilder]$this).builder_init_file()
        $this.HeadlineStack = [System.Collections.Generic.List[string]]::new()
        $this.CrossrefFootnote = @{}
        $this.CrossrefEndnote = @{}

        $this.ListIndex = [ReviewListIndex]::new()
        $this.TableIndex = [ReviewTableIndex]::new()
        $this.EquationIndex = [ReviewEquationIndex]::new()
        $this.FootnoteIndex = [ReviewFootnoteIndex]::new()
        $this.EndnoteIndex = [ReviewEndnoteIndex]::new()
        $this.HeadlineIndex = [ReviewHeadlineIndex]::new($this.Chapter)
        $this.ColumnIndex = [ReviewColumnIndex]::new()
        $this.BibpaperIndex = [ReviewBibpaperIndex]::new()

        if ($this.Book) {
            $this.ImageIndex = [ReviewImageIndex]::new($this.Chapter)
            $this.IconIndex = [ReviewIconIndex]::new($this.Chapter)
            $this.NumberlessImageIndex = [ReviewNumberlessImageIndex]::new($this.Chapter)
            $this.IndepImageIndex = [ReviewIndepImageIndex]::new($this.Chapter)
        }
    }

    [string] result() { return $null }
    [string] target_name() { return 'index' }

    hidden [void] check_id([object]$Id) {
        if ($Id -and ($Id -match "[#%\\{}\[\]~/`$'""|*?&<>``\s]")) {
            Write-Warning "deprecated ID: '$($Matches[0])' in '$Id'"
        }
        elseif ($Id -and $Id.StartsWith('.')) {
            Write-Warning "deprecated ID: '$Id' begins from '.'"
        }
    }

    [void] headline([int]$Level, [object]$Label, [string]$Caption) {
        $this.check_id($Label)
        $this.SecCounter.Inc($Level)
        if ($Level -lt 2) { return }
        $cursor = $Level - 2
        $this.SetHeadlineStack($cursor, $(if ($Label) { $Label } else { $Caption }))
        $itemId = $this.HeadlineStack -join '|'
        $item = [ReviewIndexItem]::new($itemId, $this.SecCounter.NumberList(), $Caption)
        $this.HeadlineIndex.AddItem($item)
        [void]$this.compile_inline($Caption)
    }

    hidden [void] SetHeadlineStack([int]$Cursor, [string]$Value) {
        while ($this.HeadlineStack.Count -le $Cursor) { $this.HeadlineStack.Add($null) }
        $this.HeadlineStack[$Cursor] = $Value
        if ($this.HeadlineStack.Count -gt $Cursor + 1) {
            $this.HeadlineStack = [System.Collections.Generic.List[string]]::new($this.HeadlineStack.GetRange(0, $Cursor + 1))
        }
    }

    hidden [void] NoNumHeadline([int]$Level, [object]$Label, [string]$Caption) {
        $this.check_id($Label)
        if ($Level -lt 2) { return }
        $cursor = $Level - 2
        $this.SetHeadlineStack($cursor, $(if ($Label) { $Label } else { $Caption }))
        $itemId = $this.HeadlineStack -join '|'
        $item = [ReviewIndexItem]::new($itemId, $null, $Caption)
        $this.HeadlineIndex.AddItem($item)
    }

    [void] nonum_begin([int]$Level, [object]$Label, [string]$Caption) { $this.NoNumHeadline($Level, $Label, $Caption) }
    [void] nonum_end([int]$Level) {}
    [void] notoc_begin([int]$Level, [object]$Label, [string]$Caption) { $this.NoNumHeadline($Level, $Label, $Caption) }
    [void] notoc_end([int]$Level) {}
    [void] nodisp_begin([int]$Level, [object]$Label, [string]$Caption) { $this.NoNumHeadline($Level, $Label, $Caption) }
    [void] nodisp_end([int]$Level) {}

    [void] column_begin([int]$Level, [object]$Label, [string]$Caption) {
        $this.check_id($Label)
        $itemId = if ($Label) { $Label } else { $Caption }
        $item = [ReviewIndexItem]::new($itemId, $this.ColumnIndex.Size() + 1, $Caption)
        $this.ColumnIndex.AddItem($item)
    }
    [void] column_end([int]$Level) {}

    [void] ul_begin() {}
    [void] ul_item_begin([string[]]$Lines) {}
    [void] ul_item_end() {}
    [void] ul_end() {}
    [void] ol_begin() {}
    [void] ol_item([string[]]$Lines, [string]$Num) {}
    [void] ol_end() {}
    [void] dl_begin() {}
    [void] dt([string]$Line) {}
    [void] dd([string[]]$Lines) {}
    [void] dl_end() {}
    [void] paragraph([string[]]$Lines) {}
    [string] parasep() { return '' }
    [string] nofunc_text([string]$Str) { return '' }
    [void] read([string[]]$Lines) {}
    [void] lead([string[]]$Lines) {}

    [void] list([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $item = [ReviewIndexItem]::new($id, $this.ListIndex.Size() + 1)
        $this.ListIndex.AddItem($item)
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] source([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] listnum([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $item = [ReviewIndexItem]::new($id, $this.ListIndex.Size() + 1)
        $this.ListIndex.AddItem($item)
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] emlist([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] emlistnum([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] cmd([string[]]$Lines, [string[]]$ArgList) {
        $caption = $ArgList[0]
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] quote([string[]]$Lines) {
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] image([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $item = [ReviewIndexItem]::new($id, $this.ImageIndex.Size() + 1, $caption)
        $this.ImageIndex.AddItem($item)
        [void]$this.compile_inline($caption)
    }

    [void] table([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        if ($id) {
            $item = [ReviewIndexItem]::new($id, $this.TableIndex.Size() + 1, $caption)
            $this.TableIndex.AddItem($item)
        }
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [void] emtable([string[]]$Lines, [string[]]$ArgList) {
        [void]$this.compile_inline($ArgList[0])
    }

    [void] comment([string[]]$Lines, [string[]]$ArgList) {}

    [void] imgtable([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $this.TableIndex.AddItem([ReviewIndexItem]::new($id, $this.TableIndex.Size() + 1))
        $this.IndepImageIndex.AddItem([ReviewIndexItem]::new($id, $this.IndepImageIndex.Size() + 1))
        [void]$this.compile_inline($caption)
    }

    [void] footnote([string[]]$ArgList) {
        $id = $ArgList[0]; $str = $ArgList[1]
        $this.check_id($id)
        if (-not $this.CrossrefFootnote.ContainsKey($id)) { $this.CrossrefFootnote[$id] = 0 }
        $item = [ReviewIndexItem]::new($id, $this.FootnoteIndex.Size() + 1, $str)
        $this.FootnoteIndex.AddItem($item)
        [void]$this.compile_inline($str)
    }

    [void] endnote([string[]]$ArgList) {
        $id = $ArgList[0]; $str = $ArgList[1]
        $this.check_id($id)
        if (-not $this.CrossrefEndnote.ContainsKey($id)) { $this.CrossrefEndnote[$id] = 0 }
        $item = [ReviewIndexItem]::new($id, $this.EndnoteIndex.Size() + 1, $str)
        $this.EndnoteIndex.AddItem($item)
        [void]$this.compile_inline($str)
    }

    [void] indepimage([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $this.IndepImageIndex.AddItem([ReviewIndexItem]::new($id, $this.IndepImageIndex.Size() + 1))
        [void]$this.compile_inline($caption)
    }

    [void] numberlessimage([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $this.IndepImageIndex.AddItem([ReviewIndexItem]::new($id, $this.IndepImageIndex.Size() + 1))
        [void]$this.compile_inline($caption)
    }

    [void] hr() {}
    [void] label([string[]]$ArgList) { $this.check_id($ArgList[0]) }
    [void] blankline() {}
    [void] flushright([string[]]$Lines) { foreach ($line in $Lines) { [void]$this.compile_inline($line) } }
    [void] centering([string[]]$Lines) { foreach ($line in $Lines) { [void]$this.compile_inline($line) } }
    [void] olnum([string[]]$ArgList) {}
    [void] pagebreak() {}
    [void] bpo([string[]]$Lines) { foreach ($line in $Lines) { [void]$this.compile_inline($line) } }
    [void] noindent() {}
    [void] printendnotes() {}

    [string] compile_inline([string]$S) { return $this.Compiler.Text($S) }

    [string] inline_chapref([string]$Id) { return '' }
    [string] inline_chap([string]$Id) { return '' }
    [string] inline_title([string]$Id) { return '' }
    [string] inline_list([string]$Id) { return '' }
    [string] inline_img([string]$Id) { return '' }
    [string] inline_imgref([string]$Id) { return '' }
    [string] inline_table([string]$Id) { return '' }
    [string] inline_eq([string]$Id) { return '' }

    [string] inline_fn([string]$Id) {
        $this.CrossrefFootnote[$Id] = $(if ($this.CrossrefFootnote.ContainsKey($Id)) { $this.CrossrefFootnote[$Id] + 1 } else { 1 })
        return ''
    }

    [string] inline_endnote([string]$Id) {
        $this.CrossrefEndnote[$Id] = $(if ($this.CrossrefEndnote.ContainsKey($Id)) { $this.CrossrefEndnote[$Id] + 1 } else { 1 })
        return ''
    }

    [string] inline_i([string]$Str) { return '' }
    [string] inline_b([string]$Str) { return '' }
    [string] inline_ami([string]$Str) { return '' }
    [string] inline_bou([string]$Str) { return $Str }
    [string] inline_tti([string]$Str) { return '' }
    [string] inline_ttb([string]$Str) { return '' }
    [string] inline_dtp([string]$Str) { return '' }
    [string] inline_code([string]$Str) { return '' }
    [string] inline_idx([string]$Str) { return '' }
    [string] inline_hidx([string]$Str) { return '' }
    [string] inline_br([string]$Str) { return '' }
    [string] inline_m([string]$Str) { return '' }
    [void] firstlinenum([string[]]$ArgList) {}
    [string] inline_ruby([string]$Arg) { return '' }
    [string] inline_kw([string]$Arg) { return '' }
    [string] inline_href([string]$Arg) { return '' }
    [string] inline_hr([string]$Arg) { return '' }
    [string] text([string]$Str) { return '' }

    [void] bibpaper([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        $item = [ReviewIndexItem]::new($id, $this.BibpaperIndex.Size() + 1, $caption)
        $this.BibpaperIndex.AddItem($item)
        [void]$this.compile_inline($caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
    }

    [string] inline_hd([string]$Id) { return '' }
    [string] inline_ref([string]$Id) { return '' }
    [string] inline_labelref([string]$Id) { return '' }
    [string] inline_secref([string]$Id) { return '' }
    [string] inline_sec([string]$Id) { return '' }
    [string] inline_sectitle([string]$Id) { return '' }
    [string] inline_bib([string]$Id) { return '' }
    [string] inline_column([string]$Id) { return '' }
    [string] inline_pageref([string]$Id) { return '' }
    [string] inline_tcy([string]$Arg) { return '' }
    [string] inline_balloon([string]$Arg) { return '' }
    [string] inline_w([string]$S) { return '' }
    [string] inline_wb([string]$S) { return '' }
    [string] inline_abbr([string]$Str) { return '' }
    [string] inline_acronym([string]$Str) { return '' }
    [string] inline_cite([string]$Str) { return '' }
    [string] inline_dfn([string]$Str) { return '' }
    [string] inline_em([string]$Str) { return '' }
    [string] inline_kbd([string]$Str) { return '' }
    [string] inline_samp([string]$Str) { return '' }
    [string] inline_strong([string]$Str) { return '' }
    [string] inline_var([string]$Str) { return '' }
    [string] inline_big([string]$Str) { return '' }
    [string] inline_small([string]$Str) { return '' }
    [string] inline_sub([string]$Str) { return '' }
    [string] inline_sup([string]$Str) { return '' }
    [string] inline_tt([string]$Str) { return '' }
    [string] inline_del([string]$Str) { return '' }
    [string] inline_ins([string]$Str) { return '' }
    [string] inline_u([string]$Str) { return '' }
    [string] inline_recipe([string]$Str) { return '' }

    [string] inline_icon([string]$Id) {
        $this.check_id($Id)
        $this.IconIndex.AddItem([ReviewIndexItem]::new($Id, $this.IconIndex.Size() + 1))
        return ''
    }

    [string] inline_uchar([string]$Str) { return '' }
    [void] raw([string[]]$ArgList) {}
    [void] embed([string[]]$Lines, [string[]]$ArgList) {}

    # override: swallow all errors/warnings during the index pass
    [void] Error([object]$Msg) {}

    [void] texequation([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[1]
        $this.check_id($id)
        if ($id) {
            $this.EquationIndex.AddItem([ReviewIndexItem]::new($id, $this.EquationIndex.Size() + 1))
        }
        [void]$this.compile_inline($caption)
    }

    [object] get_chap([object]$ChapterArg) { return '' }
    [object[]] extract_chapter_id([string]$ChapRef) { return @('') }

    [string] captionblock([string]$Type, [string[]]$Lines, [object]$Caption) {
        [void]$this.compile_inline($Caption)
        foreach ($line in $Lines) { [void]$this.compile_inline($line) }
        return ''
    }

    [void] graph([string[]]$Lines, [string[]]$ArgList) {
        $id = $ArgList[0]; $caption = $ArgList[2]
        $this.image($Lines, @($id, $caption))
    }

    [void] tsize([string[]]$ArgList) {}
    [string] inline_raw([string]$Args0) { return '' }
    [string] inline_embed([string]$Args0) { return '' }
    [bool] highlight() { return $false }
}
