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

        It 'selects the backend from PWSHREVIEW_LATEX_BACKEND (default Docker)' {
            $saved = $env:PWSHREVIEW_LATEX_BACKEND
            try {
                $env:PWSHREVIEW_LATEX_BACKEND = $null
                [ReviewProcessRunner]::DefaultBackend() | Should -Be ([ReviewLatexBackend]::Docker)
                $env:PWSHREVIEW_LATEX_BACKEND = 'native'
                [ReviewProcessRunner]::DefaultBackend() | Should -Be ([ReviewLatexBackend]::Native)
                $env:PWSHREVIEW_LATEX_BACKEND = 'bogus'
                { [ReviewProcessRunner]::DefaultBackend() } | Should -Throw -ExceptionType ([ReviewApplicationError])
            }
            finally { $env:PWSHREVIEW_LATEX_BACKEND = $saved }
        }

        It 'runs a command directly in WorkDir with the Native backend' {
            $runner = [ReviewProcessRunner]::new($TestDrive, '', [ReviewLatexBackend]::Native)
            $pwshPath = (Get-Process -Id $PID).Path
            $result = $runner.Run($pwshPath, @('-NoProfile', '-Command', '(Get-Location).Path; exit 3'))
            $result.Output.Trim() | Should -Be (Resolve-Path $TestDrive).ProviderPath
            $result.ExitCode | Should -Be 3
            $result.Success | Should -BeFalse
        }
    }
}
