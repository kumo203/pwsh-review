# A deliberately restricted ERB-subset interpreter, used only for PROJECT-LOCAL template
# overrides (<basedir>/layouts/layout.tex.erb, layouts/config-local.tex.erb, sty/*.erb).
# The two templates Re:VIEW itself bundles are hand-ported instead (Private/
# LatexTemplates.ps1). Anything outside the grammar below throws a clear
# "unsupported ERB construct" error rather than silently mis-rendering -- arbitrary Ruby
# is a documented non-goal, in the same category as review-ext.rb.
#
# Supported:
#   tags        <%= expr %>, <% stmt %>, <%- stmt -%> (ERB trim_mode '-'), <%# comment %>
#               (or trim_mode '>' for HTML/EPUB layouts, via the 3-argument constructor)
#   statements  if / elsif / else / unless / end,  EXPR.each do |x| ... end
#   expressions 'str', "str" (no interpolation), integers, nil/true/false,
#               @ivar, local vars, x[expr] chains, [a, b] array literals,
#               && || ! == != and parentheses,
#               .present? .blank? .nil? .empty? .to_s .to_i .size .length .first .last
#               .flatten .join(expr) .strip,
#               escape(expr), File.read(expr)
#   truthiness  Ruby rules: only nil and false are falsy ('' and 0 are TRUE).
#
# Bindings: a hashtable of names -> values ('@config' etc. include the '@'). A value that
# is a [scriptblock] is invoked when referenced as a bare identifier (e.g. latex_config).
# A ReviewConfigure value is indexed via .Get() so top-level @config['x'] lookups keep
# Configure#[]'s maker-shadowing semantics.

class ReviewErbNode {
    [string] $Kind          # text | output | if | each
    [string] $Text
    [string] $Expr
    [System.Collections.Generic.List[object]] $Branches   # if: list of @{ Cond; Negate; Body }
    [System.Collections.Generic.List[ReviewErbNode]] $ElseBody
    [string] $LoopVar
    [System.Collections.Generic.List[ReviewErbNode]] $Body
}

class ReviewErbLiteTemplate {
    hidden [string] $Source
    hidden [string] $SourceName
    hidden [System.Collections.Generic.List[ReviewErbNode]] $Root
    hidden [object] $EscapeFn
    # '-' (pdfmaker's ERB.new(..., trim_mode: '-')) or '>' (ReVIEW::Template's default
    # mode 1, used by the HTML/EPUB layouts: the newline after ANY tag that ends a line
    # is dropped).
    hidden [string] $TrimMode = '-'

    ReviewErbLiteTemplate([string]$Source, [string]$SourceName) {
        $this.Source = $Source
        $this.SourceName = $SourceName
        $this.Root = $this.Parse($this.Tokenize($Source))
    }

    ReviewErbLiteTemplate([string]$Source, [string]$SourceName, [string]$TrimMode) {
        $this.Source = $Source
        $this.SourceName = $SourceName
        $this.TrimMode = $TrimMode
        $this.Root = $this.Parse($this.Tokenize($Source))
    }

    [void] Unsupported([string]$What) {
        throw [ReviewApplicationError]::new("unsupported ERB construct in $($this.SourceName): $What (only a restricted ERB subset is supported for project-local templates -- see the README)")
    }

    # --- tokenizer (handles trim_mode '-') ---------------------------------------------

    hidden [System.Collections.Generic.List[hashtable]] Tokenize([string]$Src) {
        $tokens = [System.Collections.Generic.List[hashtable]]::new()
        $re = [regex]::new('<%(%|=|-|#)?(.*?)(-?)%>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $pos = 0
        $skipNewline = $false
        foreach ($m in $re.Matches($Src)) {
            $text = $Src.Substring($pos, $m.Index - $pos)
            if ($skipNewline) {
                if ($text.StartsWith("`r`n")) { $text = $text.Substring(2) }
                elseif ($text.StartsWith("`n")) { $text = $text.Substring(1) }
                $skipNewline = $false
            }
            $flag = $m.Groups[1].Value
            if ($flag -eq '-') {
                # '<%-' strips indentation before the tag, but only when the tag starts its line
                $lineStart = $text.LastIndexOf("`n") + 1
                if ($text.Substring($lineStart) -match '^[ \t]*$') { $text = $text.Substring(0, $lineStart) }
            }
            if ($text.Length -gt 0) { $tokens.Add(@{ Type = 'text'; Value = $text }) }

            $code = $m.Groups[2].Value
            switch ($flag) {
                '%' { $tokens.Add(@{ Type = 'text'; Value = '<%' + $code + $m.Groups[3].Value + '%>' }) }
                '=' { $tokens.Add(@{ Type = 'output'; Value = $code.Trim() }) }
                '#' { }
                default { $tokens.Add(@{ Type = 'code'; Value = $code.Trim() }) }
            }
            $skipNewline = ($this.TrimMode -eq '>') -or ($m.Groups[3].Value -eq '-')
            $pos = $m.Index + $m.Length
        }
        $tail = $Src.Substring($pos)
        if ($skipNewline) {
            if ($tail.StartsWith("`r`n")) { $tail = $tail.Substring(2) }
            elseif ($tail.StartsWith("`n")) { $tail = $tail.Substring(1) }
        }
        if ($tail.Length -gt 0) { $tokens.Add(@{ Type = 'text'; Value = $tail }) }
        return $tokens
    }

    # --- parser: token stream -> node tree ---------------------------------------------

    hidden [System.Collections.Generic.List[ReviewErbNode]] Parse([System.Collections.Generic.List[hashtable]]$Tokens) {
        $state = @{ Pos = 0 }
        $nodes = $this.ParseBlock($Tokens, $state, @())
        if ($state.Pos -lt $Tokens.Count) { $this.Unsupported("unexpected '$($Tokens[$state.Pos].Value)'") }
        return $nodes
    }

    hidden [System.Collections.Generic.List[ReviewErbNode]] ParseBlock([System.Collections.Generic.List[hashtable]]$Tokens, [hashtable]$State, [string[]]$Terminators) {
        $nodes = [System.Collections.Generic.List[ReviewErbNode]]::new()
        while ($State.Pos -lt $Tokens.Count) {
            $tok = $Tokens[$State.Pos]
            if ($tok.Type -eq 'text') {
                $n = [ReviewErbNode]::new(); $n.Kind = 'text'; $n.Text = $tok.Value
                $nodes.Add($n); $State.Pos++; continue
            }
            if ($tok.Type -eq 'output') {
                $n = [ReviewErbNode]::new(); $n.Kind = 'output'; $n.Expr = $tok.Value
                $nodes.Add($n); $State.Pos++; continue
            }

            $code = $tok.Value
            $keyword = ($code -split '\s+', 2)[0]
            if ($Terminators -contains $keyword) { return $nodes }
            $State.Pos++

            if ($code -match '^(if|unless)\s+(.+)$') {
                $n = [ReviewErbNode]::new(); $n.Kind = 'if'
                $n.Branches = [System.Collections.Generic.List[object]]::new()
                $negate = ($Matches[1] -eq 'unless')
                $cond = $Matches[2]
                while ($true) {
                    $body = $this.ParseBlock($Tokens, $State, @('elsif', 'else', 'end'))
                    $n.Branches.Add(@{ Cond = $cond; Negate = $negate; Body = $body })
                    if ($State.Pos -ge $Tokens.Count) { $this.Unsupported("missing 'end' for '$code'") }
                    $term = $Tokens[$State.Pos].Value
                    $State.Pos++
                    if ($term -match '^elsif\s+(.+)$') { $cond = $Matches[1]; $negate = $false; continue }
                    if ($term -eq 'else') {
                        $n.ElseBody = $this.ParseBlock($Tokens, $State, @('end'))
                        if ($State.Pos -ge $Tokens.Count) { $this.Unsupported("missing 'end' for '$code'") }
                        $State.Pos++
                    }
                    break
                }
                $nodes.Add($n)
            }
            elseif ($code -match '^(.+)\.each\s+do\s*\|\s*([a-z_][A-Za-z0-9_]*)\s*\|$') {
                $n = [ReviewErbNode]::new(); $n.Kind = 'each'
                $n.Expr = $Matches[1]; $n.LoopVar = $Matches[2]
                $n.Body = $this.ParseBlock($Tokens, $State, @('end'))
                if ($State.Pos -ge $Tokens.Count) { $this.Unsupported("missing 'end' for '$code'") }
                $State.Pos++
                $nodes.Add($n)
            }
            else {
                $this.Unsupported("statement '$code'")
            }
        }
        if ($Terminators.Count -gt 0) { $this.Unsupported("missing '$($Terminators -join "'/'")'") }
        return $nodes
    }

    # --- renderer ----------------------------------------------------------------------

    [string] Render([hashtable]$Binding, [object]$Escaper) {
        $this.EscapeFn = $Escaper
        $sb = [System.Text.StringBuilder]::new()
        $scope = [hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($k in $Binding.Keys) { $scope[$k] = $Binding[$k] }
        $this.RenderNodes($this.Root, $scope, $sb)
        return $sb.ToString()
    }

    hidden [void] RenderNodes([System.Collections.Generic.List[ReviewErbNode]]$Nodes, [hashtable]$Scope, [System.Text.StringBuilder]$Sb) {
        foreach ($n in $Nodes) {
            switch ($n.Kind) {
                'text' { [void]$Sb.Append($n.Text) }
                'output' { [void]$Sb.Append($this.ToRubyString($this.Eval($n.Expr, $Scope))) }
                'if' {
                    $done = $false
                    foreach ($br in $n.Branches) {
                        $t = [ReviewErbLiteTemplate]::Truthy($this.Eval($br.Cond, $Scope))
                        if ($br.Negate) { $t = -not $t }
                        if ($t) { $this.RenderNodes($br.Body, $Scope, $Sb); $done = $true; break }
                    }
                    if (-not $done -and $n.ElseBody) { $this.RenderNodes($n.ElseBody, $Scope, $Sb) }
                }
                'each' {
                    $coll = $this.Eval($n.Expr, $Scope)
                    foreach ($item in @($coll)) {
                        $inner = [hashtable]::new($Scope, [System.StringComparer]::Ordinal)
                        $inner[$n.LoopVar] = $item
                        $this.RenderNodes($n.Body, $inner, $Sb)
                    }
                }
            }
        }
    }

    static [bool] Truthy([object]$V) {
        if ($null -eq $V) { return $false }
        if ($V -is [bool]) { return $V }
        return $true
    }

    hidden [string] ToRubyString([object]$V) {
        if ($null -eq $V) { return '' }
        if ($V -is [bool]) { if ($V) { return 'true' } else { return 'false' } }
        if ($V -is [System.Collections.IList]) { return ($V | ForEach-Object { $this.ToRubyString($_) }) -join '' }
        return [string]$V
    }

    # --- expression evaluator (recursive descent over a small token list) ------------------

    [object] Eval([string]$Expr, [hashtable]$Scope) {
        $toks = $this.LexExpr($Expr)
        $st = @{ Pos = 0; Toks = $toks; Scope = $Scope; Src = $Expr }
        $v = $this.ParseOr($st)
        if ($st.Pos -lt $toks.Count) { $this.Unsupported("expression '$Expr'") }
        return $v
    }

    hidden [System.Collections.Generic.List[string]] LexExpr([string]$Expr) {
        $re = [regex]::new(@'
\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|&&|\|\||==|!=|@?[A-Za-z_][A-Za-z0-9_]*[?!]?|-?\d+|[\[\]().,!])
'@.Trim())
        $toks = [System.Collections.Generic.List[string]]::new()
        $pos = 0
        $src = $Expr.TrimEnd()
        while ($pos -lt $src.Length) {
            $m = $re.Match($src, $pos)
            if (-not $m.Success -or $m.Index -ne $pos) { $this.Unsupported("expression '$Expr'") }
            $toks.Add($m.Groups[1].Value)
            $pos += $m.Length
        }
        return $toks
    }

    hidden [string] Peek([hashtable]$St) { if ($St.Pos -lt $St.Toks.Count) { return $St.Toks[$St.Pos] } return $null }
    hidden [string] Next([hashtable]$St) { $t = $this.Peek($St); $St.Pos++; return $t }
    hidden [void] Expect([hashtable]$St, [string]$T) {
        if ($this.Next($St) -ne $T) { $this.Unsupported("expression '$($St.Src)' (expected '$T')") }
    }

    hidden [object] ParseOr([hashtable]$St) {
        $v = $this.ParseAnd($St)
        while ($this.Peek($St) -eq '||') {
            [void]$this.Next($St)
            $r = $this.ParseAnd($St)
            if (-not [ReviewErbLiteTemplate]::Truthy($v)) { $v = $r }
        }
        return $v
    }

    hidden [object] ParseAnd([hashtable]$St) {
        $v = $this.ParseEq($St)
        while ($this.Peek($St) -eq '&&') {
            [void]$this.Next($St)
            $r = $this.ParseEq($St)
            if ([ReviewErbLiteTemplate]::Truthy($v)) { $v = $r }
        }
        return $v
    }

    hidden [object] ParseEq([hashtable]$St) {
        $v = $this.ParseUnary($St)
        $op = $this.Peek($St)
        if ($op -eq '==' -or $op -eq '!=') {
            [void]$this.Next($St)
            $r = $this.ParseUnary($St)
            $eq = ($this.ToRubyString($v) -ceq $this.ToRubyString($r)) -and (($null -eq $v) -eq ($null -eq $r))
            if ($op -eq '==') { return $eq } else { return -not $eq }
        }
        return $v
    }

    hidden [object] ParseUnary([hashtable]$St) {
        if ($this.Peek($St) -eq '!') {
            [void]$this.Next($St)
            return -not [ReviewErbLiteTemplate]::Truthy($this.ParseUnary($St))
        }
        return $this.ParsePostfix($St)
    }

    hidden [object] ParsePostfix([hashtable]$St) {
        $v = $this.ParsePrimary($St)
        while ($true) {
            $t = $this.Peek($St)
            if ($t -eq '[') {
                [void]$this.Next($St)
                $key = $this.ParseOr($St)
                $this.Expect($St, ']')
                $v = $this.Index($v, $key)
            }
            elseif ($t -eq '.') {
                [void]$this.Next($St)
                $name = $this.Next($St)
                $argVal = $null
                if ($this.Peek($St) -eq '(') {
                    [void]$this.Next($St)
                    $argVal = $this.ParseOr($St)
                    $this.Expect($St, ')')
                }
                $v = $this.CallMethod($v, $name, $argVal, $St)
            }
            else { break }
        }
        return $v
    }

    hidden [object] Index([object]$Target, [object]$Key) {
        if ($null -eq $Target) { return $null }
        if ($Target.GetType().Name -eq 'ReviewConfigure') { return $Target.Get([string]$Key) }
        if ($Target -is [System.Collections.IDictionary]) {
            if ($Target.Contains($Key)) { return $Target[$Key] }
            return $null
        }
        if ($Target -is [System.Collections.IList] -and $Key -is [int]) {
            if ($Key -lt $Target.Count) { return $Target[$Key] }
            return $null
        }
        $this.Unsupported("indexing a $($Target.GetType().Name)")
        return $null
    }

    hidden [object] CallMethod([object]$V, [string]$Name, [object]$Arg, [hashtable]$St) {
        switch ($Name) {
            'present?' { return -not $this.IsBlank($V) }
            'blank?' { return $this.IsBlank($V) }
            'nil?' { return $null -eq $V }
            'empty?' { return (@($V).Count -eq 0) -or ($V -is [string] -and $V.Length -eq 0) }
            'to_s' { return $this.ToRubyString($V) }
            'to_i' { $i = 0; [void][int]::TryParse($this.ToRubyString($V), [ref]$i); return $i }
            'strip' { return $this.ToRubyString($V).Trim() }
            'size' { if ($V -is [string]) { return $V.Length } return @($V).Count }
            'length' { if ($V -is [string]) { return $V.Length } return @($V).Count }
            'first' { $a = @($V); if ($a.Count) { return $a[0] } return $null }
            'last' { $a = @($V); if ($a.Count) { return $a[$a.Count - 1] } return $null }
            'flatten' { return $this.Flatten($V) }
            'join' { return (@($V) | ForEach-Object { $this.ToRubyString($_) }) -join $this.ToRubyString($Arg) }
        }
        $this.Unsupported("method '.$Name' in '$($St.Src)'")
        return $null
    }

    hidden [object[]] Flatten([object]$V) {
        $out = [System.Collections.Generic.List[object]]::new()
        foreach ($x in @($V)) {
            if ($x -is [System.Collections.IList] -or $x -is [System.Collections.IList]) { $out.AddRange([object[]]$this.Flatten($x)) }
            else { $out.Add($x) }
        }
        return $out.ToArray()
    }

    hidden [bool] IsBlank([object]$V) {
        if ($null -eq $V) { return $true }
        if ($V -is [bool]) { return -not $V }
        if ($V -is [string]) { return $V.Trim().Length -eq 0 }
        if ($V -is [System.Collections.ICollection]) { return $V.Count -eq 0 }
        return $false
    }

    hidden [object] ParsePrimary([hashtable]$St) {
        $t = $this.Next($St)
        if ($null -eq $t) { $this.Unsupported("expression '$($St.Src)' (unexpected end)") }
        if ($t -eq '(') { $v = $this.ParseOr($St); $this.Expect($St, ')'); return $v }
        if ($t -eq '[') {
            $items = [System.Collections.Generic.List[object]]::new()
            if ($this.Peek($St) -ne ']') {
                while ($true) {
                    $items.Add($this.ParseOr($St))
                    if ($this.Peek($St) -eq ',') { [void]$this.Next($St); continue }
                    break
                }
            }
            $this.Expect($St, ']')
            return $items.ToArray()
        }
        if ($t.StartsWith("'")) { return ($t.Substring(1, $t.Length - 2) -replace "\\(['\\])", '$1') }
        if ($t.StartsWith('"')) {
            $inner = $t.Substring(1, $t.Length - 2)
            if ($inner.Contains('#{')) { $this.Unsupported("string interpolation in '$($St.Src)'") }
            return ($inner -replace '\\(["\\])', '$1')
        }
        if ($t -match '^-?\d+$') { return [int]$t }
        if ($t -eq 'nil') { return $null }
        if ($t -eq 'true') { return $true }
        if ($t -eq 'false') { return $false }

        if ($t -eq 'escape' -and $this.Peek($St) -eq '(') {
            [void]$this.Next($St); $a = $this.ParseOr($St); $this.Expect($St, ')')
            return $this.EscapeFn.Escape($this.ToRubyString($a))
        }
        if ($t -eq 'File' -and $this.Peek($St) -eq '.') {
            [void]$this.Next($St)
            if ($this.Next($St) -ne 'read') { $this.Unsupported("File method in '$($St.Src)'") }
            $this.Expect($St, '('); $a = $this.ParseOr($St); $this.Expect($St, ')')
            $base = $St.Scope['__basedir']
            $p = $this.ToRubyString($a)
            if ($base -and -not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $base $p }
            return Get-Content -LiteralPath $p -Raw -Encoding utf8
        }

        if ($St.Scope.ContainsKey($t)) {
            $v = $St.Scope[$t]
            if ($v -is [scriptblock]) { return & $v }
            return $v
        }
        if ($t.StartsWith('@')) { return $null }   # undefined ivar -> nil, as in Ruby
        $this.Unsupported("identifier '$t' in '$($St.Src)'")
        return $null
    }
}
