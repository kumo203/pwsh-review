# Port of review/lib/review/sec_counter.rb.
#
# $Chapter is duck-typed (a ReviewChapter or ReviewPart), accessed only via Number/
# FormatNumber/IsPart -- avoiding a `-is [ReviewPart]` type-literal check keeps this file
# free of a forward reference to Part (which, like Chapter, is defined earlier in the
# load order anyway, but the duck-typing convention is kept consistent project-wide).

class ReviewSecCounter {
    hidden [object] $Chapter
    hidden [int[]] $Counter

    ReviewSecCounter([int]$N, [object]$Chapter) {
        $this.Chapter = $Chapter
        $this.ResetCounter($N)
    }

    [void] ResetCounter([int]$N) {
        $this.Counter = New-Object int[] $N
    }

    [void] Inc([int]$Level) {
        $n = $Level - 2
        if ($n -ge 0) {
            $this.Counter[$n]++
        }
        if ($this.Counter.Length -gt $n) {
            for ($i = $n + 1; $i -lt $this.Counter.Length; $i++) {
                $this.Counter[$i] = 0
            }
        }
    }

    [string] Anchor([int]$Level) {
        $str = $this.Chapter.FormatNumber($false)
        for ($i = 0; $i -le $Level - 2; $i++) {
            $str = "$str-$($this.Counter[$i])"
        }
        return $str
    }

    [int[]] NumberList() {
        $buf = [System.Collections.Generic.List[int]]::new($this.Counter)
        while ($buf.Count -gt 0 -and $buf[$buf.Count - 1] -eq 0) {
            $buf.RemoveAt($buf.Count - 1)
        }
        return $buf.ToArray()
    }

    [object] Prefix([int]$Level, [int]$SecNoLevel) {
        if ($null -eq $this.Chapter.Number) { return $null }

        if ($Level -eq 1) {
            if ($SecNoLevel -lt 1) { return $null }
            if ($this.Chapter.IsPart()) {
                $num = $this.Chapter.Number
                return "$([ReviewI18n]::T('part', $num))$([ReviewI18n]::T('chapter_postfix'))"
            }
            return "$($this.Chapter.FormatNumber($true))$([ReviewI18n]::T('chapter_postfix'))"
        }
        elseif ($SecNoLevel -ge $Level) {
            $parts = [System.Collections.Generic.List[string]]::new()
            if ($this.Chapter.IsPart()) {
                $parts.Add([ReviewI18n]::T('part_short', $this.Chapter.Number))
            }
            else {
                $parts.Add($this.Chapter.FormatNumber($false))
            }
            for ($i = 0; $i -le $Level - 2; $i++) {
                $parts.Add(".$($this.Counter[$i])")
            }
            $parts.Add([ReviewI18n]::T('chapter_postfix'))
            return ($parts -join '')
        }
        return $null
    }
}
