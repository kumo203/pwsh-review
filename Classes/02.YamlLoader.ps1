# Port of review/lib/review/yamlloader.rb — YAML loading plus the `inherit: [a.yml, b.yml]`
# chain-merge semantics: 7.yml inheriting [3.yml, 6.yml] (which may itself inherit further)
# yields precedence 7 > 6 > 5 > 4 > 3 > ... (the file closer to the original wins).
#
# Requires the `powershell-yaml` module (ConvertFrom-Yaml) -- declared in PwshReview.psd1's
# RequiredModules.
#
# Deviation from Ruby (faithfully preserved, not "fixed"): parse_inherit resolves each
# inherited file's relative path against the *original* top-level yamlfile's directory,
# not the directory of the file that declared the `inherit:` key. This only matters when
# inherited YAML files live in a different directory than the file that inherits them.

class ReviewYamlLoader {
    static [object] SafeLoad([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        return (ConvertFrom-Yaml -Yaml $Text)
    }

    static [object] SafeLoadFile([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw [ReviewFileNotFoundError]::new("file not found: $Path")
        }
        $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        return [ReviewYamlLoader]::SafeLoad($text)
    }

    # mirrors ActiveSupport's Hash#deep_merge: Base.deep_merge(Override) -> Override wins
    # on key conflicts; nested hashtables recurse, everything else (including arrays) is
    # replaced wholesale by Override's value.
    static [hashtable] DeepMerge([hashtable]$Base, [hashtable]$Override) {
        $result = @{}
        foreach ($key in $Base.Keys) { $result[$key] = $Base[$key] }
        foreach ($key in $Override.Keys) {
            if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
                $result[$key] = [ReviewYamlLoader]::DeepMerge($result[$key], $Override[$key])
            }
            else {
                $result[$key] = $Override[$key]
            }
        }
        return $result
    }

    [hashtable] LoadFile([string]$YamlFile) {
        $yamlFileFull = [System.IO.Path]::GetFullPath($YamlFile)
        $fileQueue = [System.Collections.Generic.List[string]]::new()
        $fileQueue.Add($yamlFileFull)
        $loadedFiles = @{}
        $yaml = @{}

        while ($fileQueue.Count -gt 0) {
            $currentFile = $fileQueue[0]
            $fileQueue.RemoveAt(0)

            $currentYaml = [ReviewYamlLoader]::SafeLoadFile($currentFile)
            if ($null -eq $currentYaml -or ($currentYaml -is [bool] -and $currentYaml -eq $false)) {
                throw [ReviewApplicationError]::new("$(Split-Path -Leaf $currentFile) is malformed.")
            }

            $yaml = [ReviewYamlLoader]::DeepMerge($currentYaml, $yaml)

            if ($yaml.ContainsKey('inherit')) {
                $inheritFiles = $this.ParseInherit($yaml, $yamlFileFull, $loadedFiles)
                $newQueue = [System.Collections.Generic.List[string]]::new()
                $newQueue.AddRange([string[]]$inheritFiles)
                $newQueue.AddRange($fileQueue)
                $fileQueue = $newQueue
            }
        }

        return $yaml
    }

    hidden [string[]] ParseInherit([hashtable]$Yaml, [string]$YamlFile, [hashtable]$LoadedFiles) {
        $files = [System.Collections.Generic.List[string]]::new()
        $inheritList = @($Yaml['inherit'])
        $baseDir = Split-Path -Parent $YamlFile

        for ($i = $inheritList.Count - 1; $i -ge 0; $i--) {
            $item = $inheritList[$i]
            $inheritFile = [System.IO.Path]::GetFullPath((Join-Path $baseDir $item))

            if ($LoadedFiles.ContainsKey($inheritFile)) {
                throw [ReviewApplicationError]::new("Found circular YAML inheritance '$inheritFile' in $YamlFile.")
            }
            $LoadedFiles[$inheritFile] = $true
            $files.Add($inheritFile)
        }

        $Yaml.Remove('inherit')
        return $files.ToArray()
    }
}
