$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'ReviewConfigure' {
    InModuleScope PwshReview {
        It 'Values() returns the documented defaults' {
            $conf = [ReviewConfigure]::Values()
            $conf.Get('bookname') | Should -Be 'book'
            $conf.Get('texcommand') | Should -Be 'uplatex'
            $conf.Get('dvicommand') | Should -Be 'dvipdfmx'
            $conf.Get('secnolevel') | Should -Be 2
            $conf.Get('nonexistent-key') | Should -BeNullOrEmpty
        }

        It 'Create() deep-merges YAML over defaults, and CLI config over that' {
            $dir = Join-Path $TestDrive 'create1'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -Path "$dir\config.yml" -Value @'
review_version: 5
bookname: mybook
pdfmaker:
  makeindex: true
'@
            $conf = [ReviewConfigure]::Create('pdfmaker', "$dir\config.yml", @{ bookname = 'overridden-by-cli' })
            $conf.Get('bookname') | Should -Be 'overridden-by-cli'
            $conf.Get('texcommand') | Should -Be 'uplatex'
        }

        It 'Get() applies maker-specific shadowing before the top-level value' {
            $conf = [ReviewConfigure]::Values()
            $conf.Maker = 'pdfmaker'
            $conf.Set('colophon', $false)
            $conf.Set('pdfmaker', @{ colophon = $true })
            $conf.Get('colophon') | Should -BeTrue

            $conf.Maker = $null
            $conf.Get('colophon') | Should -BeFalse
        }

        It 'MigrateParameters converts known string fields to single-element arrays' {
            $conf = [ReviewConfigure]::Values()
            $conf.Set('aut', 'Jane Doe')
            $conf.MigrateParameters()
            , $conf.Get('aut') | Should -Be @('Jane Doe')
        }

        It 'CheckVersion raises when review_version is missing' {
            $conf = [ReviewConfigure]::Values()
            { $conf.CheckVersion('5.9.0') } | Should -Throw -ExceptionType ([ReviewConfigError])
        }

        It 'CheckVersion raises on a major version mismatch' {
            $conf = [ReviewConfigure]::Values()
            $conf.Set('review_version', '4')
            { $conf.CheckVersion('5.9.0') } | Should -Throw -ExceptionType ([ReviewConfigError])
        }

        It 'CheckVersion passes when major versions match' {
            $conf = [ReviewConfigure]::Values()
            $conf.Set('review_version', '5.0')
            $conf.CheckVersion('5.9.0') | Should -BeTrue
        }

        It 'NamesOf flattens an array of name hashtables' {
            $conf = [ReviewConfigure]::Values()
            $conf.Set('aut', @(@{ name = 'Alice' }, @{ name = 'Bob' }))
            $conf.NamesOf('aut') | Should -Be @('Alice', 'Bob')
        }
    }
}

Describe 'ReviewYamlLoader' {
    InModuleScope PwshReview {
        It 'inherit chain-merges with the original file winning over inherited files' {
            $dir = Join-Path $TestDrive 'inherit1'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -Path "$dir\base.yml" -Value @'
texstyle: ["base-style"]
shared: from-base
'@
            Set-Content -Path "$dir\child.yml" -Value @'
inherit: ["base.yml"]
texstyle: ["child-style"]
'@
            $loader = [ReviewYamlLoader]::new()
            $result = $loader.LoadFile("$dir\child.yml")
            $result['texstyle'] | Should -Be @('child-style')
            $result['shared'] | Should -Be 'from-base'
            $result.ContainsKey('inherit') | Should -BeFalse
        }

        It 'raises on circular inheritance' {
            $dir = Join-Path $TestDrive 'circular1'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -Path "$dir\a.yml" -Value "inherit: [`"b.yml`"]`nx: 1"
            Set-Content -Path "$dir\b.yml" -Value "inherit: [`"a.yml`"]`ny: 2"
            $loader = [ReviewYamlLoader]::new()
            { $loader.LoadFile("$dir\a.yml") } | Should -Throw
        }

        It 'DeepMerge recurses into nested hashtables, overwrites arrays wholesale' {
            $base = @{ a = 1; nested = @{ x = 1; y = 2 }; arr = @(1, 2) }
            $over = @{ nested = @{ y = 20 }; arr = @(9) }
            $merged = [ReviewYamlLoader]::DeepMerge($base, $over)
            $merged['a'] | Should -Be 1
            $merged['nested']['x'] | Should -Be 1
            $merged['nested']['y'] | Should -Be 20
            , $merged['arr'] | Should -Be @(9)
        }
    }
}
