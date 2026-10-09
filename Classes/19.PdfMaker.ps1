# Port of review/lib/review/pdfmaker.rb -- PDF build orchestration. Shells every
# uplatex/mendex/dvipdfmx call into the review-oracle Docker container via
# ReviewProcessRunner (see 20.ExternalProcessRunner.ps1 and the README's "LaTeX
# backend" section) rather than running them as native Windows processes.
#
# Project-local template overrides (<basedir>/layouts/layout.tex.erb,
# layouts/config-local.tex.erb, sty/*.erb) are rendered through ReviewErbLiteTemplate
# (18b.ErbLiteTemplate.ps1); constructs outside its restricted grammar raise a clear
# "unsupported ERB construct" error. Project paths (locale.yml, sty/, layouts/, loose
# *.tex) resolve against BaseDir (the config.yml directory), not Ruby's Dir.pwd.

class ReviewPdfMaker {
    [ReviewConfigure] $Config
    [string] $BaseDir
    [string] $Path
    [string] $MasterTex = '__REVIEW_BOOK__'
    [bool] $CompileErrors = $false
    [string[]] $BuildOnly = $null
    [object] $Converter
    [hashtable] $InputFiles

    [string] $TexCompiler
    [string] $DocumentClass
    [string] $DocumentClassOption
    [string] $Authors
    [string] $Okuduke
    [object] $CustomOriginalTitlePage
    [object] $CustomCreditPage
    [object] $CustomProfilePage
    [object] $CustomAdvFilePage
    [object] $CustomBackCoverPage
    [object] $CustomColophonPage
    [string] $CoverImageOption
    [hashtable] $LocaleLatex
    [object] $BoxSetting
    [ReviewLaTeXEscaper] $Escaper
    [string] $DockerImage = 'review-oracle:5.9'
    [bool] $Debug = $false

    [string] PdfFilePath() {
        return Join-Path $this.BaseDir ("$($this.Config.Get('bookname')).pdf")
    }

    [void] RemoveOldFile() {
        Remove-Item -LiteralPath $this.PdfFilePath() -Force -ErrorAction SilentlyContinue
    }

    [string] BuildPath() {
        if ($this.Config.Get('debug')) {
            # In the project directory rather than Ruby's Dir.pwd -- see GeneratePdf
            $dirName = "$($this.Config.Get('bookname'))-pdf"
            $fullPath = Join-Path $this.BaseDir $dirName
            if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Recurse -Force }
            New-Item -ItemType Directory -Path $fullPath | Out-Null
            return $fullPath
        }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("$($this.Config.Get('bookname'))-pdf-$([guid]::NewGuid().ToString('N').Substring(0,8))")
        New-Item -ItemType Directory -Path $tmp | Out-Null
        return $tmp
    }

    [void] CheckCompileStatus([bool]$IgnoreErrors) {
        if (-not $this.CompileErrors) { return }
        if ($IgnoreErrors) {
            Write-Verbose 'compile error, but try to generate PDF file'
        }
        else {
            throw [ReviewApplicationError]::new('compile error, No PDF file output.')
        }
    }

    [void] Execute([string]$YamlFile, [bool]$DebugFlag, [bool]$IgnoreErrors, [string[]]$OnlyFiles) {
        if (-not (Test-Path -LiteralPath $YamlFile -PathType Leaf)) {
            throw [ReviewApplicationError]::new("$YamlFile not found.")
        }

        $cmdConfig = @{}
        if ($DebugFlag) { $cmdConfig['debug'] = $true }
        if ($IgnoreErrors) { $cmdConfig['ignore-errors'] = $true }
        if ($OnlyFiles) { $this.BuildOnly = @($OnlyFiles | ForEach-Object { $_.Trim() -replace '\.re$', '' }) }

        $this.LoadConfig($YamlFile, $cmdConfig)

        try {
            $this.GeneratePdf()
        }
        catch [ReviewApplicationError] {
            if ($this.Debug) { throw }
            throw [ReviewApplicationError]::new($_.Exception.Message)
        }
    }

    hidden [void] LoadConfig([string]$YamlFile, [hashtable]$CmdConfig) {
        try {
            $this.Config = [ReviewConfigure]::Create('pdfmaker', $YamlFile, $CmdConfig)
        }
        catch [ReviewConfigError] {
            throw [ReviewApplicationError]::new($_.Exception.Message)
        }

        $this.BaseDir = (Resolve-Path -LiteralPath (Split-Path -Parent $YamlFile)).ProviderPath
        # Ruby: I18n.setup(language) reads locale.yml from Dir.pwd (the project dir when
        # review-pdfmaker is run as documented); resolve it against BaseDir instead.
        [ReviewI18n]::Setup([string]$this.Config.Get('language'), (Join-Path $this.BaseDir 'locale.yml'))
        $this.Debug = [bool]$this.Config.Get('debug')

        try {
            $this.Config.CheckVersion([string]$script:ReviewPortedGemVersion)
        }
        catch [ReviewConfigError] {
            Write-Warning $_.Exception.Message
        }

        if (-not $this.Config.Get('texdocumentclass')) {
            $this.Config.Set('texdocumentclass', $this.Config.Get('_texdocumentclass'))
        }
    }

    # Compiles every chapter plus the master __REVIEW_BOOK__.tex into $OutDir WITHOUT
    # running the LaTeX toolchain (no Docker needed) -- backs ConvertTo-ReviewLatex, and
    # makes golden-file comparison against the Ruby oracle possible in plain unit tests.
    [void] ExecuteTexOnly([string]$YamlFile, [string]$OutDir, [bool]$IgnoreErrors) {
        if (-not (Test-Path -LiteralPath $YamlFile -PathType Leaf)) {
            throw [ReviewApplicationError]::new("$YamlFile not found.")
        }
        $cmdConfig = @{}
        if ($IgnoreErrors) { $cmdConfig['ignore-errors'] = $true }
        $this.LoadConfig($YamlFile, $cmdConfig)

        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        $this.Path = (Resolve-Path -LiteralPath $OutDir).ProviderPath
        $this.CompileTexSources()
        Set-Content -LiteralPath (Join-Path $this.Path "$($this.MasterTex).tex") -Value $this.TemplateContent() -NoNewline -Encoding utf8
    }

    hidden [void] CompileTexSources() {
        $this.CompileErrors = $false

        $book = [ReviewBookBase]::new($this.BaseDir, $this.Config)
        $latexBuilder = [ReviewLATEXBuilder]::new()
        $this.Converter = [ReviewConverter]::new($book, $latexBuilder)
        $this.ErbConfig()

        $this.InputFiles = $this.MakeInputFiles($book)

        $this.CheckCompileStatus([bool]$this.Config.Get('ignore-errors'))

        # for backward compatibility
        $styPkg = ''
        if ($this.Config.Get('texstyle')) { $styPkg = "\usepackage{$($this.Config.Get('texstyle'))}" }
        $this.Config.Set('usepackage', $styPkg)
    }

    [hashtable] MakeInputFiles([object]$Book) {
        $files = @{ PREDEF = ''; CHAPS = ''; APPENDIX = ''; POSTDEF = '' }
        foreach ($part in $Book.Parts()) {
            if ($part.Name) {
                $this.Config.Set('use_part', $true)
                if ($part.FileFlag()) {
                    if ($this.BuildOnly -and ($this.BuildOnly -notcontains $part.Name)) {
                        Write-Warning "skip $($part.Name).re"
                        $files['CHAPS'] += "\part{}`n"
                    }
                    else {
                        $this.OutputChaps($part.Name)
                        $files['CHAPS'] += "\input{$($part.Name).tex}`n"
                    }
                }
                else {
                    $files['CHAPS'] += "\part{$($part.Name)}`n"
                }
            }

            foreach ($chap in $part.Chapters) {
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($chap.Path)
                $entry = "\input{$fileName.tex}`n"
                if ($this.BuildOnly -and ($this.BuildOnly -notcontains $fileName)) {
                    Write-Warning "skip $fileName.re"
                    $entry = "\chapter{}`n"
                }
                else {
                    $this.OutputChaps($fileName)
                }

                if ($chap.OnPredef()) { $files['PREDEF'] += $entry }
                if ($chap.OnChaps()) { $files['CHAPS'] += $entry }
                if ($chap.OnAppendix()) { $files['APPENDIX'] += $entry }
                if ($chap.OnPostdef()) { $files['POSTDEF'] += $entry }
            }
        }
        return $files
    }

    [void] OutputChaps([string]$FileName) {
        Write-Verbose "compiling $FileName.tex"
        try {
            $this.Converter.Convert("$FileName.re", (Join-Path $this.Path "$FileName.tex"))
        }
        catch {
            $this.CompileErrors = $true
            Write-Warning "compile error in $FileName.tex ($($_.Exception.GetType().Name))"
            Write-Warning $_.Exception.Message
        }
    }

    [void] GeneratePdf() {
        $this.RemoveOldFile()
        $this.Path = $this.BuildPath()

        try {
            $this.CompileTexSources()

            # Deviation: Ruby reads sty/ and loose *.tex from Dir.pwd, relying on the
            # `cd project && review-pdfmaker config.yml` convention. This port takes an
            # explicit -Path and may be invoked from anywhere, so it uses the project
            # directory (the one containing config.yml) instead.
            $styDir = Join-Path $this.BaseDir 'sty'
            $this.CopyImages([string]$this.Config.Get('imagedir'), (Join-Path $this.Path ([string]$this.Config.Get('imagedir'))))
            $this.CopySty($styDir, $this.Path, 'sty')
            $this.CopySty($styDir, $this.Path, 'fd')
            $this.CopySty($styDir, $this.Path, 'cls')
            $this.CopySty($styDir, $this.Path, 'erb')
            $this.CopySty($styDir, $this.Path, 'tex')
            $this.CopySty($this.BaseDir, $this.Path, 'tex')
            $this.CopyBundledStyFiles()

            $this.BuildPdf()

            Copy-Item -LiteralPath (Join-Path $this.Path "$($this.MasterTex).pdf") -Destination $this.PdfFilePath() -Force
            Write-Verbose "built $(Split-Path -Leaf $this.PdfFilePath())"
        }
        finally {
            if (-not $this.Debug) {
                Remove-Item -LiteralPath $this.Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Copies the bundled review-jsbook .sty/.cls/.fd resources (Resources/latex/
    # review-jsbook/*) into the build dir -- the PowerShell-port equivalent of Ruby's
    # gem shipping templates/latex/review-jsbook/* as part of its own load path, which
    # the project-local copy_sty calls (above) layer project overrides on top of.
    [void] CopyBundledStyFiles() {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $bundled = Join-Path $moduleRoot 'Resources\latex\review-jsbook'
        if (-not (Test-Path -LiteralPath $bundled)) { return }
        foreach ($f in Get-ChildItem -LiteralPath $bundled -File) {
            $dest = Join-Path $this.Path $f.Name
            if (-not (Test-Path -LiteralPath $dest)) {
                Copy-Item -LiteralPath $f.FullName -Destination $dest
            }
        }
    }

    [void] CopyImages([string]$From, [string]$To) {
        $fromPath = Join-Path $this.BaseDir $From
        if (-not (Test-Path -LiteralPath $fromPath)) { return }
        New-Item -ItemType Directory -Path $To -Force | Out-Null
        $this.CopyImagesToDirRecursive($fromPath, $To)
    }

    hidden [void] CopyImagesToDirRecursive([string]$FromDir, [string]$ToDir) {
        $exts = @('.png', '.gif', '.jpg', '.jpeg', '.svg', '.pdf', '.eps', '.ai', '.tif', '.psd')
        foreach ($entry in Get-ChildItem -LiteralPath $FromDir -Force) {
            if ($entry.Name.StartsWith('.')) { continue }
            if ($entry.PSIsContainer) {
                $this.CopyImagesToDirRecursive($entry.FullName, (Join-Path $ToDir $entry.Name))
            }
            else {
                if ($exts -contains $entry.Extension.ToLowerInvariant()) {
                    New-Item -ItemType Directory -Path $ToDir -Force | Out-Null
                    Copy-Item -LiteralPath $entry.FullName -Destination $ToDir
                }
            }
        }
    }

    [object] MakeCustomPage([object]$FileArg) {
        if (-not $FileArg) { return $null }
        $fileSty = [string]$FileArg -replace '\.[^.]+$', '.tex'
        $fullPath = Join-Path $this.BaseDir $fileSty
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            return Get-Content -LiteralPath $fullPath -Raw
        }
        Write-Warning "File $fileSty is not found."
        return $null
    }

    hidden [string] JoinWithSeparator([object]$Value, [string]$Sep) {
        if ($Value -is [System.Collections.IList]) { return ($Value -join $Sep) }
        return [string]$Value
    }

    hidden [string] MakeColophonRole([string]$Role) {
        if ($this.Config.Get($Role)) {
            $names = $this.JoinWithSeparator($this.Config.NamesOf($Role), [ReviewI18n]::T('names_splitter'))
            return "$([ReviewI18n]::T($Role)) & $($this.Escaper.Escape($names)) \\`n"
        }
        return ''
    }

    [string] MakeColophon() {
        $colophonText = [System.Text.StringBuilder]::new()
        foreach ($role in @($this.Config.Get('colophon_order'))) {
            [void]$colophonText.Append($this.MakeColophonRole($role))
        }
        return $colophonText.ToString()
    }

    [string] MakeAuthors() {
        $authorsText = ''
        if ($this.Config.Get('aut')) {
            $autNames = $this.JoinWithSeparator(($this.Config.NamesOf('aut') | ForEach-Object { $this.Escaper.Escape($_) }), [ReviewI18n]::T('names_splitter'))
            $authorsText = [ReviewI18n]::T('author_with_label', $autNames)
        }
        if ($this.Config.Get('csl')) {
            $cslNames = $this.JoinWithSeparator(($this.Config.NamesOf('csl') | ForEach-Object { $this.Escaper.Escape($_) }), [ReviewI18n]::T('names_splitter'))
            $authorsText += " \\`n" + [ReviewI18n]::T('supervisor_with_label', $cslNames)
        }
        if ($this.Config.Get('trl')) {
            $trlNames = $this.JoinWithSeparator(($this.Config.NamesOf('trl') | ForEach-Object { $this.Escaper.Escape($_) }), [ReviewI18n]::T('names_splitter'))
            $authorsText += " \\`n" + [ReviewI18n]::T('translator_with_label', $trlNames)
        }
        return $authorsText
    }

    [string] DateToS([string]$DateStr) {
        $parsed = [datetime]::Parse($DateStr, [System.Globalization.CultureInfo]::InvariantCulture)
        $format = [ReviewI18n]::T('date_format')
        return [ReviewI18n]::Strftime($parsed, $format)
    }

    [string[]] MakeHistoryList() {
        $buf = [System.Collections.Generic.List[string]]::new()
        $history = $this.Config.Get('history')
        if ($history) {
            for ($edit = 0; $edit -lt $history.Count; $edit++) {
                $items = @($history[$edit])
                for ($rev = 0; $rev -lt $items.Count; $rev++) {
                    $item = [string]$items[$rev]
                    $editStr = if ($edit -eq 0) { [ReviewI18n]::T('first_edition') } else { [ReviewI18n]::T('nth_edition', [string]($edit + 1)) }
                    $revStr = [ReviewI18n]::T('nth_impression', [string]($rev + 1))
                    if ($item -match '^\d+-\d+-\d+$') {
                        # parenthesized: in @($a, $b + $c) the comma binds tighter than +, giving @($a, $b) + $c
                        $buf.Add([ReviewI18n]::T('published_by1', @($this.DateToS($item), ($editStr + $revStr))))
                    }
                    elseif ($item -match '^(\d+-\d+-\d+)[\s　](.+)') {
                        $buf.Add([ReviewI18n]::T('published_by3', @($this.DateToS($Matches[1]), $Matches[2])))
                    }
                    else {
                        $buf.Add($item)
                    }
                }
            }
        }
        elseif ($this.Config.Get('date')) {
            $buf.Add([ReviewI18n]::T('published_by2', $this.DateToS([string]$this.Config.Get('date'))))
        }
        return $buf.ToArray()
    }

    [void] ErbConfig() {
        $this.TexCompiler = [System.IO.Path]::GetFileNameWithoutExtension([string]$this.Config.Get('texcommand'))
        $this.Escaper = [ReviewLaTeXEscaper]::new([string]$this.Config.Get('texcommand'))
        $docClassCfg = @($this.Config.Get('texdocumentclass'))
        $this.DocumentClass = if ($docClassCfg.Count -gt 0 -and $docClassCfg[0]) { $docClassCfg[0] } else { 'review-jsbook' }
        $this.DocumentClassOption = if ($docClassCfg.Count -gt 1 -and $docClassCfg[1]) { $docClassCfg[1] } else { '' }
        if ([string]$this.Config.Get('dvicommand') -match 'dvipdfmx' -and $this.DocumentClassOption -notmatch 'dvipdfmx') {
            $this.DocumentClassOption = ("dvipdfmx,$($this.DocumentClassOption)" -replace ',$', '')
        }

        $this.Okuduke = $this.MakeColophon()
        $this.Authors = $this.MakeAuthors()

        $this.CustomOriginalTitlePage = $this.MakeCustomPage($this.Config.Get('originaltitlefile'))
        $this.CustomCreditPage = $this.MakeCustomPage($this.Config.Get('creditfile'))
        $this.CustomProfilePage = $this.MakeCustomPage($this.Config.Get('profile'))
        $this.CustomAdvFilePage = $this.MakeCustomPage($this.Config.Get('advfile'))
        if ($this.Config.Get('colophon') -is [string]) {
            $this.CustomColophonPage = $this.MakeCustomPage($this.Config.Get('colophon'))
        }
        $this.CustomBackCoverPage = $this.MakeCustomPage($this.Config.Get('backcover'))

        if ($this.Config.Get('pubhistory')) {
            Write-Warning 'pubhistory is oboleted. use history.'
        }
        else {
            $this.Config.Set('pubhistory', ($this.MakeHistoryList() -join "`n"))
        }

        $this.CoverImageOption = if ($this.DocumentClass -eq 'ubook' -or $this.DocumentClass -eq 'utbook') { 'keepaspectratio,angle=90' } else { 'keepaspectratio' }
        if ($this.Config.CheckVersion('2', $false)) {
            $this.CoverImageOption = if ($this.DocumentClass -eq 'ubook' -or $this.DocumentClass -eq 'utbook') { 'width=\textheight,height=\textwidth,keepaspectratio,angle=90' } else { 'width=\textwidth,height=\textheight,keepaspectratio' }
        }

        if ($this.Config.Get('coverimage')) {
            $coverImgPath = Join-Path (Join-Path $this.BaseDir ([string]$this.Config.Get('imagedir'))) ([string]$this.Config.Get('coverimage'))
            if (-not (Test-Path -LiteralPath $coverImgPath)) {
                throw [ReviewConfigError]::new("coverimage $($this.Config.Get('coverimage')) is not found.")
            }
        }

        $this.LocaleLatex = @{}
        $partTuple = [regex]::Split([ReviewI18n]::Instance.Get('part'), '%[A-Za-z]{1,3}', 2)
        $chapterTuple = [regex]::Split([ReviewI18n]::Instance.Get('chapter'), '%[A-Za-z]{1,3}', 2)
        $appendixTuple = [regex]::Split([ReviewI18n]::Instance.Get('appendix'), '%[A-Za-z]{1,3}', 2)
        $this.LocaleLatex['prepartname'] = [string]$partTuple[0]
        $this.LocaleLatex['postpartname'] = [string]$(if ($partTuple.Count -gt 1) { $partTuple[1] } else { '' })
        $this.LocaleLatex['prechaptername'] = [string]$chapterTuple[0]
        $this.LocaleLatex['postchaptername'] = [string]$(if ($chapterTuple.Count -gt 1) { $chapterTuple[1] } else { '' })
        $this.LocaleLatex['preappendixname'] = [string]$appendixTuple[0]
        $this.LocaleLatex['postappendixname'] = [string]$(if ($appendixTuple.Count -gt 1) { $appendixTuple[1] } else { '' })

        $pdfmakerCfg = $this.Config.Get('pdfmaker')
        if ($pdfmakerCfg -and $pdfmakerCfg['boxsetting']) {
            $box = [ReviewLaTeXBox]::new()
            $this.BoxSetting = $box.Tcbox($this.Config)
        }
    }

    # The variables Ruby's ERB templates see via `binding` inside PDFMaker (its instance
    # variables plus the latex_config helper), for project-local .erb overrides rendered
    # by the restricted ReviewErbLiteTemplate interpreter.
    hidden [hashtable] ErbBinding() {
        $self = $this   # NOT $this inside the scriptblock below -- see 13.Compiler.ps1
        $binding = [hashtable]::new([System.StringComparer]::Ordinal)
        $binding['@config'] = $this.Config
        $binding['@texcompiler'] = $this.TexCompiler
        $binding['@documentclass'] = $this.DocumentClass
        $binding['@documentclassoption'] = $this.DocumentClassOption
        $binding['@authors'] = $this.Authors
        $binding['@okuduke'] = $this.Okuduke
        $binding['@custom_originaltitlepage'] = $this.CustomOriginalTitlePage
        $binding['@custom_creditpage'] = $this.CustomCreditPage
        $binding['@custom_profilepage'] = $this.CustomProfilePage
        $binding['@custom_advfilepage'] = $this.CustomAdvFilePage
        $binding['@custom_backcoverpage'] = $this.CustomBackCoverPage
        $binding['@custom_colophonpage'] = $this.CustomColophonPage
        $binding['@coverimageoption'] = $this.CoverImageOption
        $binding['@locale_latex'] = $this.LocaleLatex
        $binding['@boxsetting'] = $this.BoxSetting
        $binding['@input_files'] = $this.InputFiles
        $binding['latex_config'] = { $self.LatexConfig() }.GetNewClosure()
        $binding['__basedir'] = $this.BaseDir
        return $binding
    }

    hidden [string] RenderProjectErb([string]$Path) {
        $src = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        $tpl = [ReviewErbLiteTemplate]::new($src, $Path)
        return $tpl.Render($this.ErbBinding(), $this.Escaper)
    }

    [string] LatexConfig() {
        $result = New-ReviewLatexConfigBlock -Maker $this
        $localConfigFile = Join-Path $this.BaseDir 'layouts\config-local.tex.erb'
        if (Test-Path -LiteralPath $localConfigFile -PathType Leaf) {
            $result += "%% BEGIN: config-local.tex.erb`n"
            $result += $this.RenderProjectErb($localConfigFile)
            $result += "%% END: config-local.tex.erb`n"
        }
        return $result
    }

    [string] TemplateContent() {
        $coverFile = $this.Config.Get('cover')
        if ($coverFile -and -not (Test-Path -LiteralPath (Join-Path $this.BaseDir $coverFile))) {
            throw [ReviewApplicationError]::new("File $coverFile is not found.")
        }
        $titleFile = $this.Config.Get('titlefile')
        if ($this.Config.Get('titlepage') -and $titleFile -and -not (Test-Path -LiteralPath (Join-Path $this.BaseDir $titleFile))) {
            throw [ReviewApplicationError]::new("File $titleFile is not found.")
        }

        $layoutFile = Join-Path $this.BaseDir 'layouts\layout.tex.erb'
        if (Test-Path -LiteralPath $layoutFile -PathType Leaf) {
            return $this.RenderProjectErb($layoutFile)
        }

        $configBlock = $this.LatexConfig()
        return New-ReviewLatexLayout -Maker $this -ConfigBlock $configBlock
    }

    [void] CopySty([string]$DirName, [string]$CopyBase, [string]$ExtName) {
        if (-not (Test-Path -LiteralPath $DirName -PathType Container)) { return }
        $matchExt = ".$ExtName"
        $files = Get-ChildItem -LiteralPath $DirName -File | Where-Object { $_.Extension.ToLowerInvariant() -eq $matchExt.ToLowerInvariant() } | Sort-Object Name
        foreach ($f in $files) {
            New-Item -ItemType Directory -Path $CopyBase -Force | Out-Null
            if ($ExtName -eq 'erb') {
                # Deliberate fix, not a port: Ruby 5.9.0 calls an erb_content method here
                # that is never defined anywhere (NameError if a project ever has a
                # sty/*.erb). This renders it with the same binding as the layouts.
                $target = Join-Path $CopyBase ($f.Name -replace '\.erb$', '')
                Set-Content -LiteralPath $target -Value $this.RenderProjectErb($f.FullName) -NoNewline -Encoding utf8
            }
            else {
                Copy-Item -LiteralPath $f.FullName -Destination $CopyBase -Force
            }
        }
    }

    [void] CallHook([string]$HookName, [string[]]$HookParams) {
        $maker = $this.Config.Maker
        $pdfCfg = $this.Config.Get($maker)
        $fileName = if ($pdfCfg) { $pdfCfg[$HookName] } else { $null }
        if (-not $fileName) { return }

        $hook = Join-Path $this.BaseDir $fileName
        if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) { return }
        & $hook @HookParams
    }

    [void] BuildPdf() {
        $template = $this.TemplateContent()
        Push-Location $this.Path
        try {
            Set-Content -LiteralPath "./$($this.MasterTex).tex" -Value $template -NoNewline -Encoding utf8

            $this.CallHook('hook_beforetexcompile', @((Get-Location).Path, $this.BaseDir))

            if (-not $this.Config.Get('texcommand')) {
                throw [ReviewApplicationError]::new("texcommand isn't defined.")
            }
            $texCommand = [string]$this.Config.Get('texcommand')
            $dviCommand = [string]$this.Config.Get('dvicommand')
            $dviOptions = ConvertTo-ReviewArgv ([string]$this.Config.Get('dvioptions'))
            $texOptions = ConvertTo-ReviewArgv ([string]$this.Config.Get('texoptions'))
            $pdfCfg = $this.Config.Get('pdfmaker')
            $makeindexCommand = [string]$pdfCfg['makeindex_command']
            # [string[]] cast is required, not cosmetic: a plain @(...) wrap still
            # produces a System.Object[], which does NOT bind to the generic
            # List<string>(IEnumerable<string>) constructor overload even when every
            # element is actually a string -- confirmed empirically ("Cannot find an
            # overload for 'new' and the argument count: 1", a misleading message for
            # what's actually a type-mismatch, not an arity mismatch).
            $makeindexOptions = [System.Collections.Generic.List[string]]::new([string[]](ConvertTo-ReviewArgv ([string]$pdfCfg['makeindex_options'])))
            $makeindexSty = $pdfCfg['makeindex_sty']
            $makeindexDic = $pdfCfg['makeindex_dic']

            # Deviation from Ruby (which passes an absolute path, e.g. /work/syntax.dic):
            # only the BUILD directory is mounted into the Docker container, so a host
            # path to the project's style/dictionary file doesn't exist in there. Copy it
            # into the build dir and pass a container-relative name instead.
            if ($makeindexSty) {
                $styFull = Join-Path $this.BaseDir $makeindexSty
                if (Test-Path -LiteralPath $styFull) {
                    $styName = '__review_makeindex' + [System.IO.Path]::GetExtension($styFull)
                    Copy-Item -LiteralPath $styFull -Destination (Join-Path $this.Path $styName) -Force
                    $makeindexOptions.Add('-s'); $makeindexOptions.Add($styName)
                }
            }
            if ($makeindexDic) {
                $dicFull = Join-Path $this.BaseDir $makeindexDic
                if (Test-Path -LiteralPath $dicFull) {
                    $dicName = '__review_makeindex_dic' + [System.IO.Path]::GetExtension($dicFull)
                    Copy-Item -LiteralPath $dicFull -Destination (Join-Path $this.Path $dicName) -Force
                    $makeindexOptions.Add('-d'); $makeindexOptions.Add($dicName)
                }
            }

            $runner = [ReviewProcessRunner]::new($this.Path, $this.DockerImage)
            $runner.AssertDockerReady()

            1..2 | ForEach-Object {
                [void]$runner.RunOrRaise($texCommand, (@($texOptions) + @("$($this.MasterTex).tex")))
            }

            $this.CallHook('hook_beforemakeindex', @((Get-Location).Path, $this.BaseDir))
            $idxPath = "$($this.MasterTex).idx"
            if ($pdfCfg['makeindex'] -and (Test-Path -LiteralPath $idxPath) -and (Get-Item -LiteralPath $idxPath).Length -gt 0) {
                [void]$runner.RunOrRaise($makeindexCommand, (@($makeindexOptions.ToArray()) + @($this.MasterTex)))
                $this.CallHook('hook_aftermakeindex', @((Get-Location).Path, $this.BaseDir))
                [void]$runner.RunOrRaise($texCommand, (@($texOptions) + @("$($this.MasterTex).tex")))
            }

            [void]$runner.RunOrRaise($texCommand, (@($texOptions) + @("$($this.MasterTex).tex")))
            $this.CallHook('hook_aftertexcompile', @((Get-Location).Path, $this.BaseDir))

            if ((Test-Path -LiteralPath "$($this.MasterTex).dvi") -and $dviCommand) {
                [void]$runner.RunOrRaise($dviCommand, (@($dviOptions) + @("$($this.MasterTex).dvi")))
                $this.CallHook('hook_afterdvipdf', @((Get-Location).Path, $this.BaseDir))
            }
        }
        finally {
            Pop-Location
        }
    }
}
