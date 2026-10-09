$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

# Byte-for-byte comparison of the port's EPUB package against goldens captured from the
# real Ruby `review-epubmaker` 5.9.0 (tests/tools/Update-GoldenFixtures.ps1): every
# generated file (mimetype, container.xml, OPF, nav, cover, title page, chapters) plus
# the zip entry order. No Docker needed -- the EPUB pipeline has no external tools.
$goldenRoot = Join-Path $PSScriptRoot '..\Golden\epub'
$fixtureCases = foreach ($dir in Get-ChildItem -LiteralPath $goldenRoot -Directory) {
    @{ Name = $dir.Name; GoldenDir = $dir.FullName }
}

Describe 'Golden EPUB parity with Ruby Re:VIEW 5.9.0: <Name>' -ForEach $fixtureCases {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $fixtureDir = Join-Path $PSScriptRoot "..\Fixtures\$Name"
        $work = Join-Path $TestDrive "$Name-epub"
        Copy-Item -LiteralPath $fixtureDir -Destination $work -Recurse
        $epub = Invoke-ReviewEpubMaker -Path (Join-Path $work 'config.yml') -KeepBuildDir 3>$null
        $bookname = $epub.BaseName
        $pkgDir = Join-Path $work "$bookname-epub/$bookname-epub"
    }

    It 'produces <_> identical to the oracle' -ForEach @(
        Get-ChildItem -LiteralPath $GoldenDir -Recurse -File |
            Where-Object Name -ne 'entries.txt' |
            ForEach-Object { [IO.Path]::GetRelativePath($GoldenDir, $_.FullName).Replace('\', '/') }
    ) {
        $actualPath = Join-Path $pkgDir $_
        $actualPath | Should -Exist
        [IO.File]::ReadAllText($actualPath) | Should -BeExactly ([IO.File]::ReadAllText((Join-Path $GoldenDir $_)))
    }

    It 'zips the same entries in the same order, mimetype first and stored' {
        $expected = @([IO.File]::ReadAllText((Join-Path $GoldenDir 'entries.txt')).TrimEnd("`n").Split("`n"))
        $zip = [IO.Compression.ZipFile]::OpenRead($epub.FullName)
        try { $actual = @($zip.Entries | ForEach-Object FullName) } finally { $zip.Dispose() }
        $actual | Should -Be $expected

        $bytes = [IO.File]::ReadAllBytes($epub.FullName)
        [BitConverter]::ToUInt16($bytes, 8) | Should -Be 0      # compression method: stored
        [BitConverter]::ToUInt16($bytes, 28) | Should -Be 0     # no extra field
        [Text.Encoding]::ASCII.GetString($bytes, 30, 8) | Should -Be 'mimetype'
        [Text.Encoding]::ASCII.GetString($bytes, 38, 20) | Should -Be 'application/epub+zip'
    }
}
