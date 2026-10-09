$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'ReviewProcessRunner (pure logic, no Docker invoked)' {
    InModuleScope PwshReview {
        It 'defaults to the review-oracle:5.9 image' {
            $runner = [ReviewProcessRunner]::new('C:\work')
            $runner.DockerImage | Should -Be 'review-oracle:5.9'
        }

        It 'accepts an overridden image tag' {
            $runner = [ReviewProcessRunner]::new('C:\work', 'review-oracle:5.3')
            $runner.DockerImage | Should -Be 'review-oracle:5.3'
        }

        It 'builds docker run args mounting WorkDir at /work and setting it as the working dir' {
            $runner = [ReviewProcessRunner]::new('C:\build\abc123')
            $args = $runner.BuildDockerArgs('uplatex', @('-interaction=nonstopmode', '__REVIEW_BOOK__.tex'))
            $args | Should -Be @(
                'run', '--rm',
                '-v', 'C:\build\abc123:/work',
                '-w', '/work',
                'review-oracle:5.9',
                'uplatex',
                '-interaction=nonstopmode',
                '__REVIEW_BOOK__.tex'
            )
        }

        It 'passes through commands with no extra arguments' {
            $runner = [ReviewProcessRunner]::new('C:\build\abc123')
            $args = $runner.BuildDockerArgs('mendex', @())
            $args | Should -Be @('run', '--rm', '-v', 'C:\build\abc123:/work', '-w', '/work', 'review-oracle:5.9', 'mendex')
        }
    }
}
