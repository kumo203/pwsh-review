# Port of review/lib/review/book/index.rb + book/index/item.rb -- the per-chapter/per-book
# numbering registries (ordered id -> Item(id, number, content)) that make Re:VIEW's
# two-pass cross-reference resolution work (see IndexBuilder, M3).
#
# ReviewIndex.Get($Id) mirrors Index#[] exactly, including its ambiguous-vs-not-found
# KeyError distinction (compound ids are pipe-joined, e.g. "chap1|fig1", and a bare
# fragment that matches more than one compound id is "ambiguous" rather than silently
# picking one).

class ReviewIndexItem {
    [string] $Id
    [object] $Number
    [object] $Caption
    [ReviewIndex] $Index

    ReviewIndexItem([string]$Id, [object]$Number) {
        $this.Id = $Id
        $this.Number = $Number
        $this.Caption = $null
    }

    ReviewIndexItem([string]$Id, [object]$Number, [object]$Caption) {
        $this.Id = $Id
        $this.Number = $Number
        $this.Caption = $Caption
    }

    # alias for Caption, matching Ruby's `alias_method :content, :caption`
    [object] Content() {
        return $this.Caption
    }

    [object] Path() {
        if ($null -ne $this.PathValue) { return $this.PathValue }
        if ($null -ne $this.Index) {
            $this.PathValue = $this.Index.FindPath($this.Id)
        }
        return $this.PathValue
    }

    hidden [object] $PathValue = $null
}

class ReviewIndex {
    hidden [System.Collections.Specialized.OrderedDictionary] $Entries

    ReviewIndex() {
        $this.Entries = [System.Collections.Specialized.OrderedDictionary]::new()
    }

    [int] Size() {
        return $this.Entries.Count
    }

    [void] AddItem([ReviewIndexItem]$Item) {
        if ($this.Entries.Contains($Item.Id) -and $this.GetType().Name -ne 'ReviewIconIndex') {
            Write-Warning "duplicate ID: $($Item.Id)"
        }
        $this.Entries[$Item.Id] = $Item
        $Item.Index = $this
    }

    [bool] ContainsKey([string]$Id) {
        return $this.Entries.Contains($Id)
    }

    # Mirrors Index#[] -- exact match first; otherwise scans pipe-joined compound ids for
    # a fragment match, raising on ambiguity (fragment matches 2+ compound ids) or absence.
    [ReviewIndexItem] Get([string]$Id) {
        if ($this.Entries.Contains($Id)) {
            return $this.Entries[$Id]
        }

        $fragmentCounts = @{}
        foreach ($key in $this.Entries.Keys) {
            foreach ($frag in ($key -split '\|')) {
                if (-not $fragmentCounts.ContainsKey($frag)) { $fragmentCounts[$frag] = 0 }
                $fragmentCounts[$frag]++
            }
        }
        if ($fragmentCounts.ContainsKey($Id) -and $fragmentCounts[$Id] -gt 1) {
            throw [ReviewKeyError]::new("key '$Id' is ambiguous for $($this.GetType().Name)")
        }

        foreach ($key in $this.Entries.Keys) {
            if (($key -split '\|') -contains $Id) {
                return $this.Entries[$key]
            }
        }

        throw [ReviewKeyError]::new("not found key '$Id' for $($this.GetType().Name)")
    }

    [string] NumberOf([string]$Id) {
        return [string]($this.Get($Id).Number)
    }

    [object[]] Each() {
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($key in $this.Entries.Keys) { $result.Add($this.Entries[$key]) }
        return $result.ToArray()
    }

    # Overridden by ImageIndex/subclasses; base Index has no image lookup.
    [object] FindPath([string]$Id) {
        throw [ReviewApplicationError]::new('FindPath is only supported on image-family indexes.')
    }
}

class ReviewChapterIndex : ReviewIndex {
    [string] NumberOf([string]$Id) {
        $item = $this.Get($Id)
        try {
            return [string]$item.Content().FormatNumber()
        }
        catch {
            return [ReviewI18n]::T('part', $item.Content().Number)
        }
    }

    [string] TitleOf([string]$Id) {
        try {
            return [string]$this.Get($Id).Content().Title()
        }
        catch {
            return [string]$this.Get($Id).Content().Name()
        }
    }

    [string] DisplayString([string]$Id) {
        $num = $this.NumberOf($Id)
        if ($num) {
            return [ReviewI18n]::T('chapter_quote', @($num, $this.TitleOf($Id)))
        }
        return [ReviewI18n]::T('chapter_quote_without_number', $this.TitleOf($Id))
    }
}

class ReviewListIndex : ReviewIndex {}
class ReviewTableIndex : ReviewIndex {}
class ReviewEquationIndex : ReviewIndex {}
class ReviewFootnoteIndex : ReviewIndex {}
class ReviewEndnoteIndex : ReviewIndex {}
class ReviewBibpaperIndex : ReviewIndex {}
class ReviewColumnIndex : ReviewIndex {}

class ReviewImageIndex : ReviewIndex {
    hidden [object] $Chapter

    ReviewImageIndex([object]$Chapter) : base() {
        $this.Chapter = $Chapter
    }

    # TODO (deferred to M5, when //image blocks are compiled): port
    # review/lib/review/book/image_finder.rb's extension-probing lookup. Until then this
    # throws rather than silently returning a wrong path.
    [object] FindPath([string]$Id) {
        throw [ReviewApplicationError]::new("image path resolution not yet implemented for '$Id' (deferred to M5)")
    }
}

class ReviewIconIndex : ReviewImageIndex {
    ReviewIconIndex([object]$Chapter) : base($Chapter) {}
}

class ReviewNumberlessImageIndex : ReviewImageIndex {
    ReviewNumberlessImageIndex([object]$Chapter) : base($Chapter) {}

    [string] NumberOf([string]$Id) {
        return ''
    }
}

class ReviewIndepImageIndex : ReviewImageIndex {
    ReviewIndepImageIndex([object]$Chapter) : base($Chapter) {}

    [string] NumberOf([string]$Id) {
        return ''
    }
}

class ReviewHeadlineIndex : ReviewIndex {
    hidden [object] $Chapter

    ReviewHeadlineIndex([object]$Chapter) : base() {
        $this.Chapter = $Chapter
    }

    [string] NumberOf([string]$Id) {
        $item = $this.Get($Id)
        if ($null -eq $item.Number) {
            return ''
        }

        $n = $this.Chapter.Number
        if ($this.Chapter.OnAppendix() -and $this.Chapter.Number -gt 0 -and $this.Chapter.Number -lt 28) {
            $n = $this.Chapter.FormatNumber($false)
        }

        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add([string]$n)
        foreach ($p in @($item.Number)) { $parts.Add([string]$p) }
        return ($parts -join '.')
    }
}
