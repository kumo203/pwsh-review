# External process runner for the LaTeX toolchain (uplatex/mendex/dvipdfmx).
#
# Mirrors review/lib/review/pdfmaker.rb's system_with_info/system_or_raise, both of which
# wrap Open3.capture2e (merged stdout+stderr, no stdin) around a single external command.
#
# Two backends, differing only in transport (PdfMaker.BuildPdf's sequencing and error
# handling are identical either way):
#
# - 'Docker' (default on a host): plain Windows has no uplatex/dvipdfmx/mendex on PATH,
#   and a native TeX Live/MiKTeX install is a multi-GB ask we're avoiding. So each command
#   runs *inside* a TeX container via
#   `docker run --rm -v <WorkDir>:/work -w /work <DockerImage> <command> <args...>`,
#   with WorkDir being the per-build directory Ruby's PDFMaker would Dir.chdir into.
# - 'Native': the command runs directly with WorkDir as its working directory, exactly
#   like Ruby. Used inside the pwsh-review Docker image (docker/), which bundles TeX Live
#   and sets PWSHREVIEW_LATEX_BACKEND=Native.

enum ReviewLatexBackend {
    Docker
    Native
}

class ReviewProcessResult {
    [string]   $CommandLine
    [string]   $Output
    [int]      $ExitCode
    [bool]     $Success
}

class ReviewProcessRunner {
    [string] $DockerImage = 'review-oracle:5.9'
    [string] $WorkDir
    [ReviewLatexBackend] $Backend = [ReviewLatexBackend]::Docker

    ReviewProcessRunner([string]$WorkDir) {
        $this.WorkDir = $WorkDir
    }

    ReviewProcessRunner([string]$WorkDir, [string]$DockerImage) {
        $this.WorkDir = $WorkDir
        $this.DockerImage = $DockerImage
    }

    ReviewProcessRunner([string]$WorkDir, [string]$DockerImage, [ReviewLatexBackend]$Backend) {
        $this.WorkDir = $WorkDir
        $this.DockerImage = $DockerImage
        $this.Backend = $Backend
    }

    # The backend selected by $env:PWSHREVIEW_LATEX_BACKEND ('Docker' or 'Native'),
    # defaulting to Docker when unset.
    static [ReviewLatexBackend] DefaultBackend() {
        $fromEnv = $env:PWSHREVIEW_LATEX_BACKEND
        if ([string]::IsNullOrWhiteSpace($fromEnv)) { return [ReviewLatexBackend]::Docker }
        $parsed = [ReviewLatexBackend]::Docker
        if (-not [Enum]::TryParse([ReviewLatexBackend], $fromEnv, $true, [ref]$parsed)) {
            throw [ReviewApplicationError]::new("PWSHREVIEW_LATEX_BACKEND must be 'Docker' or 'Native', got '$fromEnv'.")
        }
        return $parsed
    }

    # Verifies the selected backend can run commands before a build starts.
    [void] AssertReady() {
        if ($this.Backend -eq [ReviewLatexBackend]::Native) {
            if (-not (Get-Command uplatex -CommandType Application -ErrorAction SilentlyContinue)) {
                throw [ReviewApplicationError]::new('Native LaTeX backend selected but uplatex is not on PATH. Install TeX Live, or use the Docker backend.')
            }
            return
        }
        $this.AssertDockerReady()
    }

    # Verifies `docker` is reachable and that $DockerImage exists locally, raising a clear
    # ReviewApplicationError (rather than failing deep inside a texcommand call) if not.
    [void] AssertDockerReady() {
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
        if (-not $dockerCmd) {
            throw [ReviewApplicationError]::new('Docker CLI not found on PATH. Install Docker Desktop to run the LaTeX toolchain backend.')
        }

        $null = & docker image inspect $this.DockerImage 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw [ReviewApplicationError]::new(
                "Docker image '$($this.DockerImage)' not found locally. Build it with:`n" +
                "  docker build -t $($this.DockerImage) docker-review\review-5.9`n" +
                "or pull it with:`n" +
                "  docker pull vvakame/review:5.9 ; docker tag vvakame/review:5.9 $($this.DockerImage)"
            )
        }
    }

    hidden [string[]] BuildDockerArgs([string]$Command, [string[]]$Arguments) {
        $dockerArgs = [System.Collections.Generic.List[string]]::new()
        $dockerArgs.Add('run')
        $dockerArgs.Add('--rm')
        $dockerArgs.Add('-v')
        $dockerArgs.Add("$($this.WorkDir):/work")
        $dockerArgs.Add('-w')
        $dockerArgs.Add('/work')
        $dockerArgs.Add($this.DockerImage)
        $dockerArgs.Add($Command)
        foreach ($a in $Arguments) { $dockerArgs.Add($a) }
        return $dockerArgs.ToArray()
    }

    # Runs one command inside the container and returns the merged-output result.
    # Never writes to the child process's stdin, mirroring Open3.capture2e.
    #
    # Deviation from Ruby: Open3.capture2e merges stdout+stderr into one OS-level pipe,
    # preserving true chronological interleaving. .NET's Process class exposes stdout and
    # stderr as two separate streams with no equivalent single-pipe merge, and an
    # event-driven (OutputDataReceived/ErrorDataReceived) merge attempt proved unreliable
    # here (closures over local StringBuilder state did not reliably fire). Instead, both
    # streams are read fully and asynchronously via ReadToEndAsync (started before
    # WaitForExit to avoid the classic deadlock-on-full-pipe-buffer problem), then
    # concatenated stdout-then-stderr. This loses exact interleaving order but preserves
    # full content, which is what RunOrRaise's error messages and golden-diff log
    # comparisons actually depend on.
    [ReviewProcessResult] Run([string]$Command, [string[]]$Arguments) {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        if ($this.Backend -eq [ReviewLatexBackend]::Native) {
            $psi.FileName = $Command
            $psi.WorkingDirectory = $this.WorkDir
            foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
            $commandLine = "$Command $($Arguments -join ' ')"
        }
        else {
            $dockerArgs = $this.BuildDockerArgs($Command, $Arguments)
            $psi.FileName = 'docker'
            foreach ($a in $dockerArgs) { $psi.ArgumentList.Add($a) }
            $commandLine = "docker $($dockerArgs -join ' ')"
        }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $false
        $psi.UseShellExecute = $false

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi

        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        $result = [ReviewProcessResult]::new()
        $result.CommandLine = $commandLine
        $result.Output = $stdout + $stderr
        $result.ExitCode = $process.ExitCode
        $result.Success = ($process.ExitCode -eq 0)
        return $result
    }

    # Mirrors system_or_raise: hard failure, throws with the command line + merged output.
    [ReviewProcessResult] RunOrRaise([string]$Command, [string[]]$Arguments) {
        Write-Verbose "$Command $($Arguments -join ' ')"
        $result = $this.Run($Command, $Arguments)
        if (-not $result.Success) {
            throw [ReviewApplicationError]::new("failed to run command: $($result.CommandLine)`n`nError log:`n$($result.Output)")
        }
        return $result
    }

    # Mirrors system_with_info: logs on failure (via Write-Warning), does not throw.
    [ReviewProcessResult] RunWithInfo([string]$Command, [string[]]$Arguments) {
        Write-Verbose "$Command $($Arguments -join ' ')"
        $result = $this.Run($Command, $Arguments)
        if (-not $result.Success) {
            Write-Warning "execution error`n`nError log:`n$($result.Output)"
        }
        return $result
    }
}
