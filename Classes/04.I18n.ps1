# Port of review/lib/review/i18n.rb. Locale data is loaded from Resources/i18n/i18n.yml
# (a verbatim copy of review/lib/review/i18n.yml) at ::Setup() time, plus an optional
# project-local locale.yml merged on top (mirrors ReVIEW::I18n.setup(locale, ymlfile)).
#
# Ruby's #t does Kernel#sprintf-style '%s'/'%d' substitution after first resolving the
# custom positional tokens (%pA, %pR, %pJ, ...) against fixed numbering-system lookup
# tables (alphabetic/roman/kanji page-numbering styles used by 'part'/'appendix' locale
# strings). This port replicates both passes.

class ReviewI18n {
    static [string[]] $AlphaU = @('0', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
    static [string[]] $AlphaL = @('0', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
    static [string[]] $RomanU = @('0', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI', 'XVII', 'XVIII', 'XIX', 'XX', 'XXI', 'XXII', 'XXIII', 'XXIV', 'XXV', 'XXVI', 'XXVII')
    static [string[]] $RomanL = @('0', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x', 'xi', 'xii', 'xiii', 'xiv', 'xv', 'xvi', 'xvii', 'xviii', 'xix', 'xx', 'xxi', 'xxii', 'xxiii', 'xxiv', 'xxv', 'xxvi', 'xxvii')
    static [string[]] $AlphaUW = @('０', 'Ａ', 'Ｂ', 'Ｃ', 'Ｄ', 'Ｅ', 'Ｆ', 'Ｇ', 'Ｈ', 'Ｉ', 'Ｊ', 'Ｋ', 'Ｌ', 'Ｍ', 'Ｎ', 'Ｏ', 'Ｐ', 'Ｑ', 'Ｒ', 'Ｓ', 'Ｔ', 'Ｕ', 'Ｖ', 'Ｗ', 'Ｘ', 'Ｙ', 'Ｚ')
    static [string[]] $AlphaLW = @('０', 'ａ', 'ｂ', 'ｃ', 'ｄ', 'ｅ', 'ｆ', 'ｇ', 'ｈ', 'ｉ', 'ｊ', 'ｋ', 'ｌ', 'ｍ', 'ｎ', 'ｏ', 'ｐ', 'ｑ', 'ｒ', 'ｓ', 'ｔ', 'ｕ', 'ｖ', 'ｗ', 'ｘ', 'ｙ', 'ｚ')
    static [string[]] $RomanUW = @('０', 'Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ｖ', 'Ⅵ', 'Ⅶ', 'Ⅷ', 'Ⅸ', 'Ｘ', 'Ⅺ', 'Ⅻ')
    static [string[]] $ArabicUW = @('〇', '１', '２', '３', '４', '５', '６', '７', '８', '９', '１０', '１１', '１２', '１３', '１４', '１５', '１６', '１７', '１８', '１９', '２０', '２１', '２２', '２３', '２４', '２５', '２６', '２７')
    static [string[]] $ArabicLW = @('〇', '１', '２', '３', '４', '５', '６', '７', '８', '９', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27')
    static [string[]] $Japan = @('〇', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十', '二十一', '二十二', '二十三', '二十四', '二十五', '二十六', '二十七')

    static [ReviewI18n] $Instance = $null

    # Minimal Ruby Time#strftime-subset, covering only the directives actually used by
    # i18n.yml's 'date_format' strings across locales ('%Y年%-m月%-d日' for ja/zh,
    # '%b. %e, %Y' for en): %Y (4-digit year), %m/%-m (zero-padded/unpadded month),
    # %d/%-d (zero-padded/unpadded day), %b (abbreviated month name), %e (day,
    # space-padded to 2 chars). Anything else passes through literally.
    static [string] Strftime([datetime]$Date, [string]$Format) {
        $sb = [System.Text.StringBuilder]::new()
        $i = 0
        while ($i -lt $Format.Length) {
            if ($Format[$i] -eq '%' -and ($i + 1) -lt $Format.Length) {
                $rest = $Format.Substring($i + 1)
                if ($rest.StartsWith('-m')) { [void]$sb.Append([string]$Date.Month); $i += 3; continue }
                if ($rest.StartsWith('-d')) { [void]$sb.Append([string]$Date.Day); $i += 3; continue }
                if ($rest.StartsWith('Y')) { [void]$sb.Append($Date.ToString('yyyy')); $i += 2; continue }
                if ($rest.StartsWith('m')) { [void]$sb.Append($Date.ToString('MM')); $i += 2; continue }
                if ($rest.StartsWith('d')) { [void]$sb.Append($Date.ToString('dd')); $i += 2; continue }
                if ($rest.StartsWith('b')) { [void]$sb.Append($Date.ToString('MMM', [System.Globalization.CultureInfo]::InvariantCulture)); $i += 2; continue }
                if ($rest.StartsWith('e')) { [void]$sb.Append($Date.Day.ToString().PadLeft(2)); $i += 2; continue }
            }
            [void]$sb.Append($Format[$i])
            $i++
        }
        return $sb.ToString()
    }

    [string] $Locale
    [hashtable] $Store

    ReviewI18n([string]$Locale) {
        $this.Locale = $Locale
        $defaultPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Resources\i18n\i18n.yml'
        if (-not (Test-Path -LiteralPath $defaultPath)) {
            $defaultPath = Join-Path $PSScriptRoot '..\Resources\i18n\i18n.yml'
        }
        $this.Store = [ReviewYamlLoader]::SafeLoadFile($defaultPath)
    }

    static [void] Setup([string]$Locale) {
        [ReviewI18n]::Setup($Locale, $null)
    }

    static [void] Setup([string]$Locale, [string]$LocaleYmlPath) {
        $newInst = [ReviewI18n]::new($Locale)
        if ($LocaleYmlPath -and (Test-Path -LiteralPath $LocaleYmlPath -PathType Leaf)) {
            $newInst.UpdateLocaleFile($LocaleYmlPath)
        }
        [ReviewI18n]::Instance = $newInst
    }

    [void] UpdateLocaleFile([string]$Path) {
        $userI18n = [ReviewYamlLoader]::SafeLoadFile($Path)
        if ($null -eq $userI18n) { return }

        if ($userI18n.ContainsKey('locale')) {
            $loc = [string]$userI18n['locale']
            $userI18n.Remove('locale')
            if ($this.Store.ContainsKey($loc)) {
                foreach ($k in $userI18n.Keys) { $this.Store[$loc][$k] = $userI18n[$k] }
            }
            else {
                $this.Store[$loc] = $userI18n
            }
        }
        else {
            foreach ($loc in $userI18n.Keys) {
                $values = $userI18n[$loc]
                if ($values -isnot [hashtable]) {
                    throw [ReviewKeyError]::new("Invalid locale file: $Path")
                }
                if (-not $this.Store.ContainsKey($loc)) { $this.Store[$loc] = @{} }
                foreach ($k in $values.Keys) { $this.Store[$loc][$k] = $values[$k] }
            }
        }
    }

    static [string] T([string]$Str) {
        return [ReviewI18n]::Instance.Translate($Str, $null)
    }

    static [string] T([string]$Str, [object]$FormatArgs) {
        return [ReviewI18n]::Instance.Translate($Str, $FormatArgs)
    }

    [object] Get([string]$Word) {
        if (-not $this.Store.ContainsKey($this.Locale)) { return $null }
        $localeStore = $this.Store[$this.Locale]
        if ($localeStore.ContainsKey($Word)) { return $localeStore[$Word] }
        return $null
    }

    [void] SetWord([string]$Word, [string]$Str) {
        if (-not $this.Store.ContainsKey($this.Locale)) { $this.Store[$this.Locale] = @{} }
        $this.Store[$this.Locale][$Word] = $Str
    }

    [string] Translate([string]$Str, [object]$FormatArgs) {
        $raw = $this.Get($Str)
        if ($null -eq $raw) { return $Str }

        $frmt = [string]$raw
        $frmt = $frmt.Replace('%%', '##')

        if ($FormatArgs -is [System.Collections.IList]) {
            $argList = [System.Collections.Generic.List[object]]::new()
            $argList.AddRange([object[]]$FormatArgs)
        }
        elseif ($null -eq $FormatArgs -and $frmt -notmatch '%') {
            $argList = [System.Collections.Generic.List[object]]::new()
        }
        else {
            $argList = [System.Collections.Generic.List[object]]::new()
            $argList.Add($FormatArgs)
        }

        $percentTokenPattern = [regex]::new('%[A-Za-z]{1,3}')
        $tokenMatches = $percentTokenPattern.Matches($frmt)   # not $matches: that shadows the automatic $Matches
        $removeIdx = [System.Collections.Generic.List[int]]::new()

        for ($idx = 0; $idx -lt $tokenMatches.Count; $idx++) {
            $tok = $tokenMatches[$idx].Value
            # -CaseSensitive is essential: PowerShell's switch is case-INsensitive by
            # default AND runs every matching clause, so '%pA' also matched the '%pa'
            # clause (last one wins), rendering 付録A as 付録a and 第II部 as 第ii部.
            $table = switch -CaseSensitive ($tok) {
                '%pA' { [ReviewI18n]::AlphaU; break }
                '%pa' { [ReviewI18n]::AlphaL; break }
                '%pAW' { [ReviewI18n]::AlphaUW; break }
                '%paW' { [ReviewI18n]::AlphaLW; break }
                '%pR' { [ReviewI18n]::RomanU; break }
                '%pr' { [ReviewI18n]::RomanL; break }
                '%pRW' { [ReviewI18n]::RomanUW; break }
                '%pJ' { [ReviewI18n]::Japan; break }
                '%pdW' { [ReviewI18n]::ArabicLW; break }
                '%pDW' { [ReviewI18n]::ArabicUW; break }
                default { $null }
            }
            if ($null -ne $table -and $idx -lt $argList.Count) {
                $n = [int]$argList[$idx]
                $frmt = [ReviewI18n]::ReplaceFirst($frmt, $tok, $table[$n])
                $removeIdx.Add($idx)
            }
        }

        for ($i = $removeIdx.Count - 1; $i -ge 0; $i--) {
            $argList.RemoveAt($removeIdx[$i])
        }

        # Matches Ruby exactly: args_matched is computed on frmt.count('%') -- a literal
        # count of '%' characters still present at this point (almost always zero, since
        # the real %% was replaced with ## earlier and any %pA-style tokens were already
        # consumed above) -- BEFORE the ## -> %% restore on the next line. Getting this
        # order/criterion wrong (e.g. counting %s/%d/%% token matches post-restore, as an
        # earlier version of this file did) silently breaks any locale string containing
        # a literal %% escape with no real substitution args, such as 'date_format'
        # ('%%Y年%%-m月%%-d日'), which must pass through unprocessed-looking but still
        # %%-unescaped via Sprintf.
        $percentCharCount = ($frmt.ToCharArray() | Where-Object { $_ -eq '%' }).Count
        $argsMatched = $percentCharCount -le $argList.Count

        $frmt = $frmt.Replace('##', '%%')
        if ($argsMatched) {
            return [ReviewI18n]::Sprintf($frmt, $argList.ToArray())
        }
        return $frmt
    }

    hidden static [string] ReplaceFirst([string]$Haystack, [string]$Needle, [string]$Replacement) {
        $i = $Haystack.IndexOf($Needle)
        if ($i -lt 0) { return $Haystack }
        return $Haystack.Substring(0, $i) + $Replacement + $Haystack.Substring($i + $Needle.Length)
    }

    # Minimal Kernel#sprintf-equivalent: substitutes %s/%d tokens in order with Args,
    # leaving a literal %% as a single %. Sufficient for Re:VIEW's locale strings, which
    # never use width/precision specifiers.
    hidden static [string] Sprintf([string]$Format, [object[]]$FormatArgs) {
        $sb = [System.Text.StringBuilder]::new()
        $argIdx = 0
        $i = 0
        while ($i -lt $Format.Length) {
            $ch = $Format[$i]
            if ($ch -eq '%' -and ($i + 1) -lt $Format.Length) {
                $next = $Format[$i + 1]
                if ($next -eq '%') {
                    [void]$sb.Append('%')
                    $i += 2
                    continue
                }
                elseif ($next -eq 's' -or $next -eq 'd') {
                    $value = if ($argIdx -lt $FormatArgs.Count) { $FormatArgs[$argIdx] } else { $null }
                    $argIdx++
                    [void]$sb.Append([string]$value)
                    $i += 2
                    continue
                }
            }
            [void]$sb.Append($ch)
            $i++
        }
        return $sb.ToString()
    }
}
