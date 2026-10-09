# Port of review/lib/review/latexutils.rb's LaTeXUtils module.
#
# Ruby mixes this in via `include LaTeXUtils` (into both LATEXBuilder and PDFMaker). This
# port uses composition instead (see the "no mixins" mitigation in the project README):
# ReviewLATEXBuilder holds a [ReviewLaTeXEscaper] $Escaper property and delegates.
#
# Gap (documented, not silently dropped): Ruby's initialize_metachars adds a platex-only
# half-width-katakana -> \aj半角{...} escape table built via NKF.nkf('-WwX', char)
# (JIS X 0208 byte conversion). This port implements the platex-only circled-number
# escapes (⓪-⑯, literal characters, no conversion needed) but NOT the half-width-katakana
# table, since replicating NKF's JIS X 0208 conversion would need a full Shift-JIS/EUC-JP
# codec table port. This only affects platex (not the default uplatex) and only when a
# manuscript contains half-width katakana -- a real but narrow gap.

class ReviewLaTeXEscaper {
    hidden [System.Collections.Generic.Dictionary[string, string]] $MetaChars
    hidden [regex] $MetaCharsRegex
    hidden [System.Collections.Generic.Dictionary[string, string]] $MetaCharsInvert

    ReviewLaTeXEscaper([string]$TexCommand) {
        $this.InitializeMetachars($TexCommand)
    }

    [void] InitializeMetachars([string]$TexCommand) {
        $this.MetaChars = [System.Collections.Generic.Dictionary[string, string]]::new()
        $this.MetaChars['#'] = '\#'
        $this.MetaChars['$'] = '\textdollar{}'
        $this.MetaChars['%'] = '\%'
        $this.MetaChars['&'] = '\&'
        $this.MetaChars['{'] = '\{'
        $this.MetaChars['}'] = '\}'
        $this.MetaChars['_'] = '\textunderscore{}'
        $this.MetaChars['^'] = '\textasciicircum{}'
        $this.MetaChars['~'] = '\textasciitilde{}'
        $this.MetaChars['|'] = '\textbar{}'
        $this.MetaChars['<'] = '\textless{}'
        $this.MetaChars['>'] = '\textgreater{}'
        $this.MetaChars['\'] = '\reviewbackslash{}'
        $this.MetaChars['-'] = '{-}'

        $texBase = [System.IO.Path]::GetFileNameWithoutExtension($TexCommand)
        if ($texBase -eq 'platex') {
            $circled = @{
                '⓪' = '\UTF{24EA}'; '①' = '\UTF{2460}'; '②' = '\UTF{2461}'; '③' = '\UTF{2462}'
                '④' = '\UTF{2463}'; '⑤' = '\UTF{2464}'; '⑥' = '\UTF{2465}'; '⑦' = '\UTF{2466}'
                '⑧' = '\UTF{2467}'; '⑨' = '\UTF{2468}'; '⑩' = '\UTF{2469}'; '⑪' = '\UTF{246A}'
                '⑫' = '\UTF{246B}'; '⑬' = '\UTF{246C}'; '⑭' = '\UTF{246D}'; '⑮' = '\UTF{246E}'
                '⑯' = '\UTF{246F}'
            }
            foreach ($k in $circled.Keys) { $this.MetaChars[$k] = $circled[$k] }
            # Half-width katakana escaping (platex-only) is a documented gap -- see file header.
        }

        $escapedChars = ($this.MetaChars.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $this.MetaCharsRegex = [regex]::new($escapedChars)

        $this.MetaCharsInvert = [System.Collections.Generic.Dictionary[string, string]]::new()
        foreach ($k in $this.MetaChars.Keys) { $this.MetaCharsInvert[$this.MetaChars[$k]] = $k }
    }

    [string] Escape([string]$Str) {
        if ($null -eq $Str) { return $Str }
        return $this.MetaCharsRegex.Replace($Str, { param($m) $this.MetaChars[$m.Value] })
    }

    [string] Unescape([string]$Str) {
        if ($null -eq $Str) { return $Str }
        $pattern = ($this.MetaCharsInvert.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $re = [regex]::new($pattern)
        return $re.Replace($Str, { param($m) $this.MetaCharsInvert[$m.Value] })
    }

    [string] EscapeIndex([string]$Str) {
        if ($null -eq $Str) { return $Str }
        return [regex]::Replace($Str, '[@!|"]', { param($m) '"' + $m.Value })
    }

    [string] EscapeMendexKey([string]$Str) {
        if ($null -eq $Str) { return $Str }
        return $Str.Replace('"|', '｜').Replace('{', '｛').Replace('}', '｝')
    }

    [string] EscapeMendexDisplay([string]$Str) {
        if ($null -eq $Str) { return $Str }
        return $Str.Replace('\{', '\reviewleftcurlybrace{}').Replace('\}', '\reviewrightcurlybrace{}')
    }

    [string] EscapeUrl([string]$Str) {
        if ($null -eq $Str) { return $Str }
        return [regex]::Replace($Str, '[#%]', { param($m) '\' + $m.Value })
    }

    # Named MacroArgs, not Args: see the project-wide $Args-parameter-collision note in
    # 13.Compiler.ps1's CheckArgs method -- it bit this method too (macro output was
    # silently missing all {...} argument braces until this rename).
    [string] Macro([string]$Name, [string[]]$MacroArgs) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append('\').Append($Name)
        foreach ($a in $MacroArgs) { [void]$sb.Append('{').Append($a).Append('}') }
        return $sb.ToString()
    }
}
