$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'ReviewLineInput' {
    InModuleScope PwshReview {
        It 'reads lines in order, preserving trailing newlines' {
            $li = [ReviewLineInput]::FromString("line1`nline2`nline3")
            $li.Gets() | Should -Be "line1`n"
            $li.Gets() | Should -Be "line2`n"
            $li.Gets() | Should -Be 'line3'
        }

        It 'returns $null (not empty string) at real EOF' {
            $li = [ReviewLineInput]::FromString("only")
            $li.Gets() | Should -Be 'only'
            $result = $li.Gets()
            $result | Should -BeNullOrEmpty
            ($null -eq $result) | Should -BeTrue
        }

        It 'Peek does not consume, Next reflects remaining input' {
            $li = [ReviewLineInput]::FromString("a`nb")
            $li.Peek() | Should -Be "a`n"
            $li.Next() | Should -BeTrue
            $li.Gets() | Should -Be "a`n"
            $li.Gets() | Should -Be 'b'
            $li.Next() | Should -BeFalse
            $li.Eof() | Should -BeTrue
        }

        It 'supports pushback (ungets) via Peek re-reading the same line' {
            $li = [ReviewLineInput]::FromString("x`ny`n")
            $first = $li.Gets()
            $li.Peek() | Should -Be "y`n"
            $li.Gets() | Should -Be "y`n"
        }

        It 'SkipBlankLines counts and skips only blank lines' {
            $li = [ReviewLineInput]::FromString("`n`ntext`n")
            $n = $li.SkipBlankLines()
            $n | Should -Be 2
            $li.Gets() | Should -Be "text`n"
        }

        It 'SkipCommentLines counts and skips only #@ lines' {
            $li = [ReviewLineInput]::FromString("#@foo`n#@bar`ntext`n")
            $n = $li.SkipCommentLines()
            $n | Should -Be 2
            $li.Gets() | Should -Be "text`n"
        }

        It 'WhileMatch collects matching lines and leaves the first non-match for later reads' {
            $li = [ReviewLineInput]::FromString("  * item1`n  cont`n  * item2`nnotalist`n")
            $collected = [System.Collections.Generic.List[string]]::new()
            $li.WhileMatch([regex]::new('^\s+\*|^#@'), {
                param($line)
                $collected.Add($line.Trim())
            })
            @($collected) | Should -Be @('* item1')
            $li.Peek() | Should -Be "  cont`n"
        }

        It 'WhileMatch action can request early stop by returning $true (Ruby break analog)' {
            $li = [ReviewLineInput]::FromString("  * a`n  * b`n  * c`n")
            $seen = [System.Collections.Generic.List[string]]::new()
            $li.WhileMatch([regex]::new('^\s+\*'), {
                param($line)
                $seen.Add($line.Trim())
                if ($seen.Count -ge 2) { return $true }
                return $false
            })
            @($seen) | Should -Be @('* a', '* b')
            $li.Peek() | Should -Be "  * c`n"
        }

        It 'UntilMatch stops at (and ungets) the first matching line' {
            $li = [ReviewLineInput]::FromString("one`ntwo`n//}`nrest`n")
            $buf = [System.Collections.Generic.List[string]]::new()
            $li.UntilMatch([regex]::new('^//\}'), {
                param($line)
                $buf.Add($line.TrimEnd("`n"))
            })
            @($buf) | Should -Be @('one', 'two')
            $li.Peek() | Should -Be "//}`n"
        }

        It 'throws ReviewSyntaxError on invalid control characters' {
            $badChar = [char]0x01
            $li = [ReviewLineInput]::FromString("bad${badChar}line`n")
            { $li.Gets() } | Should -Throw
        }
    }
}
