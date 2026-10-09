# Port of review/lib/review/catalog.rb -- wraps the parsed catalog.yml hash.
#
# CHAPS entries come in two shapes: a bare string filename, or a single-key hashtable
# `{ partName: [chap1, chap2, ...] }` grouping chapters under a named part. Chaps()
# flattens both into a single ordered filename list; Parts()/PartsWithChaps() expose the
# grouping structure for Book::Base's part-building logic.

class ReviewCatalog {
    hidden [hashtable] $Yaml

    ReviewCatalog([hashtable]$Yaml) {
        $this.Yaml = if ($Yaml) { $Yaml } else { @{} }
    }

    static [ReviewCatalog] FromFile([string]$Path) {
        $parsed = [ReviewYamlLoader]::SafeLoadFile($Path)
        return [ReviewCatalog]::new($parsed)
    }

    [string[]] Predef() {
        if ($this.Yaml.ContainsKey('PREDEF') -and $this.Yaml['PREDEF']) {
            return @($this.Yaml['PREDEF'])
        }
        return @()
    }

    [string[]] Chaps() {
        if (-not $this.Yaml.ContainsKey('CHAPS') -or -not $this.Yaml['CHAPS']) {
            return @()
        }
        $result = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in @($this.Yaml['CHAPS'])) {
            if ($entry -is [string]) {
                $result.Add($entry)
            }
            elseif ($entry -is [hashtable]) {
                foreach ($v in $entry.Values) {
                    foreach ($item in @($v)) { $result.Add([string]$item) }
                }
            }
        }
        return $result.ToArray()
    }

    [string[]] Parts() {
        if (-not $this.Yaml.ContainsKey('CHAPS') -or -not $this.Yaml['CHAPS']) {
            return @()
        }
        $result = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in @($this.Yaml['CHAPS'])) {
            if ($entry -is [hashtable]) {
                foreach ($k in $entry.Keys) { $result.Add([string]$k) }
            }
        }
        return $result.ToArray()
    }

    # Returns the raw CHAPS list (strings and/or single-key hashtables), matching Ruby's
    # `@yaml['CHAPS'].flatten.compact` -- used by Book::Base's parse_chapters to walk
    # entries in original declaration order while still distinguishing part-groups from
    # bare chapter filenames.
    [object[]] PartsWithChaps() {
        if (-not $this.Yaml.ContainsKey('CHAPS') -or -not $this.Yaml['CHAPS']) {
            return @()
        }
        return @($this.Yaml['CHAPS'])
    }

    [string[]] Appendix() {
        if ($this.Yaml.ContainsKey('APPENDIX') -and $this.Yaml['APPENDIX']) {
            return @($this.Yaml['APPENDIX'])
        }
        return @()
    }

    [string[]] Postdef() {
        if ($this.Yaml.ContainsKey('POSTDEF') -and $this.Yaml['POSTDEF']) {
            return @($this.Yaml['POSTDEF'])
        }
        return @()
    }

    [void] Validate([ReviewConfigure]$Config, [string]$BaseDir) {
        $filenames = [System.Collections.Generic.List[string]]::new()
        $filenames.AddRange([string[]]$this.Predef())

        foreach ($chap in $this.PartsWithChaps()) {
            if ($chap -is [hashtable]) {
                foreach ($partKey in $chap.Keys) {
                    if ([System.IO.Path]::GetExtension($partKey) -eq '.re') {
                        $filenames.Add([string]$partKey)
                    }
                    foreach ($v in @($chap[$partKey])) { $filenames.Add([string]$v) }
                }
            }
            else {
                $filenames.Add([string]$chap)
            }
        }

        $filenames.AddRange([string[]]$this.Appendix())
        $filenames.AddRange([string[]]$this.Postdef())

        foreach ($filename in $filenames) {
            $contentDir = [string]$Config.Get('contentdir')
            $refile = [System.IO.Path]::GetFullPath((Join-Path $BaseDir (Join-Path $contentDir $filename)))
            if (-not (Test-Path -LiteralPath $refile -PathType Leaf)) {
                throw [ReviewFileNotFoundError]::new("file not found in catalog.yml: $refile")
            }
        }
    }
}
