$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

# Byte-for-byte comparison of the port's generated LaTeX against goldens captured from the
# real Ruby Re:VIEW 5.9.0 (tests/tools/Update-GoldenFixtures.ps1). No Docker needed:
# ConvertTo-ReviewLatex stops before the LaTeX toolchain.
$goldenRoot = Join-Path $PSScriptRoot '..\Golden\latex'
$fixtureCases = foreach ($dir in Get-ChildItem -LiteralPath $goldenRoot -Directory) {
    @{ Name = $dir.Name; GoldenDir = $dir.FullName }
}

Describe 'Golden .tex parity with Ruby Re:VIEW 5.9.0: <Name>' -ForEach $fixtureCases {
    BeforeAll {
        $fixtureDir = Join-Path $PSScriptRoot "..\Fixtures\$Name"
        $work = Join-Path $TestDrive $Name
        Copy-Item -LiteralPath $fixtureDir -Destination $work -Recurse
        $out = Join-Path $TestDrive "$Name-tex"
        ConvertTo-ReviewLatex -Path (Join-Path $work 'config.yml') -OutputDirectory $out | Out-Null
    }

    It 'produces <_> identical to the oracle' -ForEach @(Get-ChildItem -LiteralPath $GoldenDir -Filter *.tex | ForEach-Object Name) {
        $actualPath = Join-Path $out $_
        $actualPath | Should -Exist
        $expected = [IO.File]::ReadAllText((Join-Path $GoldenDir $_))
        $actual = [IO.File]::ReadAllText($actualPath)
        $actual | Should -BeExactly $expected
    }
}
