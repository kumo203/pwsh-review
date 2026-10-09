$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

$dockerAvailable = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)

Describe 'ReviewProcessRunner (real Docker invocation)' -Skip:(-not $dockerAvailable) {
    InModuleScope PwshReview {
        BeforeAll {
            # A tiny, widely-cached image is enough to exercise Run()/RunOrRaise() without
            # needing the (large) review-oracle image built yet -- that full build/run is
            # covered separately once M4 wires PdfMaker against review-oracle:5.9.
            $script:TestImage = 'busybox:latest'
            docker pull $script:TestImage *> $null
        }

        It 'Run() captures merged stdout and a zero exit code on success' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $runner = [ReviewProcessRunner]::new($tmp, $script:TestImage)
                $result = $runner.Run('echo', @('hello-from-container'))
                $result.ExitCode | Should -Be 0
                $result.Success | Should -BeTrue
                $result.Output | Should -Match 'hello-from-container'
            }
            finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }

        It 'RunOrRaise() throws ReviewApplicationError with command + output on nonzero exit' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $runner = [ReviewProcessRunner]::new($tmp, $script:TestImage)
                { $runner.RunOrRaise('sh', @('-c', 'echo failing-output; exit 7')) } | Should -Throw -ExceptionType ([ReviewApplicationError])
            }
            finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }

        It 'AssertDockerReady throws a clear error for a nonexistent image' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $runner = [ReviewProcessRunner]::new($tmp, 'review-oracle-definitely-not-built:999')
                { $runner.AssertDockerReady() } | Should -Throw -ExceptionType ([ReviewApplicationError])
            }
            finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    }
}
