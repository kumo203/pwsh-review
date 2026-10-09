# Port of review/lib/review/book/book_unit.rb -- the shared base of Chapter and Part.
#
# ExecuteIndexer()/GenerateIndexes() reference ReviewIndexBuilder/ReviewCompiler, which
# are defined much later in the load order (M2/M3). Per the project's forward-reference
# mitigation (see PwshReview.psm1's header comment), these are instantiated via
# `New-Object -TypeName` (resolved at *runtime*, by string, after the whole module has
# loaded) rather than a `[ReviewIndexBuilder]::new()` type-literal (resolved at *parse
# time* of this file, which would fail since that class doesn't exist yet when 07.* is
# dot-sourced).

class ReviewBookUnit {
    [object] $Book
    [string] $Path
    [string] $Content
    [string[]] $Lines
    hidden [string] $Name
    hidden [string] $TitleValue = $null

    hidden [object] $IndexBuilderInstance = $null
    [ReviewListIndex] $ListIndex
    [ReviewTableIndex] $TableIndex
    [ReviewEquationIndex] $EquationIndex
    [ReviewFootnoteIndex] $FootnoteIndex
    [ReviewEndnoteIndex] $EndnoteIndex
    [ReviewHeadlineIndex] $HeadlineIndex
    [ReviewColumnIndex] $ColumnIndex
    [ReviewNumberlessImageIndex] $NumberlessImageIndex
    [ReviewImageIndex] $ImageIndex
    [ReviewIconIndex] $IconIndex
    [ReviewIndepImageIndex] $IndepImageIndex

    [string] Id() {
        if (-not $this.Name) { return $null }
        return [System.IO.Path]::GetFileNameWithoutExtension($this.Name)
    }

    [string] NameValue() {
        return $this.Id()
    }

    [string] Dirname() {
        if (-not $this.Path) { return $null }
        return Split-Path -Parent $this.Path
    }

    [string] Basename() {
        if (-not $this.Path) { return $null }
        return Split-Path -Leaf $this.Path
    }

    # Lazily extracts the first headline's text, mirroring Ruby's title method.
    # Returns '' (not $null) when there's no content/headline, same as Ruby.
    [string] Title() {
        if ($this.TitleValue) { return $this.TitleValue }
        $this.TitleValue = ''
        if (-not $this.Content) { return $this.TitleValue }

        foreach ($line in ($this.Content -split "`n")) {
            if ($line -match '^=+') {
                $stripped = $line -replace '^=+(\[.+?\])?(\{.+?\})?', ''
                $this.TitleValue = $stripped.Trim()
                break
            }
        }
        return $this.TitleValue
    }

    [object] ExecuteIndexer([bool]$Force) {
        if ($this.IndexBuilderInstance -and -not $Force) {
            return $this.IndexBuilderInstance
        }
        $this.IndexBuilderInstance = New-Object -TypeName 'ReviewIndexBuilder'
        $compiler = New-Object -TypeName 'ReviewCompiler' -ArgumentList $this.IndexBuilderInstance
        $compiler.Compile($this)
        return $this.IndexBuilderInstance
    }

    [void] GenerateIndexes([bool]$UseBib) {
        if (-not $this.Content) { return }

        $this.Lines = [ReviewLineInput]::SplitKeepingNewlines($this.Content)
        $indexes = $this.ExecuteIndexer($false)

        $this.ListIndex = $indexes.ListIndex
        $this.TableIndex = $indexes.TableIndex
        $this.EquationIndex = $indexes.EquationIndex
        $this.FootnoteIndex = $indexes.FootnoteIndex
        $this.EndnoteIndex = $indexes.EndnoteIndex
        $this.HeadlineIndex = $indexes.HeadlineIndex
        $this.ColumnIndex = $indexes.ColumnIndex
        if ($UseBib) {
            $this.Book.BibpaperIndex = $indexes.BibpaperIndex
        }
    }

    [ReviewIndexItem] GetList([string]$Id) { return $this.ListIndex.Get($Id) }
    [ReviewIndexItem] GetTable([string]$Id) { return $this.TableIndex.Get($Id) }
    [ReviewIndexItem] GetEquation([string]$Id) { return $this.EquationIndex.Get($Id) }
    [ReviewIndexItem] GetFootnote([string]$Id) { return $this.FootnoteIndex.Get($Id) }
    [ReviewIndexItem] GetEndnote([string]$Id) { return $this.EndnoteIndex.Get($Id) }
    [ReviewIndexItem] GetHeadline([string]$Caption) { return $this.HeadlineIndex.Get($Caption) }
    [ReviewIndexItem] GetColumn([string]$Id) { return $this.ColumnIndex.Get($Id) }

    [ReviewIndexItem] GetImage([string]$Id) {
        if ($this.ImageIndex -and $this.ImageIndex.ContainsKey($Id)) { return $this.ImageIndex.Get($Id) }
        if ($this.IconIndex -and $this.IconIndex.ContainsKey($Id)) { return $this.IconIndex.Get($Id) }
        if ($this.NumberlessImageIndex -and $this.NumberlessImageIndex.ContainsKey($Id)) { return $this.NumberlessImageIndex.Get($Id) }
        return $this.IndepImageIndex.Get($Id)
    }

    # Mirrors BookUnit#bibpaper/#bibpaper_index: the bib index is book-wide (built from
    # bib.re by ReviewBookBase.GenerateIndexes), not per-chapter.
    [ReviewIndexItem] GetBibpaper([string]$Id) {
        if (-not $this.Book.BibExist()) {
            throw [ReviewFileNotFoundError]::new("no such bib file: $($this.Book.BibFile())")
        }
        return $this.Book.BibpaperIndex.Get($Id)
    }

    # Mirrors BookUnit#image_bound? -- truthy iff the image's resolved file path exists
    # (ReviewImageFinder.FindPath returns $null, not a throw, when nothing matches).
    [bool] ImageBound([string]$Id) {
        return $null -ne $this.GetImage($Id).Path()
    }

    [object] NextChapter() {
        return $this.Book.NextChapter($this)
    }

    [object] PrevChapter() {
        return $this.Book.PrevChapter($this)
    }
}
