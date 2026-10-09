# Port of review/lib/review/lineinput.rb — a pushback-capable line reader.
#
# IMPORTANT PowerShell gotcha (applies to every class in this module, not just this one):
# a method declared with a typed return value (e.g. `[string] Foo()`) silently coerces a
# returned $null into that type's default -- for [string] this is "" (empty string), NOT
# $null. `$null -eq [T]::new().M()` is $false even though `return $null` executed. Since
# Ruby's `nil` is used throughout Re:VIEW as a real sentinel (EOF, "key not found", etc.),
# any method whose Ruby counterpart can return nil MUST be declared with an explicit
# [object] return type (an omitted/untyped method signature defaults to [void] in
# PowerShell classes, which is just as broken for this purpose -- it rejects `return
# $line` outright). Gets() and Peek() below are deliberately [object] for exactly this
# reason -- do not "fix" them to [string].
#
# Deviation from Ruby: Ruby's while_match/until_match accept a block, and a Ruby
# `break` executed inside that block terminates the *enclosing* while_match/until_match
# call (break propagates through `yield`). PowerShell scriptblocks invoked via `& $sb`
# do not have that propagation — `break`/`return` inside the scriptblock only ends that
# one invocation. To replicate Ruby's `break` semantics, the Action scriptblock passed to
# WhileMatch/UntilMatch may return $true to signal "stop iterating now", which the host
# loop below checks explicitly. Compiler.ps1 callers translate Ruby's `break` into
# `return $true` and Ruby's `next` into a plain `return` (no value) from the scriptblock.

class ReviewLineInput {
    hidden [string[]] $Lines
    hidden [int] $Index = 0
    hidden [System.Collections.Generic.List[string]] $Buf
    hidden [bool] $EofFlag = $false
    [int] $LineNo = 0

    static [regex] $InvalidCharacterPattern = [regex]::new('[\x00-\x08\x0b-\x0c\x0e-\x1f]')

    ReviewLineInput([string[]]$Lines) {
        $this.Lines = $Lines
        $this.Buf = [System.Collections.Generic.List[string]]::new()
    }

    static [ReviewLineInput] FromString([string]$Text) {
        return [ReviewLineInput]::new([ReviewLineInput]::SplitKeepingNewlines($Text))
    }

    static [string[]] SplitKeepingNewlines([string]$Text) {
        $result = [System.Collections.Generic.List[string]]::new()
        $sb = [System.Text.StringBuilder]::new()
        foreach ($ch in $Text.ToCharArray()) {
            [void]$sb.Append($ch)
            if ($ch -eq "`n") {
                $result.Add($sb.ToString())
                $sb = [System.Text.StringBuilder]::new()
            }
        }
        if ($sb.Length -gt 0) {
            $result.Add($sb.ToString())
        }
        return $result.ToArray()
    }

    [string] ToString() {
        return "ReviewLineInput(line=$($this.LineNo))"
    }

    [bool] Eof() {
        return $this.EofFlag
    }

    [object] Gets() {
        if ($this.Buf.Count -gt 0) {
            $this.LineNo++
            $last = $this.Buf.Count - 1
            $line = $this.Buf[$last]
            $this.Buf.RemoveAt($last)
            return $line
        }
        if ($this.EofFlag) {
            return $null
        }

        if ($this.Index -ge $this.Lines.Count) {
            $this.EofFlag = $true
            $this.LineNo++
            return $null
        }

        $line = $this.Lines[$this.Index]
        $this.Index++
        $this.LineNo++

        $invalid = [ReviewLineInput]::InvalidCharacterPattern.Match($line)
        if ($invalid.Success) {
            $codepoint = [int]$invalid.Value[0]
            throw [ReviewSyntaxError]::new("found invalid control-sequence character (0x$($codepoint.ToString('x')))." )
        }

        return $line
    }

    [object] Peek() {
        $line = $this.Gets()
        if ($null -ne $line) {
            $this.Ungets($line)
        }
        return $line
    }

    [bool] Next() {
        return $null -ne $this.Peek()
    }

    [int] SkipBlankLines() {
        $n = 0
        while ($true) {
            $line = $this.Gets()
            if ($null -eq $line) { return $n }
            if ($line.Trim().Length -ne 0) {
                $this.Ungets($line)
                return $n
            }
            $n++
        }
        return $n
    }

    [int] SkipCommentLines() {
        $n = 0
        while ($true) {
            $line = $this.Gets()
            if ($null -eq $line) { return $n }
            if (-not $line.Trim().StartsWith('#@')) {
                $this.Ungets($line)
                return $n
            }
            $n++
        }
        return $n
    }

    [void] ForEach([scriptblock]$Action) {
        while ($true) {
            $line = $this.Gets()
            if ($null -eq $line) { return }
            & $Action $line
        }
    }

    # See deviation note at top of file for the $true "stop" return-value convention.
    [void] WhileMatch([regex]$Re, [scriptblock]$Action) {
        while ($true) {
            $line = $this.Gets()
            if ($null -eq $line) { return }
            if (-not $Re.IsMatch($line)) {
                $this.Ungets($line)
                return
            }
            $stop = & $Action $line
            if ($stop -eq $true) { return }
        }
    }

    [void] UntilMatch([regex]$Re, [scriptblock]$Action) {
        while ($true) {
            $line = $this.Gets()
            if ($null -eq $line) { return }
            if ($Re.IsMatch($line)) {
                $this.Ungets($line)
                return
            }
            $stop = & $Action $line
            if ($stop -eq $true) { return }
        }
    }

    hidden [void] Ungets([string]$Line) {
        if ($null -eq $Line) { return }
        $this.LineNo--
        $this.Buf.Add($Line)
    }
}
