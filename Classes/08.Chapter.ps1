# Port of review/lib/review/book/chapter.rb.

class ReviewChapter : ReviewBookUnit {
    [Nullable[int]] $Number

    static [ReviewChapter] MkChap([object]$Book, [string]$Name, [Nullable[int]]$Number) {
        $name2 = $Name
        if (-not [System.IO.Path]::GetExtension($name2)) { $name2 = $name2 + $Book.Ext() }
        $path = Join-Path $Book.ContentDir() $name2
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw [ReviewFileNotFoundError]::new("file not exist: $path")
        }
        return [ReviewChapter]::new($Book, $Number, $name2, $path)
    }

    static [ReviewChapter] MkChapIfExist([object]$Book, [string]$Name, [Nullable[int]]$Number) {
        $name2 = $Name
        if (-not [System.IO.Path]::GetExtension($name2)) { $name2 = $name2 + $Book.Ext() }
        $path = Join-Path $Book.ContentDir() $name2
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return [ReviewChapter]::new($Book, $Number, $name2, $path)
        }
        return $null
    }

    ReviewChapter([object]$Book, [Nullable[int]]$Number, [string]$Name, [string]$Path) {
        $this.Book = $Book
        $this.Number = $Number
        $this.Name = $Name
        $this.Path = $Path
        $this.Content = $null

        if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $this.Content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
            $opt = $this.FindFirstHeaderOption()
            if ($opt -in @('nonum', 'nodisp', 'notoc')) {
                $this.Number = $null
            }
        }
    }

    # Mirrors Chapter#generate_indexes: calls the base pass, then additionally pulls the
    # image-family indexes off the (cached) IndexBuilder result -- these aren't set by
    # the base BookUnit.GenerateIndexes() since Ruby's book_unit.rb doesn't set them
    # either (only Chapter's and Part's own overrides do).
    [void] GenerateIndexes([bool]$UseBib) {
        ([ReviewBookUnit]$this).GenerateIndexes($UseBib)
        if (-not $this.Content) { return }
        $indexes = $this.ExecuteIndexer($false)
        $this.NumberlessImageIndex = $indexes.NumberlessImageIndex
        $this.ImageIndex = $indexes.ImageIndex
        $this.IconIndex = $indexes.IconIndex
        $this.IndepImageIndex = $indexes.IndepImageIndex
    }

    [object] FindFirstHeaderOption() {
        $f = [ReviewLineInput]::FromString($this.Content)
        while ($f.Next()) {
            $peeked = $f.Peek()
            if ($peeked -match '^=+[\[\s{]') {
                $line = $f.Gets()
                if ($line -match '^(=+)(?:\[(.+?)\])?(?:\{(.+?)\})?(.*)') {
                    return $Matches[2]
                }
                return $null
            }
            elseif ($peeked -match '^//[a-z]+/') {
                $line = $f.Gets()
                if ($line.TrimEnd().Substring($line.TrimEnd().Length - 1) -eq '{') {
                    $f.UntilMatch([regex]::new('^//\}'), { return $false })
                }
            }
            $f.Gets()
        }
        return $null
    }

    [string] Inspect() {
        return "#<ReviewChapter $($this.Number) $($this.Path)>"
    }

    [string] FormatNumber([bool]$Heading) {
        if ($null -eq $this.Number) { return '' }

        if ($this.OnPredef()) {
            return [string]$this.Number
        }

        if ($this.OnAppendix()) {
            if ($this.Number -lt 1 -or $this.Number -gt 27) {
                return [string]$this.Number
            }
            if ($this.Book.Config.Get('appendix_format')) {
                throw [ReviewConfigError]::new("'appendix_format:' in config.yml is obsoleted.")
            }

            $i18nAppendix = [string][ReviewI18n]::Instance.Get('appendix')
            $fmtMatch = [regex]::Match($i18nAppendix, '%\w{1,3}')
            $fmt = if ($fmtMatch.Success) { $fmtMatch.Value } else { '%s' }
            [ReviewI18n]::Instance.SetWord('appendix_without_heading', $fmt)

            if ($Heading) {
                return [ReviewI18n]::T('appendix', $this.Number)
            }
            return [ReviewI18n]::T('appendix_without_heading', $this.Number)
        }

        if ($Heading) {
            return [ReviewI18n]::T('chapter', $this.Number)
        }
        return [string]$this.Number
    }

    [string] FormatNumber() {
        return $this.FormatNumber($true)
    }

    hidden [bool] OnFile([string[]]$Contents) {
        $target = "$($this.Id())$($this.Book.Ext())"
        foreach ($c in $Contents) {
            if ($c.Trim() -eq $target) { return $true }
        }
        return $false
    }

    [bool] OnChaps() { return $this.OnFile($this.Book.ReadChaps()) }
    [bool] OnPredef() { return $this.OnFile($this.Book.ReadPredef()) }
    [bool] OnAppendix() { return $this.OnFile($this.Book.ReadAppendix()) }
    [bool] OnPostdef() { return $this.OnFile($this.Book.ReadPostdef()) }

    [bool] IsPart() { return $false }
}
