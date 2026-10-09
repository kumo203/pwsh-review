# Port of review/lib/review/compiler.rb -- the markup parser. Has zero format knowledge:
# every block/inline command is dispatched to the bound Builder by NAME. To keep that
# dynamic dispatch trivial (PowerShell's `$obj.$methodName(@args)` is the direct analog
# of Ruby's `@builder.send(name, *args)`), Builder/IndexBuilder/LATEXBuilder methods in
# this port use Ruby's exact snake_case names (`ul_item_begin`, `inline_b`, `column_begin`,
# ...) instead of the PascalCase convention used elsewhere in this module (Book model,
# Configure, etc.) -- that convention is for methods called by fixed/known names in our
# own code, not ones assembled dynamically from markup content.
#
# Deviation: minicolumn blocks (note/tip/memo/...) are NOT dispatched via a dynamically
# built "<name>_begin" method name the way Ruby's compile_minicolumn_begin does (which
# only works in Ruby because LATEXBuilder metaprograms 8 near-identical wrapper methods
# from CAPTION_TITLES). This port instead calls a single `common_block_begin($Kind,
# $Caption)` / `common_block_end($Kind)` pair directly -- same output, no metaprogramming
# needed. Tagged sections (`=[column]`/`=[/column]`, `=[nonum]`, etc.) are NOT limited to
# a fixed set, so THOSE still need real dynamic-by-name dispatch (via Test-BuilderMethod
# below) exactly as Ruby does.

function Test-ReviewBuilderMethod {
    param([object]$Builder, [string]$Name)
    return [bool]($Builder.psobject.Methods.Name -contains $Name)
}

class ReviewSyntaxElement {
    [string] $Name
    [string] $Type   # 'block' | 'optional' | 'minicolumn' | 'line'
    [object] $ArgcSpec  # either an [int] or a [int[]]{min,max} pair representing a Range
    [scriptblock] $Checker

    ReviewSyntaxElement([string]$Name, [string]$Type, [object]$ArgcSpec) {
        $this.Name = $Name
        $this.Type = $Type
        $this.ArgcSpec = $ArgcSpec
    }

    [bool] ArgcMatches([int]$Size) {
        if ($this.ArgcSpec -is [int]) { return $Size -eq $this.ArgcSpec }
        # ArgcSpec is a 2-element [min,max] array representing a Ruby Range
        return ($Size -ge $this.ArgcSpec[0]) -and ($Size -le $this.ArgcSpec[1])
    }

    # Parameter named ArgList, not Args: PowerShell class methods silently fail to bind a
    # declared parameter literally named $Args/$args (it collides with the automatic
    # per-scriptblock $args variable) -- confirmed empirically, see PwshReview.psm1's
    # header comment and the project README's "PowerShell-specific mitigations" section.
    [void] CheckArgs([string[]]$ArgList) {
        if (-not $this.ArgcMatches($ArgList.Count)) {
            throw [ReviewCompileError]::new("wrong # of parameters (block command //$($this.Name), expect $($this.ArgcSpecDescription()) but $($ArgList.Count))")
        }
    }

    [string] ArgcSpecDescription() {
        if ($this.ArgcSpec -is [int]) { return [string]$this.ArgcSpec }
        return "$($this.ArgcSpec[0])..$($this.ArgcSpec[1])"
    }

    [int] MinArgc() {
        if ($this.ArgcSpec -is [int]) { return $this.ArgcSpec }
        return $this.ArgcSpec[0]
    }

    # Commands declared with an exact argc of 0 (//quote, //hr, //noindent, ...) are
    # dispatched WITHOUT the (always-empty) $ArgList -- mirroring Ruby's
    # send(name, lines, *[]) / send(name, *[]) -- so their builder methods take just
    # (lines) or () respectively, rather than every zero-arg method having to accept
    # and ignore an empty array parameter.
    [bool] IsNoArg() { return ($this.ArgcSpec -is [int]) -and ($this.ArgcSpec -eq 0) }

    [bool] IsMinicolumn() { return $this.Type -eq 'minicolumn' }
    [bool] BlockRequired() { return $this.Type -eq 'block' -or $this.Type -eq 'minicolumn' }
    [bool] BlockAllowed() { return $this.Type -eq 'block' -or $this.Type -eq 'optional' -or $this.Type -eq 'minicolumn' }
}

class ReviewInlineSyntaxElement {
    [string] $Name
    ReviewInlineSyntaxElement([string]$Name) { $this.Name = $Name }
}

class ReviewCompiler {
    static [hashtable] $Syntax = $null
    static [hashtable] $Inline = $null
    static [int] $MaxHeadlineLevel = 6

    hidden [object] $Builder
    hidden [object] $Chapter
    hidden [bool] $IgnoreErrors
    hidden [bool] $CompileErrors = $false
    # Real List-backed stacks, NOT arrays sliced with $a[0..($a.Count - 2)] to "pop":
    # for a 1-element array PowerShell's 0..-1 is a DESCENDING range [0, -1] that
    # returns 2 elements, not 0 -- so the stack never empties. That turned every
    # =[column]/=[nonum] tagged section into an infinite loop (found via syntax-book).
    hidden [System.Collections.Generic.List[string]] $CommandNameStack = [System.Collections.Generic.List[string]]::new()
    hidden [string[]] $NonParsedCommands = @('embed', 'texequation', 'graph')
    hidden [string] $MinicolumnName = $null
    hidden [System.Collections.Generic.List[object]] $TaggedSection = [System.Collections.Generic.List[object]]::new()
    hidden [int[]] $HeadlineIndexes = $null
    [string] $PreviousListType = $null

    static ReviewCompiler() {
        [ReviewCompiler]::InitSyntaxTables()
    }

    static [void] InitSyntaxTables() {
        if ($null -ne [ReviewCompiler]::Syntax) { return }

        $syntaxTable = @{}
        $defblock = {
            param($name, $argc, $optional)
            $type = if ($optional) { 'optional' } else { 'block' }
            $syntaxTable[$name] = [ReviewSyntaxElement]::new($name, $type, $argc)
        }
        $defminicolumn = {
            param($name, $argc)
            $syntaxTable[$name] = [ReviewSyntaxElement]::new($name, 'minicolumn', $argc)
        }
        $defsingle = {
            param($name, $argc)
            $syntaxTable[$name] = [ReviewSyntaxElement]::new($name, 'line', $argc)
        }

        & $defblock 'read' 0 $false
        & $defblock 'lead' 0 $false
        & $defblock 'list' @(2, 3) $false
        & $defblock 'emlist' @(0, 2) $false
        & $defblock 'cmd' @(0, 1) $false
        & $defblock 'table' @(0, 2) $false
        & $defblock 'imgtable' @(0, 3) $false
        & $defblock 'emtable' @(0, 1) $false
        & $defblock 'quote' 0 $false
        & $defblock 'image' @(2, 3) $true
        & $defblock 'source' @(0, 2) $false
        & $defblock 'listnum' @(2, 3) $false
        & $defblock 'emlistnum' @(0, 2) $false
        & $defblock 'bibpaper' @(2, 3) $true
        & $defblock 'doorquote' 1 $false
        & $defblock 'talk' 0 $false
        & $defblock 'texequation' @(0, 2) $false
        & $defblock 'graph' @(1, 3) $false
        & $defblock 'indepimage' @(1, 3) $true
        & $defblock 'numberlessimage' @(1, 3) $true

        & $defblock 'address' 0 $false
        & $defblock 'blockquote' 0 $false
        & $defblock 'bpo' 0 $false
        & $defblock 'flushright' 0 $false
        & $defblock 'centering' 0 $false
        & $defblock 'box' @(0, 1) $false
        & $defblock 'comment' @(0, 1) $true
        & $defblock 'embed' @(0, 1) $false

        & $defminicolumn 'note' @(0, 1)
        & $defminicolumn 'memo' @(0, 1)
        & $defminicolumn 'tip' @(0, 1)
        & $defminicolumn 'info' @(0, 1)
        & $defminicolumn 'warning' @(0, 1)
        & $defminicolumn 'important' @(0, 1)
        & $defminicolumn 'caution' @(0, 1)
        & $defminicolumn 'notice' @(0, 1)

        & $defsingle 'footnote' 2
        & $defsingle 'endnote' 2
        & $defsingle 'printendnotes' 0
        & $defsingle 'noindent' 0
        & $defsingle 'blankline' 0
        & $defsingle 'pagebreak' 0
        & $defsingle 'hr' 0
        & $defsingle 'parasep' 0
        & $defsingle 'label' 1
        & $defsingle 'raw' 1
        & $defsingle 'tsize' 1
        & $defsingle 'include' 1
        & $defsingle 'olnum' 1
        & $defsingle 'firstlinenum' 1
        & $defsingle 'beginchild' 0
        & $defsingle 'endchild' 0
        # registered by LATEXBuilder in Ruby (Compiler.defsingle(:latextsize, 1)); kept in
        # the global table here for the same reason as 'hd_chap' below
        & $defsingle 'latextsize' 1

        [ReviewCompiler]::Syntax = $syntaxTable

        $inlineTable = @{}
        $inlineNames = @(
            'chapref', 'chap', 'title', 'img', 'imgref', 'icon', 'list', 'table', 'eq', 'fn', 'endnote',
            'kw', 'ruby', 'bou', 'ami', 'b', 'dtp', 'code', 'bib', 'hd', 'secref', 'sec', 'sectitle',
            'href', 'recipe', 'column', 'tcy', 'balloon',
            'abbr', 'acronym', 'cite', 'dfn', 'em', 'kbd', 'q', 'samp', 'strong', 'var', 'big', 'small',
            'del', 'ins', 'sup', 'sub', 'tt', 'i', 'tti', 'ttb', 'u', 'raw', 'br', 'm', 'uchar',
            # (no 'labelref'/'ref': those inline ops were added after Re:VIEW 5.9.0, the
            # version this port and its Docker oracle target)
            'idx', 'hidx', 'comment', 'include', 'embed', 'pageref', 'w', 'wb',
            # registered by LATEXBuilder in Ruby (Compiler.definline(:dtp/:hd_chap)); kept here
            # since our port's inline table is global/static rather than per-target-registered.
            'hd_chap'
        )
        foreach ($n in $inlineNames) { $inlineTable[$n] = [ReviewInlineSyntaxElement]::new($n) }
        [ReviewCompiler]::Inline = $inlineTable
    }

    ReviewCompiler([object]$Builder) {
        [ReviewCompiler]::InitSyntaxTables()
        $this.Builder = $Builder
        $this.IgnoreErrors = ($Builder.GetType().Name -eq 'ReviewIndexBuilder')
    }

    [bool] SyntaxDefined([string]$Name) { return [ReviewCompiler]::Syntax.ContainsKey($Name) }
    [ReviewSyntaxElement] SyntaxDescriptor([string]$Name) { return [ReviewCompiler]::Syntax[$Name] }
    [bool] InlineDefined([string]$Name) { return [ReviewCompiler]::Inline.ContainsKey($Name) }

    [object] Compile([object]$Chap) {
        $this.Chapter = $Chap
        $this.DoCompile()
        if ($this.CompileErrors) {
            throw [ReviewApplicationError]::new("$($Chap.Basename()) cannot be compiled.")
        }
        return $this.Builder.result()
    }

    hidden [void] Error([string]$Msg) {
        if ($this.IgnoreErrors) { return }
        $this.CompileErrors = $true
        Write-Warning "$($this.Chapter.Basename()): $Msg"
    }

    hidden [void] DoCompile() {
        $f = [ReviewLineInput]::FromString($this.Chapter.Content)
        $this.Builder.bind($this, $this.Chapter, $f)
        $this.PreviousListType = $null
        $this.MinicolumnName = $null
        $this.TaggedSection.Clear()

        while ($f.Next()) {
            $peek = $f.Peek()
            if ($peek -match '^#@') {
                [void]$f.Gets()
            }
            elseif ($peek -match '^=+[\[\s{]') {
                $this.CompileHeadline($f.Gets())
                $this.PreviousListType = $null
            }
            elseif ($peek -match '^\s+\*') {
                $this.CompileUlist($f)
                $this.PreviousListType = 'ul'
            }
            elseif ($peek -match '^\s+\d+\.') {
                $this.CompileOlist($f)
                $this.PreviousListType = 'ol'
            }
            elseif ($peek -match '^\s+:\s') {
                $this.CompileDlist($f)
                $this.PreviousListType = 'dl'
            }
            elseif ($peek -match '^\s*:\s') {
                Write-Warning 'Definition list starting with `:` is deprecated. It should start with ` : `.'
                $this.CompileDlist($f)
                $this.PreviousListType = 'dl'
            }
            elseif ($peek -match '^//\}') {
                if ($this.MinicolumnName) {
                    [void]$f.Gets()
                    $this.CompileMinicolumnEnd()
                }
                else {
                    [void]$f.Gets()
                    $this.Error('block end seen but not opened')
                }
            }
            elseif ($peek -match '^//[a-z]+') {
                $line = $f.Peek()
                $m = [regex]::Match($line, '^//([a-z]+)(:?\[.*\])?\{\s*$')
                if ($m.Success -and $this.IsMinicolumnName($m.Groups[1].Value)) {
                    $line = $f.Gets()
                    $name = $m.Groups[1].Value
                    # Precompute: inside a method call's parens, the comma in an
                    # unparenthesized `-replace 'x', ''` operand is parsed as an argument
                    # separator, silently passing TWO arguments to ParseArgs.
                    $minicolumnArgStr = (($line -replace '^//[a-z]+', '').TrimEnd()) -replace '\{$', ''
                    $args = $this.ParseArgs($minicolumnArgStr)
                    $this.CompileMinicolumnBegin($name, $(if ($args.Count -gt 0) { $args[0] } else { $null }))
                }
                else {
                    $result = $this.ReadCommand($f)
                    $name = $result.Name; $args = $result.Args; $lines = $result.Lines
                    if (-not $this.SyntaxDefined($name)) {
                        $this.Error("unknown command: //$name")
                    }
                    else {
                        $syntaxElem = $this.SyntaxDescriptor($name)
                        $this.CompileCommand($syntaxElem, $args, $lines)
                    }
                }
                $this.PreviousListType = $null
            }
            elseif ($peek -match '^//') {
                $line = $f.Gets()
                Write-Warning "``//' seen but is not valid command: $($line.Trim())"
                if ($this.BlockOpen($line)) {
                    Write-Warning 'skipping block...'
                    [void]$this.ReadBlock($f, $false)
                }
                $this.PreviousListType = $null
            }
            else {
                if ($f.Peek().Trim().Length -eq 0) {
                    [void]$f.Gets()
                    continue
                }
                $this.CompileParagraph($f)
                $this.PreviousListType = $null
            }
        }
        $this.CloseAllTaggedSection()
    }

    hidden [bool] IsMinicolumnName([string]$Name) {
        return $this.Builder.minicolumn_block_name($Name)
    }

    hidden [void] CompileMinicolumnBegin([string]$Name, [object]$Caption) {
        if (-not (Test-ReviewBuilderMethod $this.Builder 'common_block_begin')) {
            $this.Error("strategy does not support minicolumn: $Name")
            return
        }
        if ($this.MinicolumnName) {
            $this.Error("minicolumn cannot be nested: $Name")
            return
        }
        $this.MinicolumnName = $Name
        $this.Builder.common_block_begin($Name, $Caption)
    }

    hidden [void] CompileMinicolumnEnd() {
        if (-not $this.MinicolumnName) {
            $this.Error('minicolumn is not used')
            return
        }
        $name = $this.MinicolumnName
        $this.Builder.common_block_end($name)
        $this.MinicolumnName = $null
    }

    hidden [void] CompileHeadline([string]$Line) {
        if ($null -eq $this.HeadlineIndexes) {
            $num = if ($this.Chapter.Number) { [int]$this.Chapter.Number } else { 0 }
            $this.HeadlineIndexes = @($num - 1)
        }
        $m = [regex]::Match($Line, '^(=+)(?:\[(.+?)\])?(?:\{(.+?)\})?(.*)')
        $level = $m.Groups[1].Value.Length
        if ($level -gt [ReviewCompiler]::MaxHeadlineLevel) {
            throw [ReviewCompileError]::new("Invalid header: max headline level is $([ReviewCompiler]::MaxHeadlineLevel)")
        }

        $tag = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $null }
        $label = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { $null }
        $caption = $m.Groups[4].Value.Trim()
        $index = $level - 1

        if ($tag) {
            if ($tag.StartsWith('/')) {
                $openTag = $tag.Substring(1)
                if ($this.TaggedSection.Count -eq 0) {
                    $this.Error("$openTag is not opened.")
                }
                else {
                    $prev = $this.TaggedSection[$this.TaggedSection.Count - 1]
                    $this.TaggedSection.RemoveAt($this.TaggedSection.Count - 1)
                    if ($prev.Tag -ne $openTag) {
                        $this.Error("$openTag is not opened.")
                    }
                    $this.CloseTaggedSection($prev.Tag, $prev.Level)
                }
            }
            else {
                if ($caption.Length -eq 0) { Write-Warning 'headline is empty.' }
                $this.CloseCurrentTaggedSection($level)
                $this.OpenTaggedSection($tag, $level, $label, $caption)
            }
        }
        else {
            if ($caption.Length -eq 0) { Write-Warning 'headline is empty.' }
            if ($this.HeadlineIndexes.Count -gt ($index + 1)) {
                $this.HeadlineIndexes = $this.HeadlineIndexes[0..$index]
            }
            while ($this.HeadlineIndexes.Count -le $index) {
                $this.HeadlineIndexes += 0
            }
            $this.HeadlineIndexes[$index]++
            $this.CloseCurrentTaggedSection($level)
            $this.Builder.headline($level, $label, $caption)
        }
    }

    hidden [void] CloseCurrentTaggedSection([int]$Level) {
        while ($this.TaggedSection.Count -gt 0 -and $this.TaggedSection[$this.TaggedSection.Count - 1].Level -ge $Level) {
            $top = $this.TaggedSection[$this.TaggedSection.Count - 1]
            $this.TaggedSection.RemoveAt($this.TaggedSection.Count - 1)
            $this.CloseTaggedSection($top.Tag, $top.Level)
        }
    }

    hidden [void] OpenTaggedSection([string]$Tag, [int]$Level, [object]$Label, [string]$Caption) {
        $mid = "${Tag}_begin"
        if (-not (Test-ReviewBuilderMethod $this.Builder $mid)) {
            $this.Error("builder does not support tagged section: $Tag")
            $this.Builder.headline($Level, $Label, $Caption)
            return
        }
        $this.TaggedSection.Add([PSCustomObject]@{ Tag = $Tag; Level = $Level })
        $this.Builder.$mid($Level, $Label, $Caption)
    }

    hidden [void] CloseTaggedSection([string]$Tag, [int]$Level) {
        $mid = "${Tag}_end"
        if (Test-ReviewBuilderMethod $this.Builder $mid) {
            $this.Builder.$mid($Level)
        }
        else {
            $this.Error("builder does not support block op: $mid")
        }
    }

    hidden [void] CloseAllTaggedSection() {
        while ($this.TaggedSection.Count -gt 0) {
            $top = $this.TaggedSection[$this.TaggedSection.Count - 1]
            $this.TaggedSection.RemoveAt($this.TaggedSection.Count - 1)
            $this.CloseTaggedSection($top.Tag, $top.Level)
        }
    }

    # $state is a hashtable (reference type), not a bare scalar: a scriptblock invoked via
    # `& $sb` from inside LineInput.WhileMatch does NOT share a live binding with a plain
    # outer variable (reassigning $level inside the block would not be visible here after
    # WhileMatch returns) -- only mutations to a shared *referenced object* propagate both
    # ways. See 01.LineInput.ps1's header comment for the related GetNewClosure() finding
    # (also not used here: it breaks $this inside class methods).
    # $self = $this, used INSIDE every scriptblock below: a scriptblock invoked via
    # `& $sb` from within LineInput.WhileMatch/UntilMatch (a DIFFERENT class's method)
    # resolves the automatic `$this` dynamically, by call stack -- it binds to
    # WhileMatch's own `$this` (the ReviewLineInput instance), NOT the ReviewCompiler
    # instance the scriptblock was lexically written under. A plain captured variable
    # does not have this problem (confirmed empirically); every nested scriptblock in
    # this file uses $self for exactly this reason. See also the $state-hashtable note
    # below for the companion "mutations don't write back" finding.
    hidden [void] CompileUlist([object]$F) {
        $self = $this
        $state = @{ Level = 0 }
        $re = [regex]::new('^\s+\*|^#@')
        $F.WhileMatch($re, {
            param($line)
            if ($line -match '^#@') { return $false }

            $buf = [System.Collections.Generic.List[string]]::new()
            $buf.Add($self.Text(($line -replace '\*+', '').Trim()))
            $F.WhileMatch([regex]::new('^\s+(?!\*)\S'), {
                param($cont)
                $buf.Add($self.Text($cont.Trim()))
                return $false
            })

            $currentLevel = [regex]::Match($line, '^\s+(\*+)').Groups[1].Value.Length
            if ($state.Level -eq $currentLevel) {
                $self.Builder.ul_item_end()
                $self.Builder.ul_item_begin($buf.ToArray())
            }
            elseif ($state.Level -lt $currentLevel) {
                $levelDiff = $currentLevel - $state.Level
                if ($levelDiff -ne 1) { $self.Error('too many *.') }
                $state.Level = $currentLevel
                $self.Builder.ul_begin()
                $self.Builder.ul_item_begin($buf.ToArray())
            }
            else {
                $levelDiff = $state.Level - $currentLevel
                $state.Level = $currentLevel
                for ($i = $levelDiff; $i -ge 1; $i--) {
                    $self.Builder.ul_item_end()
                    $self.Builder.ul_end()
                }
                $self.Builder.ul_item_end()
                $self.Builder.ul_item_begin($buf.ToArray())
            }
            return $false
        })

        for ($i = $state.Level; $i -ge 1; $i--) {
            $this.Builder.ul_item_end()
            $this.Builder.ul_end()
        }
    }

    hidden [void] CompileOlist([object]$F) {
        $self = $this
        $this.Builder.ol_begin()
        $F.WhileMatch([regex]::new('^\s+\d+\.|^#@'), {
            param($line)
            if ($line -match '^#@') { return $false }

            $num = [regex]::Match($line, '(\d+)\.').Groups[1].Value
            $buf = [System.Collections.Generic.List[string]]::new()
            $buf.Add($self.Text(($line -replace '\d+\.', '').Trim()))
            $F.WhileMatch([regex]::new('^\s+(?!\d+\.)\S'), {
                param($cont)
                $buf.Add($self.Text($cont.Trim()))
                return $false
            })
            $self.Builder.ol_item($buf.ToArray(), $num)
            return $false
        })
        $this.Builder.ol_end()
    }

    hidden [void] CompileDlist([object]$F) {
        $self = $this
        $this.Builder.dl_begin()
        while ($F.Peek() -and ($F.Peek() -match '^\s*:')) {
            $this.Builder.doc_status.dt = $true
            $this.Builder.dt($this.Text(($F.Gets() -replace '^\s*:', '').Trim()))
            $this.Builder.doc_status.dt = $null
            $desc = [System.Collections.Generic.List[string]]::new()
            $F.UntilMatch([regex]::new('^(\S|\s*:|\s+\d+\.\s|\s+\*\s)'), {
                param($line)
                $desc.Add($self.Text($line.Trim()))
                return $false
            })
            $this.Builder.dd($desc.ToArray())
            [void]$F.SkipBlankLines()
            [void]$F.SkipCommentLines()
        }
        $this.Builder.dl_end()
    }

    hidden [void] CompileParagraph([object]$F) {
        $self = $this
        $buf = [System.Collections.Generic.List[string]]::new()
        $F.UntilMatch([regex]::new('^//|^#@'), {
            param($line)
            if ($line.Trim().Length -eq 0) { return $true }
            $tabMatch = [regex]::Match($line, '^(\t+)\s*')
            $detabbed = if ($tabMatch.Success) {
                ($line -replace '^(\t+)\s*', ('<!ESCAPETAB!>' * $tabMatch.Groups[1].Value.Length))
            }
            else { $line }
            $buf.Add($self.Text($detabbed.Trim().Replace('<!ESCAPETAB!>', "`t")))
            return $false
        })
        $this.Builder.paragraph($buf.ToArray())
    }

    hidden [PSCustomObject] ReadCommand([object]$F) {
        $line = $F.Gets()
        $name = [regex]::Match($line, '[a-z]+').Value
        $ignoreInline = $this.NonParsedCommands -contains $name
        $this.CommandNameStack.Add($name)
        $argStr = (($line -replace '^//[a-z]+', '').TrimEnd()) -replace '\{$', ''
        $args = $this.ParseArgs($argStr)
        $this.Builder.doc_status.$name = $true
        # Assigned directly, NOT via `$lines = if (...) { $this.ReadBlock(...) }`: an if-
        # expression routes its output through the pipeline, where an EMPTY array emits
        # nothing -- so an empty-but-present block (//imgtable[...]{ //}) would come back
        # as $null and be misreported as "block is required".
        $lines = $null
        if ($this.BlockOpen($line)) { $lines = $this.ReadBlock($F, $ignoreInline) }
        $this.Builder.doc_status.$name = $null
        $this.CommandNameStack.RemoveAt($this.CommandNameStack.Count - 1)
        return [PSCustomObject]@{ Name = $name; Args = $args; Lines = $lines }
    }

    hidden [bool] BlockOpen([string]$Line) {
        $t = $Line.TrimEnd()
        return $t.Length -gt 0 -and $t.Substring($t.Length - 1) -eq '{'
    }

    hidden [string[]] ReadBlock([object]$F, [bool]$IgnoreInline) {
        $self = $this
        $head = $F.LineNo
        $buf = [System.Collections.Generic.List[string]]::new()
        $re = [regex]::new('^//\}')
        $F.UntilMatch($re, {
            param($line)
            if ($IgnoreInline) {
                $buf.Add($line.TrimEnd("`r", "`n"))
            }
            elseif ($line -notmatch '^#@') {
                $buf.Add($self.Text($line.TrimEnd(), $true))
            }
            return $false
        })
        $peeked = $F.Peek()
        if (-not ($peeked -and $peeked.StartsWith('//}'))) {
            $this.Error("unexpected EOF (block begins at: $head)")
            return $buf.ToArray()
        }
        [void]$F.Gets()
        return $buf.ToArray()
    }

    hidden [string[]] ParseArgs([string]$Str) {
        if ($Str.Length -eq 0) { return @() }
        $words = [System.Collections.Generic.List[string]]::new()
        $pos = 0
        $re = [regex]::new('\G(\[\]|\[.*?[^\\]\])')
        while ($pos -lt $Str.Length) {
            $m = $re.Match($Str, $pos)
            if (-not $m.Success) { break }
            $word = $m.Value
            $inner = $word.Substring(1, $word.Length - 2)
            $unescaped = [regex]::Replace($inner, '\\(.)', {
                param($mm)
                $ch = $mm.Groups[1].Value
                if ($ch -eq ']' -or $ch -eq '\') { $ch } else { '\' + $ch }
            })
            $words.Add($unescaped)
            $pos += $word.Length
        }
        if ($pos -ne $Str.Length) {
            $this.Error("argument syntax error: $($Str.Substring($pos)) in $Str")
            return @()
        }
        return $words.ToArray()
    }

    hidden [void] CompileCommand([ReviewSyntaxElement]$SyntaxElem, [string[]]$ArgList, [string[]]$Lines) {
        if (-not (Test-ReviewBuilderMethod $this.Builder $SyntaxElem.Name)) {
            $this.Error("builder does not support command: //$($SyntaxElem.Name)")
            return
        }
        try {
            $SyntaxElem.CheckArgs($ArgList)
        }
        catch [ReviewCompileError] {
            $this.Error($_.Exception.Message)
            $ArgList = @('(NoArgument)') * $SyntaxElem.MinArgc()
        }
        if ($SyntaxElem.BlockAllowed()) {
            $this.CompileBlock($SyntaxElem, $ArgList, $Lines)
        }
        else {
            if ($Lines) {
                $this.Error("block is not allowed for command //$($SyntaxElem.Name); ignore")
            }
            $this.CompileSingle($SyntaxElem, $ArgList)
        }
    }

    # Calling convention for every builder method that corresponds to a Compiler::SYNTAX
    # entry (list, emlist, image, footnote, ...): PowerShell class methods have no
    # equivalent of Ruby's optional/splat parameters (`def list(lines, id, caption,
    # lang=nil)`), so rather than defining a different fixed-arity overload per command
    # (error-prone to keep in sync with Ruby's varying argc specs), every such method
    # takes a flat (lines, argList) pair -- or just (argList) for 'line'-type commands --
    # and destructures $ArgList[0]/[1]/[2] manually, treating a missing trailing element
    # as $null exactly like a Ruby optional parameter's default.
    hidden [void] CompileBlock([ReviewSyntaxElement]$SyntaxElem, [string[]]$ArgList, [string[]]$Lines) {
        $effectiveLines = if ($null -ne $Lines) { $Lines } else { $this.DefaultBlock($SyntaxElem) }
        $methodName = $SyntaxElem.Name
        if ($SyntaxElem.IsNoArg()) {
            $this.Builder.$methodName($effectiveLines)
        }
        else {
            $this.Builder.$methodName($effectiveLines, $ArgList)
        }
    }

    hidden [string[]] DefaultBlock([ReviewSyntaxElement]$SyntaxElem) {
        if ($SyntaxElem.BlockRequired()) {
            $this.Error("block is required for //$($SyntaxElem.Name); use empty block")
        }
        return @()
    }

    hidden [void] CompileSingle([ReviewSyntaxElement]$SyntaxElem, [string[]]$ArgList) {
        $methodName = $SyntaxElem.Name
        if ($SyntaxElem.IsNoArg()) {
            $this.Builder.$methodName()
        }
        else {
            $this.Builder.$methodName($ArgList)
        }
    }

    hidden [string] ReplaceFence([string]$Str) {
        return [regex]::Replace($Str, '@<(\w+)>([$|])(.+?)\2', {
            param($m)
            $arg = $m.Groups[3].Value
            if ($arg -match "[\x01\x02\x03\x04]") {
                $this.Error("invalid character in '$Str'")
            }
            $replaced = $arg.Replace('@', "`u{1}").Replace('\', "`u{2}").Replace('{', "`u{3}").Replace('}', "`u{4}")
            "@<$($m.Groups[1].Value)>{$replaced}"
        })
    }

    hidden [string] RevertReplaceFence([string]$Str) {
        return $Str.Replace("`u{1}", '@').Replace("`u{2}", '\').Replace("`u{3}", '{').Replace("`u{4}", '}')
    }

    hidden [bool] InNonEscapedCommand() {
        if ($this.CommandNameStack.Count -eq 0) { return $false }
        $current = $this.CommandNameStack[$this.CommandNameStack.Count - 1]
        $nonEscaped = if ($this.Builder.highlight()) { @('list', 'emlist', 'listnum', 'emlistnum', 'cmd', 'source') } else { @() }
        return $nonEscaped -contains $current
    }

    # Called from Builder#compile_inline -> Compiler#text (public in Ruby). BlockMode
    # mirrors Ruby's `text(str, block_mode = false)` used by ReadBlock.
    [string] Text([string]$Str) { return $this.Text($Str, $false) }

    [string] Text([string]$Str, [bool]$BlockMode) {
        if ($Str.Length -eq 0) { return '' }

        $fenced = $this.ReplaceFence($Str)
        $words = [regex]::Split($fenced, '(@<\w+>\{(?:[^}\\]|\\.)*?\})')
        foreach ($w in $words) {
            $inlineOpCount = [regex]::Matches($w, '@<\w+>').Count
            if ($inlineOpCount -gt 1 -and $w -notmatch '^@<raw>') {
                $this.Error("``@<xxx>' seen but is not valid inline op: $w")
            }
        }

        $result = [System.Text.StringBuilder]::new()
        $idx = 0
        while ($idx -lt $words.Count) {
            $chunk = $this.RevertReplaceFence($words[$idx])
            if ($this.InNonEscapedCommand() -and $BlockMode) {
                [void]$result.Append($chunk)
            }
            else {
                [void]$result.Append($this.Builder.nofunc_text($chunk))
            }
            $idx++
            if ($idx -ge $words.Count) { break }

            $inlineChunk = $this.RevertReplaceFence($words[$idx]).Replace('\}', '}').Replace('\\', '\')
            [void]$result.Append($this.CompileInline($inlineChunk))
            $idx++
        }
        return $result.ToString()
    }

    [string] CompileInline([string]$Str) {
        $m = [regex]::Match($Str, '^@<(\w+)>\{(.*?)\}$')
        $op = $m.Groups[1].Value
        $arg = $m.Groups[2].Value
        try {
            if (-not $this.InlineDefined($op)) {
                throw [ReviewCompileError]::new("no such inline op: $op")
            }
            $methodName = "inline_$op"
            if (-not (Test-ReviewBuilderMethod $this.Builder $methodName)) {
                throw [ReviewApplicationError]::new("builder does not support inline op: @<$op>")
            }
            return $this.Builder.$methodName($arg)
        }
        catch {
            $this.Error($_.Exception.Message)
            return $this.Builder.nofunc_text($Str)
        }
    }
}
