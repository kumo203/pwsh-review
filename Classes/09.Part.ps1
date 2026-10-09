# Port of review/lib/review/book/part.rb.

class ReviewPart : ReviewBookUnit {
    [Nullable[int]] $Number
    [object[]] $Chapters

    static [ReviewPart] MkPartFromNameListFile([object]$Book, [string]$Path) {
        $chaps = [System.Collections.Generic.List[object]]::new()
        $names = (Get-Content -LiteralPath $Path -Raw -Encoding utf8) -split '\s+' | Where-Object { $_ }
        $isPredef = $Path -match 'PREDEF'
        $i = 0
        foreach ($name in $names) {
            if ($isPredef) {
                $chaps.Add([ReviewChapter]::MkChap($Book, $name, $null))
            }
            else {
                $i++
                $chaps.Add([ReviewChapter]::MkChap($Book, $name, $i))
            }
        }
        return [ReviewPart]::MkPart($chaps.ToArray())
    }

    static [ReviewPart] MkPartFromNameList([object]$Book, [string[]]$Names) {
        $chaps = [System.Collections.Generic.List[object]]::new()
        foreach ($name in $Names) {
            $c = [ReviewChapter]::MkChapIfExist($Book, $name, $null)
            if ($c) { $chaps.Add($c) }
        }
        return [ReviewPart]::MkPart($chaps.ToArray())
    }

    static [ReviewPart] MkPart([object[]]$Chaps) {
        if (-not $Chaps -or $Chaps.Count -eq 0) { return $null }
        return [ReviewPart]::new($Chaps[0].Book, $null, $Chaps, '')
    }

    ReviewPart([object]$Book, [Nullable[int]]$Number, [object[]]$Chapters, [string]$Name) {
        $this.Book = $Book
        $this.Number = $Number
        $this.Name = $Name
        $this.Chapters = $Chapters
        $this.Path = $Name

        if ($Name -and (Test-Path -LiteralPath (Join-Path $Book.ContentDir() $Name) -PathType Leaf)) {
            $this.Content = Get-Content -LiteralPath (Join-Path $Book.ContentDir() $Name) -Raw -Encoding utf8
            $this.Name = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        }
        else {
            $this.Content = ''
        }

        if ($this.FileFlag()) {
            $this.TitleValue = $null
        }
        else {
            $this.TitleValue = $Name
        }
    }

    # Mirrors Part#generate_indexes -- see the matching note in 08.Chapter.ps1.
    [void] GenerateIndexes([bool]$UseBib) {
        ([ReviewBookUnit]$this).GenerateIndexes($UseBib)
        if (-not $this.Content) { return }
        $indexes = $this.ExecuteIndexer($false)
        $this.NumberlessImageIndex = $indexes.NumberlessImageIndex
        $this.ImageIndex = $indexes.ImageIndex
        $this.IconIndex = $indexes.IconIndex
        $this.IndepImageIndex = $indexes.IndepImageIndex
    }

    [bool] FileFlag() {
        return ($this.Name) -and ($this.Path) -and $this.Path.EndsWith('.re')
    }

    [void] EachChapter([scriptblock]$Action) {
        foreach ($c in $this.Chapters) { & $Action $c }
    }

    [string] FormatNumber([bool]$Heading) {
        if ($Heading) {
            return [ReviewI18n]::T('part', $this.Number)
        }
        return [string]$this.Number
    }

    [string] FormatNumber() {
        return $this.FormatNumber($true)
    }

    [bool] OnAppendix() { return $false }

    [bool] IsPart() { return $true }
}
