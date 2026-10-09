# Minimal POSIX-shell-word-splitting, equivalent to Ruby's String#shellsplit (from the
# `shellwords` stdlib) as used on texoptions/dvioptions/makeindex_options strings like
# '-interaction=nonstopmode -file-line-error -halt-on-error'. Handles simple space-
# separated tokens and single/double-quoted substrings -- sufficient for the fixed
# option strings Re:VIEW ships; not a full shell-word-splitting implementation.
function ConvertTo-ReviewArgv {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }

    $tokens = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingle = $false
    $inDouble = $false
    $hasToken = $false

    foreach ($ch in $CommandLine.ToCharArray()) {
        if ($inSingle) {
            if ($ch -eq "'") { $inSingle = $false } else { [void]$current.Append($ch) }
            continue
        }
        if ($inDouble) {
            if ($ch -eq '"') { $inDouble = $false } else { [void]$current.Append($ch) }
            continue
        }
        if ($ch -eq "'") { $inSingle = $true; $hasToken = $true; continue }
        if ($ch -eq '"') { $inDouble = $true; $hasToken = $true; continue }
        if ($ch -match '\s') {
            if ($hasToken) {
                $tokens.Add($current.ToString())
                [void]$current.Clear()
                $hasToken = $false
            }
            continue
        }
        [void]$current.Append($ch)
        $hasToken = $true
    }
    if ($hasToken) { $tokens.Add($current.ToString()) }

    return $tokens.ToArray()
}
