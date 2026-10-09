# Port of review/lib/review/book/base.rb -- the "project" object: basedir + config,
# parses catalog.yml, lazily builds the Parts/Chapters tree, and drives generate_indexes.
#
# Non-goal (see plan): the legacy flat-file catalog format (PREDEF/CHAPS/PART/POSTDEF as
# plain text files, used when no catalog.yml exists) is not implemented -- ReadChaps() and
# friends throw a clear error in that branch rather than silently behaving differently.
# review-ext.rb (arbitrary Ruby extension loading) is likewise not supported; if present,
# a warning is emitted so the gap is visible rather than silent.

class ReviewBookBase {
    [ReviewConfigure] $Config
    [string] $BaseDir
    [ReviewCatalog] $Catalog
    [ReviewBibpaperIndex] $BibpaperIndex

    hidden [object[]] $PartsCache = $null
    hidden [ReviewChapterIndex] $ChapterIndexCache = $null

    ReviewBookBase([string]$BaseDir, [ReviewConfigure]$Config) {
        $this.BaseDir = $BaseDir
        $this.Config = if ($Config) { $Config } else { [ReviewConfigure]::Values() }
        $this.Catalog = $null

        $catalogFileName = [string]$this.Config.Get('catalogfile')
        $catalogPath = Join-Path $this.BaseDir $catalogFileName
        if ($catalogFileName -and (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            $this.ParseCatalogFile($catalogPath)
        }

        $extPath = Join-Path $this.BaseDir 'review-ext.rb'
        if (Test-Path -LiteralPath $extPath -PathType Leaf) {
            Write-Warning 'review-ext.rb was found but is not supported by this PowerShell port; ignoring.'
        }
    }

    [void] ParseCatalogFile([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw [ReviewFileNotFoundError]::new("catalog.yml is not found $Path")
        }
        $this.Catalog = [ReviewCatalog]::FromFile($Path)
        $this.Catalog.Validate($this.Config, $this.BaseDir)
    }

    [string] Ext() { return [string]$this.Config.Get('ext') }
    [string] BibFile() { return [string]$this.Config.Get('bib_file') }
    [string] ImageDir() { return [string]$this.Config.Get('imagedir') }
    [string[]] ImageTypes() { return @($this.Config.Get('image_types')) }

    [string] ContentDir() {
        $cd = [string]$this.Config.Get('contentdir')
        if ((-not $cd) -or $cd -eq '.') {
            return $this.BaseDir
        }
        return Join-Path $this.BaseDir $cd
    }

    [string[]] ReadChaps() {
        if ($this.Catalog) { return $this.Catalog.Chaps() }
        throw [ReviewApplicationError]::new('legacy CHAPS flat-file catalogs are not supported by this port; use catalog.yml.')
    }

    [string[]] ReadPredef() {
        if ($this.Catalog) { return $this.Catalog.Predef() }
        throw [ReviewApplicationError]::new('legacy PREDEF flat-file catalogs are not supported by this port; use catalog.yml.')
    }

    [string[]] ReadAppendix() {
        if ($this.Catalog) { return $this.Catalog.Appendix() }
        throw [ReviewApplicationError]::new('legacy APPENDIX flat-file catalogs are not supported by this port; use catalog.yml.')
    }

    [string[]] ReadPostdef() {
        if ($this.Catalog) { return $this.Catalog.Postdef() }
        throw [ReviewApplicationError]::new('legacy POSTDEF flat-file catalogs are not supported by this port; use catalog.yml.')
    }

    [string[]] ReadPart() {
        if ($this.Catalog) { return $this.Catalog.Parts() }
        throw [ReviewApplicationError]::new('legacy PART flat-file catalogs are not supported by this port; use catalog.yml.')
    }

    [bool] PartExist() {
        if ($this.Catalog) { return $this.Catalog.Parts().Count -gt 0 }
        return $false
    }

    [bool] BibExist() {
        return Test-Path -LiteralPath (Join-Path $this.ContentDir() $this.BibFile()) -PathType Leaf
    }

    [object[]] Parts() {
        if ($null -eq $this.PartsCache) {
            $this.PartsCache = $this.ReadParts()
        }
        return $this.PartsCache
    }

    [object[]] Chapters() {
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($part in $this.Parts()) {
            foreach ($c in $part.Chapters) { $result.Add($c) }
        }
        return $result.ToArray()
    }

    [void] EachChapter([scriptblock]$Action) {
        foreach ($c in $this.Chapters()) { & $Action $c }
    }

    [object] NextChapter([object]$Chapter) {
        $found = $false
        foreach ($c in $this.Chapters()) {
            if ($found) { return $c }
            if ($c -eq $Chapter) { $found = $true }
        }
        return $null
    }

    [object] PrevChapter([object]$Chapter) {
        $chapters = $this.Chapters()
        $found = $false
        for ($i = $chapters.Count - 1; $i -ge 0; $i--) {
            if ($found) { return $chapters[$i] }
            if ($chapters[$i] -eq $Chapter) { $found = $true }
        }
        return $null
    }

    [ReviewChapterIndex] CreateChapterIndex() {
        $index = [ReviewChapterIndex]::new()
        foreach ($chap in $this.Chapters()) {
            $index.AddItem([ReviewIndexItem]::new($chap.Id(), $chap.Number, $chap))
        }
        foreach ($part in $this.Parts()) {
            if ($part.Id()) {
                $index.AddItem([ReviewIndexItem]::new($part.Id(), $part.Number, $part))
            }
        }
        return $index
    }

    [ReviewChapterIndex] ChapterIndexValue() {
        if ($null -eq $this.ChapterIndexCache) {
            $this.ChapterIndexCache = $this.CreateChapterIndex()
        }
        return $this.ChapterIndexCache
    }

    [object] Chapter([string]$Id) {
        return $this.ChapterIndexValue().Get($Id).Content()
    }

    [void] GenerateIndexes() {
        if ($this.BibExist()) {
            # Bib (bibliography) support is deferred -- see plan non-goals; bibpaper_index
            # stays empty rather than being populated from bib.re for v1.
            $this.BibpaperIndex = [ReviewBibpaperIndex]::new()
        }
        foreach ($chap in $this.Chapters()) { $chap.GenerateIndexes($true) }
        foreach ($part in $this.Parts()) { $part.GenerateIndexes($false) }
        $this.ChapterIndexCache = $this.CreateChapterIndex()
    }

    hidden [object[]] ReadParts() {
        $list = [System.Collections.Generic.List[object]]::new()
        $list.AddRange([object[]]$this.ParseChapters())

        $pre = $this.Prefaces()
        if ($pre) { $list.Insert(0, $pre) }

        $app = $this.AppendixPart()
        if ($app) { $list.Add($app) }

        $post = $this.Postscripts()
        if ($post) { $list.Add($post) }

        return $list.ToArray()
    }

    hidden [object] Prefaces() {
        if ($this.Catalog) {
            return [ReviewPart]::MkPartFromNameList($this, $this.Catalog.Predef())
        }
        return $null
    }

    hidden [object] AppendixPart() {
        if ($this.Catalog) {
            $names = $this.Catalog.Appendix()
            $chaps = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $names.Count; $i++) {
                $c = [ReviewChapter]::MkChapIfExist($this, $names[$i], $i + 1)
                if ($c) { $chaps.Add($c) }
            }
            return [ReviewPart]::MkPart($chaps.ToArray())
        }
        return $null
    }

    hidden [object] Postscripts() {
        if ($this.Catalog) {
            return [ReviewPart]::MkPartFromNameList($this, $this.Catalog.Postdef())
        }
        return $null
    }

    hidden [object[]] ParseChapters() {
        if (-not $this.Catalog) {
            throw [ReviewApplicationError]::new('legacy chapter catalogs are not supported by this port; use catalog.yml.')
        }

        $result = [System.Collections.Generic.List[object]]::new()
        $part = 0
        $num = 0

        foreach ($entry in $this.Catalog.PartsWithChaps()) {
            if ($entry -is [hashtable]) {
                $partName = @($entry.Keys)[0]
                $chapNames = @($entry[$partName])
                $chaps = [System.Collections.Generic.List[object]]::new()
                foreach ($chapName in $chapNames) {
                    $num++
                    $chaps.Add([ReviewChapter]::new($this, $num, $chapName, (Join-Path $this.ContentDir() $chapName)))
                }
                $part++
                $readPart = $this.ReadPart()
                $partFileName = if ($readPart.Count -ge $part) { $readPart[$part - 1] } else { '' }
                $result.Add([ReviewPart]::new($this, $part, $chaps.ToArray(), $partFileName))
            }
            else {
                $num++
                $chap = [ReviewChapter]::new($this, $num, $entry, (Join-Path $this.ContentDir() $entry))
                if ($null -ne $chap.Number) {
                    $num = $chap.Number
                }
                else {
                    $num--
                }
                $result.Add([ReviewPart]::new($this, $null, @($chap), ''))
            }
        }

        return $result.ToArray()
    }
}
