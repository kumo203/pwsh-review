# Port of review/lib/review/book/image_finder.rb -- resolves a //image[id] block's `id`
# to an actual file by probing a fixed list of candidate paths x the configured
# image_types extensions, searching the directory tree under the book's imagedir.
#
# Design note: Ruby's ImageFinder globs relative to the AMBIENT CWD at compile time,
# which happens to equal the project basedir only by convention (`cd project && review-
# pdfmaker config.yml`). This port is invoked via an explicit -Path parameter from
# anywhere, so it globs using an ABSOLUTE basedir+imagedir combination for robustness --
# but still RETURNS the same relative-path strings ("images/chapid/id.ext") Ruby does,
# since that relative string is what gets embedded in the generated .tex and is only
# ever resolved later, relative to the (separate) build directory where images get
# copied to the same relative location for uplatex's own use.
class ReviewImageFinder {
    hidden [object] $Book
    hidden [string] $BaseDirImageDir   # imagedir, relative (e.g. "images")
    hidden [string] $ChapId
    hidden [string] $BuilderName
    hidden [System.Collections.Generic.List[hashtable]] $Entries

    ReviewImageFinder([object]$Chapter) {
        $this.Book = $Chapter.Book
        $this.BaseDirImageDir = $this.Book.ImageDir()
        $this.ChapId = $Chapter.Id()
        $this.BuilderName = [string]$this.Book.Config.Get('builder')
        $this.Entries = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($path in $this.DirEntries()) {
            $this.Entries.Add($this.EntryObject($path))
        }
    }

    hidden [hashtable] EntryObject([string]$Path) {
        $basename = $Path -replace '\.[^.]+$', ''
        $extMatch = [regex]::Match($Path, '\.[^.]+$')
        $downcase = if ($extMatch.Success) { $basename + $extMatch.Value.ToLowerInvariant() } else { $Path }
        return @{ Path = $Path; Basename = $basename; Downcase = $downcase }
    }

    hidden [string[]] DirEntries() {
        $absImageDir = Join-Path $this.Book.BaseDir $this.BaseDirImageDir
        if (-not (Test-Path -LiteralPath $absImageDir -PathType Container)) { return @() }
        $results = [System.Collections.Generic.List[string]]::new()
        Get-ChildItem -LiteralPath $absImageDir -Recurse -File | ForEach-Object {
            if ($_.Extension) {
                $rel = $_.FullName.Substring($absImageDir.Length).TrimStart('\', '/').Replace('\', '/')
                $results.Add("$($this.BaseDirImageDir)/$rel")
            }
        }
        return @($results | Sort-Object -Unique)
    }

    [void] AddEntry([string]$Path) {
        $p = $Path -replace '^\./', ''
        if (-not ($this.Entries | Where-Object { $_.Path -eq $p })) {
            $this.Entries.Add($this.EntryObject($p))
        }
    }

    [object] FindPath([string]$Id) {
        foreach ($target in $this.TargetList($Id)) {
            foreach ($ext in @($this.Book.ImageTypes())) {
                $wanted = "$target$ext"
                foreach ($entry in $this.Entries) {
                    if ($entry.Basename -eq $target -and $entry.Downcase -eq $wanted) {
                        return $entry.Path
                    }
                }
            }
        }
        return $null
    }

    hidden [string[]] TargetList([string]$Id) {
        $base = $this.BaseDirImageDir
        return @(
            "$base/$($this.BuilderName)/$($this.ChapId)/$Id",
            "$base/$($this.BuilderName)/$($this.ChapId)-$Id",
            "$base/$($this.BuilderName)/$Id",
            "$base/$($this.ChapId)/$Id",
            "$base/$($this.ChapId)-$Id",
            "$base/$Id"
        )
    }
}
