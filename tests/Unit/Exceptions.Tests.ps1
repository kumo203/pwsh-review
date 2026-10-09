$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'Exception hierarchy' {
    InModuleScope PwshReview {
        It 'mirrors review/lib/review/exception.rb Error -> ApplicationError -> * chain' {
            [ReviewApplicationError]::new('x') | Should -BeOfType ([ReviewError])
            [ReviewConfigError]::new('x') | Should -BeOfType ([ReviewApplicationError])
            [ReviewCompileError]::new('x') | Should -BeOfType ([ReviewApplicationError])
            [ReviewSyntaxError]::new('x') | Should -BeOfType ([ReviewCompileError])
            [ReviewKeyError]::new('x') | Should -BeOfType ([ReviewCompileError])
            [ReviewFileNotFoundError]::new('x') | Should -BeOfType ([ReviewApplicationError])
        }

        It 'ReviewBuildError carries a Location property like Ruby''s location: kwarg' {
            $e = [ReviewBuildError]::new('boom', 'chapter1.re:12')
            $e.Message | Should -Be 'boom'
            $e.Location | Should -Be 'chapter1.re:12'
            $e | Should -BeOfType ([ReviewApplicationError])
        }

        It 'can be caught by its base type, same as Ruby rescue ReVIEW::ApplicationError' {
            $caught = $null
            try {
                throw [ReviewSyntaxError]::new('bad char')
            }
            catch [ReviewApplicationError] {
                $caught = $_.Exception
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Message | Should -Be 'bad char'
        }
    }
}
