# Port of review/lib/review/epubmaker.rb plus epubmaker/{producer,content,epubcommon,
# epubv3,zip_exporter,reviewheaderlistener}.rb and htmltoc.rb (Re:VIEW 5.9.0) -- builds an
# EPUB3 from a Re:VIEW project. Chapter pages come from ReviewHTMLBuilder; the bundled
# ERB templates (cover, title page, part page, colophon, OPF, nav, container.xml) are
# hand-ported below (ERB trim mode '>' semantics), like the LaTeX ones.
#
# Scope: EPUB3 only (epubversion: 2 raises an error). The zip is written with
# System.IO.Compression (mimetype first, stored), so EPUB needs no Docker or external
# tools. Not ported: the image_size check (warnings only in Ruby), math_format
# mathml/imgmath, //graph, the legacy coverfile/titlepagefile/backcoverfile/pubhistory
# parameters (warned and ignored).
#
# Deviations: project paths (stylesheets, images, cover/title files, locale.yml) and the
# output .epub / debug directory resolve against the config.yml directory instead of
# Ruby's Dir.pwd -- identical when Ruby is run from the project directory.

class ReviewEpubContent {
    [string] $Id
    [string] $File
    [string] $Media
    [string] $Title
    [object] $Level
    [object] $Notoc
    [System.Collections.Generic.List[string]] $Properties
    [string] $Chaptype

    ReviewEpubContent([string]$File) { $this.Init($File, $null, $null, $null, $null, $null, $null) }

    ReviewEpubContent([string]$File, [object]$Level, [string]$Title, [string]$Chaptype, [object]$Notoc, [string[]]$Properties) {
        $this.Init($File, $null, $Title, $Level, $Notoc, $Properties, $Chaptype)
    }

    hidden [void] Init([string]$File, [string]$Media, [string]$Title, [object]$Level, [object]$Notoc, [string[]]$Properties, [string]$Chaptype) {
        $this.File = $File
        $this.Media = $Media
        $this.Title = $Title
        $this.Level = $Level
        $this.Notoc = $Notoc
        $this.Properties = [System.Collections.Generic.List[string]]::new()
        foreach ($p in @($Properties)) { if ($p) { $this.Properties.Add($p) } }
        $this.Chaptype = $Chaptype
        $this.Complement()
    }

    # Content#complement: id from the file name, media type from its extension.
    hidden [void] Complement() {
        $idv = [regex]::Replace($this.File, '[\\/. ]', '-')
        if ($idv -match '^[^a-zA-Z]') { $idv = "rv-$idv" }
        $this.Id = [ReviewHtmlUtils]::CgiEscape($idv).Replace('%', '_25_')

        # ([string] parameters turn $null into '', so test for empty, not just null.)
        if ([string]::IsNullOrEmpty($this.Media)) {
            # @file.sub(/.+\./, '') -- greedy, so everything after the LAST dot.
            $this.Media = ([regex]::new('.+\.').Replace($this.File, '', 1)).ToLowerInvariant()
        }
        $this.Media = switch -CaseSensitive ($this.Media) {
            'xhtml' { 'application/xhtml+xml'; break }
            'xml' { 'application/xhtml+xml'; break }
            'html' { 'application/xhtml+xml'; break }
            'css' { 'text/css'; break }
            'jpg' { 'image/jpeg'; break }
            'jpeg' { 'image/jpeg'; break }
            'image/jpg' { 'image/jpeg'; break }
            'png' { 'image/png'; break }
            'gif' { 'image/gif'; break }
            'svg' { 'image/svg+xml'; break }
            'image/svg' { 'image/svg+xml'; break }
            'ttf' { 'application/vnd.ms-opentype'; break }
            'otf' { 'application/vnd.ms-opentype'; break }
            'woff' { 'application/font-woff'; break }
            default { $this.Media }
        }
    }

    [bool] IsCoverImage([string]$ImageFile) {
        return $this.Media.StartsWith('image') -and [regex]::IsMatch($this.File, "$ImageFile\z")
    }

    [string] PropertiesAttribute() {
        if ($this.Properties.Count -eq 0) { return '' }
        $sorted = [System.Collections.Generic.SortedSet[string]]::new([string[]]$this.Properties.ToArray(), [System.StringComparer]::Ordinal)
        return " properties=`"$(@($sorted) -join ' ')`""
    }
}

# Minimal REXML element/text model, used only to reproduce hierarchy_ncx's exact
# serialization (empty elements as <x/>, double-quoted attributes, &apos;/&quot; escaping).
class ReviewXmlNode {
    [string] $Tag            # $null for a text node
    [string] $Text
    [bool] $Raw
    [System.Collections.Generic.List[object]] $Attrs = [System.Collections.Generic.List[object]]::new()
    [System.Collections.Generic.List[ReviewXmlNode]] $Children = [System.Collections.Generic.List[ReviewXmlNode]]::new()
    [ReviewXmlNode] $Parent

    static [ReviewXmlNode] Element([string]$Tag) { $n = [ReviewXmlNode]::new(); $n.Tag = $Tag; return $n }

    [ReviewXmlNode] AddElement([string]$Tag) {
        $n = [ReviewXmlNode]::Element($Tag)
        $n.Parent = $this
        $this.Children.Add($n)
        return $n
    }

    [void] SetAttribute([string]$Name, [string]$Value) {
        foreach ($a in $this.Attrs) { if ($a[0] -eq $Name) { $a[1] = $Value; return } }
        $this.Attrs.Add([object[]]@($Name, $Value))
    }

    [void] AddText([string]$Text, [bool]$Raw) {
        $n = [ReviewXmlNode]::new()
        $n.Text = $Text
        $n.Raw = $Raw
        $n.Parent = $this
        $this.Children.Add($n)
    }

    static [string] EscapeText([string]$S) {
        return $S.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
    }

    [string] ToXml() {
        if ($null -eq $this.Tag) {
            if ($this.Raw) { return $this.Text }
            return [ReviewXmlNode]::EscapeText($this.Text)
        }
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append('<').Append($this.Tag)
        foreach ($a in $this.Attrs) {
            [void]$sb.Append(' ').Append($a[0]).Append('="').Append([ReviewXmlNode]::EscapeText([string]$a[1])).Append('"')
        }
        if ($this.Children.Count -eq 0) { return $sb.Append('/>').ToString() }
        [void]$sb.Append('>')
        foreach ($c in $this.Children) { [void]$sb.Append($c.ToXml()) }
        return $sb.Append('</').Append($this.Tag).Append('>').ToString()
    }
}

class ReviewEpubMaker {
    [ReviewConfigure] $Config
    [string] $BaseDir
    [string[]] $BuildOnly = $null
    hidden [System.Collections.Generic.List[ReviewEpubContent]] $Contents
    hidden [System.Collections.Generic.List[object]] $HtmlToc
    hidden [object] $Converter
    hidden [bool] $CompileErrors = $false
    hidden [int] $PreCount = 0
    hidden [int] $BodyCount = 0
    hidden [int] $PostCount = 0
    hidden [string] $BuildLogFile = 'build-log.txt'

    static [string[]] $DcItems = @('title', 'language', 'date', 'type', 'format', 'source', 'description', 'relation', 'coverage', 'subject', 'rights')
    static [string[]] $CreatorAttributes = @('a-adp', 'a-ann', 'a-arr', 'a-art', 'a-asn', 'a-aqt', 'a-aft', 'a-aui', 'a-ant', 'a-bkp', 'a-clb', 'a-cmm', 'a-csl', 'a-dsr', 'a-edt', 'a-ill', 'a-lyr', 'a-mdc', 'a-mus', 'a-nrt', 'a-oth', 'a-pht', 'a-prt', 'a-red', 'a-rev', 'a-spn', 'a-ths', 'a-trc', 'a-trl', 'aut')
    static [string[]] $ContributerAttributes = @('adp', 'ann', 'arr', 'art', 'asn', 'aqt', 'aft', 'aui', 'ant', 'bkp', 'clb', 'cmm', 'csl', 'dsr', 'edt', 'ill', 'lyr', 'mdc', 'mus', 'nrt', 'oth', 'pbd', 'pbl', 'pht', 'prt', 'red', 'rev', 'spn', 'ths', 'trc', 'trl')

    ReviewEpubMaker() {
        $this.Contents = [System.Collections.Generic.List[ReviewEpubContent]]::new()
        $this.HtmlToc = [System.Collections.Generic.List[object]]::new()
    }

    # --- small helpers ---------------------------------------------------------------

    hidden [string] h([object]$Str) { return [ReviewHtmlUtils]::Escape([string]$Str) }
    hidden [string] Ext() { return [string]$this.Config.Get('htmlext') }
    hidden [string] Bookname() { return [string]$this.Config.Get('bookname') }
    hidden [object] EpubCfg([string]$Key) {
        $cfg = $this.Config.Get('epubmaker')
        if ($cfg -is [System.Collections.IDictionary]) { return $cfg[$Key] }
        return $null
    }

    # Ruby's Object#present? for config values.
    hidden static [bool] Present([object]$V) {
        if ($null -eq $V) { return $false }
        if ($V -is [bool]) { return $V }
        if ($V -is [string]) { return $V.Trim().Length -gt 0 }
        if ($V -is [System.Collections.ICollection]) { return $V.Count -gt 0 }
        return $true
    }

    # Ruby #to_s for scalar config values (YAML dates come back as DateTime here, as a
    # Date in Ruby, whose to_s is ISO).
    hidden static [string] RubyToS([object]$V) {
        if ($null -eq $V) { return '' }
        if ($V -is [datetime]) { return $V.ToString('yyyy-MM-dd') }
        if ($V -is [bool]) { return $V.ToString().ToLowerInvariant() }
        return [string]$V
    }

    hidden [string] JoinNames([string]$Key) { return (@($this.Config.NamesOf($Key)) -join [ReviewI18n]::T('names_splitter')) }

    hidden [string] DateToS([object]$Date) {
        $s = [ReviewEpubMaker]::RubyToS($Date)
        $parsed = [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
        return [ReviewI18n]::Strftime($parsed, [ReviewI18n]::T('date_format'))
    }

    hidden [void] WriteText([string]$Path, [string]$Text) {
        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    hidden [string] Layout([string]$Title, [string]$Body, [string]$BodyExt) {
        $binding = [hashtable]::new([System.StringComparer]::Ordinal)
        $binding['@title'] = $Title
        $binding['@body'] = $Body
        $binding['@language'] = $this.Config.Get('language')
        $binding['@stylesheets'] = $this.Config.Get('stylesheet')
        $binding['@javascripts'] = @()
        $binding['@body_ext'] = $BodyExt
        return Format-ReviewHtmlLayout -BaseDir $this.BaseDir -Binding $binding
    }

    hidden [void] AddToc([int]$Level, [string]$File, [string]$Title, [string]$Chaptype, [bool]$ForceInclude, [string]$Properties, [object]$Notoc) {
        $this.HtmlToc.Add([pscustomobject]@{
                Level = $Level; File = $File; Title = $Title; Chaptype = $Chaptype
                ForceInclude = $ForceInclude; Properties = $Properties; Notoc = $Notoc
            })
    }

    hidden [void] CallHook([string]$HookName, [string[]]$HookParams) {
        $fileName = $this.EpubCfg($HookName)
        if (-not $fileName) { return }
        $hook = Join-Path $this.BaseDir $fileName
        if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) { return }
        & $hook @HookParams
    }

    # --- entry point -----------------------------------------------------------------

    [string] EpubFilePath() { return Join-Path $this.BaseDir "$($this.Bookname()).epub" }

    [void] Execute([string]$YamlFile, [bool]$DebugFlag, [string[]]$OnlyFiles) {
        $cmdConfig = @{}
        if ($DebugFlag) { $cmdConfig['debug'] = $true }
        if ($OnlyFiles) { $this.BuildOnly = @($OnlyFiles | ForEach-Object { $_.Trim() -replace '\.re$', '' }) }
        try {
            $this.Config = [ReviewConfigure]::Create('epubmaker', $YamlFile, $cmdConfig)
        }
        catch [ReviewConfigError] {
            throw [ReviewApplicationError]::new($_.Exception.Message)
        }
        $this.BaseDir = (Resolve-Path -LiteralPath (Split-Path -Parent $YamlFile)).ProviderPath
        $this.ModifyConfig()
        $this.Produce()
    }

    # Producer#modify_config / support_legacy_maker
    hidden [void] ModifyConfig() {
        $epubVersion = [int]$this.Config.Get('epubversion')
        if ($epubVersion -ne 3) {
            throw [ReviewApplicationError]::new("epubversion: $epubVersion is not supported by this port (EPUB3 only)")
        }
        $this.Config.Set('htmlversion', 5)
        if (-not $this.Config.Get('title')) { $this.Config.Set('title', $this.Config.Get('booktitle')) }
        if (-not $this.Config.Get('cover')) { $this.Config.Set('cover', "$($this.Bookname()).$($this.Ext())") }
        foreach ($k in 'bookname', 'title') {
            if (-not $this.Config.Get($k)) { throw [ReviewApplicationError]::new("Key $k must have a value. Abort.") }
        }
        foreach ($legacy in 'coverfile', 'titlepagefile', 'backcoverfile', 'pubhistory') {
            if ($this.Config.Get($legacy)) {
                Write-Warning "Parameter '$legacy' is obsolete and not supported by this port; ignored."
            }
        }
    }

    hidden [string] BuildPath() {
        if ($this.Config.Get('debug')) {
            $path = Join-Path $this.BaseDir "$($this.Bookname())-epub"
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
            New-Item -ItemType Directory -Path $path | Out-Null
            return $path
        }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "$($this.Bookname())-epub-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tmp | Out-Null
        return $tmp
    }

    hidden [void] Produce() {
        [ReviewI18n]::Setup([string]$this.Config.Get('language'), (Join-Path $this.BaseDir 'locale.yml'))
        try {
            $this.Config.CheckVersion([string]$script:ReviewPortedGemVersion)
        }
        catch [ReviewConfigError] {
            Write-Warning $_.Exception.Message
        }
        $epubFile = $this.EpubFilePath()
        Remove-Item -LiteralPath $epubFile -Force -ErrorAction SilentlyContinue

        $baseTmpDir = $this.BuildPath()
        $epubTmpDir = $null
        try {
            $this.CallHook('hook_beforeprocess', @($baseTmpDir))
            $this.CopyStylesheet($baseTmpDir)
            $this.CopyFrontmatter($baseTmpDir)
            $this.CallHook('hook_afterfrontmatter', @($baseTmpDir))
            $this.BuildBody($baseTmpDir)
            $this.CallHook('hook_afterbody', @($baseTmpDir))
            $this.CopyBackmatter($baseTmpDir)
            $this.CallHook('hook_afterbackmatter', @($baseTmpDir))
            $this.PushContents()

            $imageDir = [string]$this.Config.Get('imagedir')
            if ([ReviewEpubMaker]::Present($this.EpubCfg('verify_target_images'))) {
                $this.VerifyTargetImages($baseTmpDir)
                $this.CopyImages($imageDir, $baseTmpDir)
            }
            else {
                $this.CopyImages($imageDir, (Join-Path $baseTmpDir $imageDir))
            }
            $this.CopyResources('covers', (Join-Path $baseTmpDir $imageDir), $null)
            $this.CopyResources('adv', (Join-Path $baseTmpDir $imageDir), $null)
            $this.CopyResources([string]$this.Config.Get('fontdir'), (Join-Path $baseTmpDir 'fonts'), @($this.Config.Get('font_ext')))
            $this.CallHook('hook_aftercopyimage', @($baseTmpDir))

            $this.ImportImageInfo((Join-Path $baseTmpDir $imageDir), $baseTmpDir, $null)
            $this.ImportImageInfo((Join-Path $baseTmpDir 'fonts'), $baseTmpDir, @($this.Config.Get('font_ext')))

            if ($this.Config.Get('debug')) {
                $epubTmpDir = Join-Path $baseTmpDir "$($this.Bookname())-epub"
            }
            else {
                $epubTmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "$($this.Bookname())-epubpkg-$([guid]::NewGuid().ToString('N'))"
            }
            New-Item -ItemType Directory -Path $epubTmpDir | Out-Null
            $this.ProduceEpub($epubFile, $baseTmpDir, $epubTmpDir)
        }
        finally {
            if (-not $this.Config.Get('debug')) {
                Remove-Item -LiteralPath $baseTmpDir -Recurse -Force -ErrorAction SilentlyContinue
                if ($epubTmpDir) { Remove-Item -LiteralPath $epubTmpDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    # --- front/back matter -----------------------------------------------------------

    hidden [void] CopyStylesheet([string]$BaseTmpDir) {
        foreach ($sfile in @($this.Config.Get('stylesheet'))) {
            if (-not $sfile) { continue }
            $src = Join-Path $this.BaseDir $sfile
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
                throw [ReviewApplicationError]::new("stylesheet: $sfile is not found.")
            }
            Copy-Item -LiteralPath $src -Destination $BaseTmpDir
            $this.Contents.Add([ReviewEpubContent]::new([string]$sfile))
        }
    }

    hidden [void] CopyStaticFile([string]$ConfigName, [string]$DestDir, [string]$DestFileName) {
        $name = [string]$this.Config.Get($ConfigName)
        $dest = if ($DestFileName) { $DestFileName } else { $name }
        $src = Join-Path $this.BaseDir $name
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            throw [ReviewApplicationError]::new("${ConfigName}: $name is not found.")
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $DestDir $dest)
    }

    hidden [void] CopyFrontmatter([string]$BaseTmpDir) {
        $cover = $this.Config.Get('cover')
        if ([ReviewEpubMaker]::Present($cover) -and (Test-Path -LiteralPath (Join-Path $this.BaseDir $cover) -PathType Leaf)) {
            $this.CopyStaticFile('cover', $BaseTmpDir, $null)
        }

        if ($this.Config.Get('titlepage')) {
            $titleFile = "titlepage.$($this.Ext())"
            if ($null -eq $this.Config.Get('titlefile')) {
                $this.BuildTitlepage($BaseTmpDir, $titleFile)
            }
            else {
                $this.CopyStaticFile('titlefile', $BaseTmpDir, $titleFile)
            }
            $this.AddToc(1, $titleFile, [ReviewI18n]::T('titlepagetitle'), 'pre', $false, $null, $null)
        }

        foreach ($pair in @(@('originaltitlefile', 'originaltitle'), @('creditfile', 'credittitle'))) {
            $value = $this.Config.Get($pair[0])
            if ([ReviewEpubMaker]::Present($value)) {
                $this.CopyStaticFile($pair[0], $BaseTmpDir, $null)
                $this.AddToc(1, [System.IO.Path]::GetFileName([string]$value), [ReviewI18n]::T($pair[1]), 'pre', $false, $null, $null)
            }
        }
    }

    hidden [void] CopyBackmatter([string]$BaseTmpDir) {
        foreach ($pair in @(@('profile', 'profiletitle'), @('advfile', 'advtitle'))) {
            $value = $this.Config.Get($pair[0])
            if ($value) {
                $this.CopyStaticFile($pair[0], $BaseTmpDir, $null)
                $this.AddToc(1, [System.IO.Path]::GetFileName([string]$value), [ReviewI18n]::T($pair[1]), 'post', $false, $null, $null)
            }
        }
        $colophon = $this.Config.Get('colophon')
        if ($colophon) {
            if ($colophon -is [string]) {
                $this.CopyStaticFile('colophon', $BaseTmpDir, "colophon.$($this.Ext())")
            }
            $this.AddToc(1, "colophon.$($this.Ext())", [ReviewI18n]::T('colophontitle'), 'post', $false, $null, $null)
        }
        $backcover = $this.Config.Get('backcover')
        if ($backcover) {
            $this.CopyStaticFile('backcover', $BaseTmpDir, $null)
            $this.AddToc(1, [System.IO.Path]::GetFileName([string]$backcover), [ReviewI18n]::T('backcovertitle'), 'post', $false, $null, $null)
        }
    }

    hidden [void] BuildTitlepage([string]$BaseTmpDir, [string]$HtmlFile) {
        $booktitle = $this.h($this.Config.NameOf('booktitle'))
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("<div class=`"titlepage`">`n")
        [void]$sb.Append("<h1 class=`"tp-title`">$booktitle</h1>`n")
        if ($this.Config.Get('subtitle')) { [void]$sb.Append("<h2 class=`"tp-subtitle`">$($this.h($this.Config.NameOf('subtitle')))</h2>`n") }
        if ($this.Config.Get('aut')) { [void]$sb.Append("<h2 class=`"tp-author`">$($this.h($this.JoinNames('aut')))</h2>`n") }
        if ($this.Config.Get('pbl')) { [void]$sb.Append("<h3 class=`"tp-publisher`">$($this.h($this.JoinNames('pbl')))</h3>`n") }
        [void]$sb.Append("</div>`n")
        $this.WriteText((Join-Path $BaseTmpDir $HtmlFile), $this.Layout($booktitle, $sb.ToString(), $null))
    }

    hidden [void] BuildPart([object]$Part, [string]$BaseTmpDir, [string]$HtmlFile) {
        $partTitle = ([string]$Part.Name).Trim()
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("<div class=`"part`">`n")
        [void]$sb.Append("<h1 class=`"part-number`">$($this.h([ReviewI18n]::T('part', $Part.Number)))</h1>`n")
        if ($partTitle.Length -gt 0) { [void]$sb.Append("<h2 class=`"part-title`">$($this.h($partTitle))</h2>`n") }
        [void]$sb.Append("</div>`n")
        $this.WriteText((Join-Path $BaseTmpDir $HtmlFile), $this.Layout($partTitle, $sb.ToString(), $null))
    }

    # --- body ------------------------------------------------------------------------

    hidden [void] WriteBuildLog([string]$BaseTmpDir, [string]$HtmlFile, [string]$ReviewFile) {
        [System.IO.File]::AppendAllText((Join-Path $BaseTmpDir $this.BuildLogFile), "$HtmlFile,$ReviewFile`n", [System.Text.UTF8Encoding]::new($false))
    }

    hidden [void] BuildBody([string]$BaseTmpDir) {
        $this.PreCount = 0; $this.BodyCount = 0; $this.PostCount = 0
        $book = [ReviewBookBase]::new($this.BaseDir, $this.Config)
        $this.Converter = [ReviewConverter]::new($book, [ReviewHTMLBuilder]::new())
        $this.CompileErrors = $false

        foreach ($part in $book.Parts()) {
            if ([ReviewEpubMaker]::Present($part.Name)) {
                if ($part.FileFlag()) {
                    $this.BuildChap($part, $BaseTmpDir, $true)
                }
                else {
                    $htmlFile = "part_$($part.Number).$($this.Ext())"
                    $this.BuildPart($part, $BaseTmpDir, $htmlFile)
                    $title = [ReviewI18n]::T('part', $part.Number)
                    if (([string]$part.Name).Trim().Length -gt 0) {
                        $title += [ReviewI18n]::T('chapter_postfix') + ([string]$part.Name).Trim()
                    }
                    $this.AddToc(0, $htmlFile, $title, 'part', $false, $null, $null)
                    $this.WriteBuildLog($BaseTmpDir, $htmlFile, '')
                }
            }
            foreach ($chap in @($part.Chapters)) { $this.BuildChap($chap, $BaseTmpDir, $false) }
        }
        if ($this.CompileErrors) {
            throw [ReviewApplicationError]::new('compile error, No EPUB file output.')
        }
    }

    hidden [void] BuildChap([object]$Chap, [string]$BaseTmpDir, [bool]$IsPart) {
        $chaptype = 'body'
        if ($IsPart) { $chaptype = 'part' }
        elseif ($Chap.OnPredef()) { $chaptype = 'pre' }
        elseif ($Chap.OnAppendix()) { $chaptype = 'appendix' }
        elseif ($Chap.OnPostdef()) { $chaptype = 'post' }

        $fileName = [string]$Chap.Path
        if (-not $IsPart -and [System.IO.Path]::IsPathRooted($fileName)) {
            $fileName = [System.IO.Path]::GetRelativePath($this.BaseDir, $fileName).Replace('\', '/')
        }
        $id = [System.IO.Path]::GetFileName($fileName) -replace '\.re$', ''

        if ($this.EpubCfg('rename_for_legacy') -and -not $IsPart) {
            if ($Chap.OnPredef()) { $this.PreCount++; $id = 'pre{0:00}' -f $this.PreCount }
            elseif ($Chap.OnAppendix()) { $this.PostCount++; $id = 'post{0:00}' -f $this.PostCount }
            else { $this.BodyCount++; $id = 'chap{0:00}' -f $this.BodyCount }
        }

        if ($this.BuildOnly -and ($this.BuildOnly -notcontains $id)) {
            Write-Warning "skip $id.re"
            return
        }

        $htmlFile = "$id.$($this.Ext())"
        $this.WriteBuildLog($BaseTmpDir, $htmlFile, $fileName)
        if ([ReviewEpubMaker]::Present($this.Config.Get('params'))) {
            Write-Warning "'params:' in config.yml is obsoleted."
        }
        try {
            $this.Converter.Convert($fileName, (Join-Path $BaseTmpDir $htmlFile))
            $this.WriteInfoBody($BaseTmpDir, $htmlFile, $IsPart, $chaptype)
            $this.RemoveHiddenTitle($BaseTmpDir, $htmlFile)
        }
        catch {
            $this.CompileErrors = $true
            Write-Warning "compile error in $fileName ($($_.Exception.GetType().Name))"
            Write-Warning $_.Exception.Message
        }
    }

    hidden [void] RemoveHiddenTitle([string]$BaseTmpDir, [string]$HtmlFile) {
        $path = Join-Path $BaseTmpDir $HtmlFile
        $body = [System.IO.File]::ReadAllText($path)
        $body = [regex]::Replace($body, '<h\d .*?hidden=[''"]true[''"].*?>.*?</h\d>\n', '')
        $body = [regex]::Replace($body, '(<h\d .*?)\s*notoc=[''"]true[''"]\s*(.*?>.*?</h\d>\n)', '$1$2')
        $this.WriteText($path, $body)
    }

    hidden static [System.Xml.XmlReader] OpenXhtml([string]$Path) {
        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $settings.XmlResolver = $null
        return [System.Xml.XmlReader]::Create($Path, $settings)
    }

    # ReVIEWHeaderListener: level, id (the hN's own id, overridden by an inner <a id>),
    # title (text content, <img alt> included, tabs -> U+3000) and notoc of each heading.
    hidden [object[]] ParseHeadlines([string]$Path) {
        $headlines = [System.Collections.Generic.List[object]]::new()
        $reader = [ReviewEpubMaker]::OpenXhtml($Path)
        try {
            $level = $null; $id = $null; $notoc = $null
            $content = [System.Text.StringBuilder]::new()
            while ($reader.Read()) {
                $nodeType = $reader.NodeType
                if ($nodeType -eq [System.Xml.XmlNodeType]::Element) {
                    $name = $reader.Name
                    $hm = [regex]::Match($name, '^h(\d+)')
                    $isEmpty = $reader.IsEmptyElement
                    if ($hm.Success) {
                        if ($null -ne $level) { throw [ReviewApplicationError]::new("nested heading <$name> in $Path") }
                        $level = [int]$hm.Groups[1].Value
                        $attrId = $reader.GetAttribute('id')
                        if ($attrId) { $id = $attrId }
                        $attrNotoc = $reader.GetAttribute('notoc')
                        if ($attrNotoc) { $notoc = $attrNotoc }
                    }
                    elseif ($null -ne $level) {
                        if ($name -eq 'img' -and $reader.GetAttribute('alt')) { [void]$content.Append($reader.GetAttribute('alt')) }
                        elseif ($name -eq 'a' -and $reader.GetAttribute('id')) { $id = $reader.GetAttribute('id') }
                    }
                    if ($isEmpty -and $hm.Success) { $nodeType = [System.Xml.XmlNodeType]::EndElement }
                }
                if ($nodeType -eq [System.Xml.XmlNodeType]::EndElement -and $reader.Name -match '^h\d+') {
                    if ($id) {
                        $headlines.Add([pscustomobject]@{ Level = $level; Id = $id; Title = $content.ToString(); Notoc = $notoc })
                    }
                    [void]$content.Clear(); $level = $null; $id = $null; $notoc = $null
                }
                elseif ($null -ne $level -and ($nodeType -eq [System.Xml.XmlNodeType]::Text -or
                        $nodeType -eq [System.Xml.XmlNodeType]::Whitespace -or
                        $nodeType -eq [System.Xml.XmlNodeType]::SignificantWhitespace -or
                        $nodeType -eq [System.Xml.XmlNodeType]::CDATA)) {
                    [void]$content.Append($reader.Value.Replace("`t", '　'))
                }
            }
        }
        finally {
            $reader.Dispose()
        }
        return $headlines.ToArray()
    }

    hidden [string[]] DetectProperties([string]$Path) {
        $mathml = $false; $svg = $false
        $reader = [ReviewEpubMaker]::OpenXhtml($Path)
        try {
            while ($reader.Read()) {
                if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                if ($reader.LocalName -eq 'math' -and $reader.NamespaceURI -eq 'http://www.w3.org/1998/Math/MathML') { $mathml = $true }
                if ($reader.LocalName -eq 'svg' -and $reader.NamespaceURI -eq 'http://www.w3.org/2000/svg') { $svg = $true }
            }
        }
        finally {
            $reader.Dispose()
        }
        $props = [System.Collections.Generic.List[string]]::new()
        if ($mathml) { $props.Add('mathml') }
        if ($svg) { $props.Add('svg') }
        return $props.ToArray()
    }

    hidden [void] WriteInfoBody([string]$BaseTmpDir, [string]$FileName, [bool]$IsPart, [string]$Chaptype) {
        $path = Join-Path $BaseTmpDir $FileName
        $headlines = $this.ParseHeadlines($path)
        if ($headlines.Count -eq 0) {
            Write-Warning "$FileName is discarded because there is no heading. Use ``=[notoc]' or ``=[nodisp]' to exclude headlines from the table of contents."
            return
        }
        $properties = $this.DetectProperties($path)
        $propStr = if ($properties.Count -gt 0) { $properties -join ' ' } else { $null }
        $first = $true
        foreach ($headline in $headlines) {
            $level = $headline.Level
            if ($IsPart -and $level -eq 1) { $level = 0 }
            if (-not $first) {
                $this.AddToc($level, "$FileName#$($headline.Id)", $headline.Title, $Chaptype, $false, $null, $headline.Notoc)
            }
            else {
                $this.AddToc($level, $FileName, $headline.Title, $Chaptype, $true, $propStr, $headline.Notoc)
                $first = $false
            }
        }
    }

    hidden [void] PushContents() {
        $tocLevel = [int]$this.Config.Get('toclevel')
        foreach ($item in $this.HtmlToc) {
            if ($item.Level -gt $tocLevel -and -not $item.ForceInclude) { continue }
            $props = if ($item.Properties) { [string[]]$item.Properties.Split(' ') } else { $null }
            $notoc = if ([ReviewEpubMaker]::Present($item.Notoc)) { $item.Notoc } else { $null }
            $this.Contents.Add([ReviewEpubContent]::new([string]$item.File, [object]$item.Level, [string]$item.Title, [string]$item.Chaptype, $notoc, $props))
        }
    }

    # --- images, fonts ---------------------------------------------------------------

    hidden [string[]] AllowExts([object]$AllowExts) {
        if ($null -eq $AllowExts) { return @($this.Config.Get('image_ext')) }
        return @($AllowExts)
    }

    hidden [void] RecursiveCopyFiles([string]$ResDir, [string]$DestDir, [string[]]$AllowExts) {
        $extRe = [regex]::new("\.($($AllowExts -join '|'))\z", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($entry in Get-ChildItem -LiteralPath $ResDir -Force) {
            if ($entry.Name.StartsWith('.')) { continue }
            if ($entry.PSIsContainer) {
                $this.RecursiveCopyFiles($entry.FullName, (Join-Path $DestDir $entry.Name), $AllowExts)
            }
            elseif ($extRe.IsMatch($entry.Name)) {
                New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
                Copy-Item -LiteralPath $entry.FullName -Destination $DestDir
            }
        }
    }

    hidden [void] CopyImages([string]$ResDir, [string]$DestDir) {
        $src = Join-Path $this.BaseDir $ResDir
        if (-not (Test-Path -LiteralPath $src)) { return }
        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
        if ([ReviewEpubMaker]::Present($this.EpubCfg('verify_target_images'))) {
            foreach ($file in @($this.EpubCfg('force_include_images'))) {
                if (-not $file) { continue }
                $full = Join-Path $this.BaseDir $file
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    if ($file -notmatch '^https?:') { Write-Warning "$file is not found, skip." }
                    continue
                }
                $sub = Join-Path $DestDir ([System.IO.Path]::GetDirectoryName([string]$file))
                New-Item -ItemType Directory -Force -Path $sub | Out-Null
                Copy-Item -LiteralPath $full -Destination $sub
            }
        }
        else {
            $this.RecursiveCopyFiles($src, $DestDir, $this.AllowExts($null))
        }
    }

    hidden [void] CopyResources([string]$ResDir, [string]$DestDir, [object]$AllowExts) {
        if (-not $ResDir) { return }
        $src = Join-Path $this.BaseDir $ResDir
        if (-not (Test-Path -LiteralPath $src)) { return }
        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
        $this.RecursiveCopyFiles($src, $DestDir, $this.AllowExts($AllowExts))
    }

    # Producer#import_imageinfo: every allowed file under Path becomes a Content entry,
    # with Base stripped to give the OEBPS-relative name. (Ruby's Dir.foreach order is
    # unspecified; sorted here -- the manifest is sorted by id anyway.)
    hidden [void] ImportImageInfo([string]$Path, [string]$Base, [object]$AllowExts) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $exts = $this.AllowExts($AllowExts)
        $extRe = [regex]::new("\.($($exts -join '|'))\z", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $entries = @(Get-ChildItem -LiteralPath $Path -Force | Sort-Object Name -CaseSensitive)
        foreach ($entry in $entries) {
            if ($entry.Name.StartsWith('.')) { continue }
            if ($extRe.IsMatch($entry.Name)) {
                $rel = [System.IO.Path]::GetRelativePath($Base, $entry.FullName).Replace('\', '/')
                $this.Contents.Add([ReviewEpubContent]::new($rel))
            }
            if ($entry.PSIsContainer) { $this.ImportImageInfo($entry.FullName, $Base, $null) }
        }
    }

    hidden [void] VerifyTargetImages([string]$BaseTmpDir) {
        $found = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in @($this.EpubCfg('force_include_images'))) { if ($existing) { $found.Add([string]$existing) } }
        foreach ($content in $this.Contents) {
            $path = Join-Path $BaseTmpDir $content.File
            if ($content.Media -eq 'application/xhtml+xml') {
                $reader = [ReviewEpubMaker]::OpenXhtml($path)
                try {
                    while ($reader.Read()) {
                        if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.LocalName -eq 'img') {
                            $src = $reader.GetAttribute('src')
                            $found.Add($src)
                            if ($src -match '(?i)svg\z') { $content.Properties.Add('svg') }
                        }
                    }
                }
                finally { $reader.Dispose() }
            }
            elseif ($content.Media -eq 'text/css') {
                foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($path), 'url\((.+?)\)')) { $found.Add($m.Groups[1].Value.Trim()) }
            }
        }
        $sorted = [System.Collections.Generic.SortedSet[string]]::new([string[]]@($found | Where-Object { $_ }), [System.StringComparer]::Ordinal)
        $this.Config.Get('epubmaker')['force_include_images'] = @($sorted)
    }

    # --- EPUB3 package ---------------------------------------------------------------

    hidden [ReviewEpubContent] CoverImageItem() {
        $coverImage = $this.Config.Get('coverimage')
        if (-not $coverImage) { return $null }
        foreach ($c in $this.Contents) { if ($c.IsCoverImage([string]$coverImage)) { return $c } }
        return $null
    }

    hidden [string] Container() {
        return "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n" +
            "<container xmlns=`"urn:oasis:names:tc:opendocument:xmlns:container`" version=`"1.0`">`n" +
            "  <rootfiles>`n" +
            "    <rootfile full-path=`"OEBPS/$($this.Bookname()).opf`" media-type=`"application/oebps-package+xml`" />`n" +
            "  </rootfiles>`n" +
            "</container>`n"
    }

    # A DC/creator/contributor value: a scalar, or a hash with 'name' plus refines.
    hidden [object[]] NameAndRefines([object]$V) {
        $refines = [System.Collections.Generic.List[object]]::new()
        if ($V -is [System.Collections.IDictionary]) {
            foreach ($k in $V.Keys) {
                if ($k -ne 'name') { $refines.Add([object[]]@([string]$k, $V[$k])) }
            }
            return @([ReviewEpubMaker]::RubyToS($V['name']), $refines)
        }
        return @([ReviewEpubMaker]::RubyToS($V), $refines)
    }

    hidden [string] OpfMetainfo() {
        $sb = [System.Text.StringBuilder]::new()
        foreach ($item in [ReviewEpubMaker]::DcItems) {
            $value = $this.Config.Get($item)
            if (-not $value) { continue }
            $entries = [System.Collections.Generic.List[object]]::new()
            if ($value -is [System.Collections.IList] -and $value -isnot [string]) {
                $i = 0
                foreach ($v in $value) { $entries.Add([object[]]@("$item-$i", $v)); $i++ }
            }
            else {
                $entries.Add([object[]]@($item, $value))
            }
            foreach ($e in $entries) {
                $nr = $this.NameAndRefines($e[1])
                [void]$sb.Append("    <dc:$item id=`"$($e[0])`">$($nr[0])</dc:$item>`n")
                foreach ($r in $nr[1]) {
                    [void]$sb.Append("    <meta refines=`"#$($e[0])`" property=`"$($r[0])`">$($this.h([ReviewEpubMaker]::RubyToS($r[1])))</meta>`n")
                }
            }
        }
        [void]$sb.Append("    <meta property=`"dcterms:modified`">$([ReviewEpubMaker]::RubyToS($this.Config.Get('modified')))</meta>`n")
        $identifier = if ($this.Config.Get('isbn')) { $this.Config.Get('isbn') } else { $this.Config.Get('urnid') }
        [void]$sb.Append("    <dc:identifier id=`"BookId`">$([ReviewEpubMaker]::RubyToS($identifier))</dc:identifier>`n")

        foreach ($role in [ReviewEpubMaker]::CreatorAttributes) {
            $value = $this.Config.Get($role)
            if (-not $value) { continue }
            $i = 0
            foreach ($v in @($value)) {
                $id = "$role-$i"
                $bare = $role -replace '^a-', ''
                $nr = $this.NameAndRefines($v)
                [void]$sb.Append("    <dc:creator id=`"$id`">$($nr[0])</dc:creator>`n")
                [void]$sb.Append("    <meta refines=`"#$id`" property=`"role`" scheme=`"marc:relators`">$bare</meta>`n")
                foreach ($r in $nr[1]) {
                    [void]$sb.Append("    <meta refines=`"#$bare-$i`" property=`"$($r[0])`">$([ReviewEpubMaker]::RubyToS($r[1]))</meta>`n")
                }
                $i++
            }
        }

        foreach ($role in [ReviewEpubMaker]::ContributerAttributes) {
            $value = $this.Config.Get($role)
            if (-not $value) { continue }
            $i = 0
            foreach ($v in @($value)) {
                $id = "$role-$i"
                $nr = $this.NameAndRefines($v)
                [void]$sb.Append("    <dc:contributor id=`"$id`">$($this.h($nr[0]))</dc:contributor>`n")
                [void]$sb.Append("    <meta refines=`"#$id`" property=`"role`" scheme=`"marc:relators`">$role</meta>`n")
                foreach ($r in $nr[1]) {
                    [void]$sb.Append("    <meta refines=`"#$id`" property=`"$($r[0])`">$([ReviewEpubMaker]::RubyToS($r[1]))</meta>`n")
                }
                if ($role -eq 'prt' -or $role -eq 'pbl') {
                    $pubId = "pub-$role-$i"
                    [void]$sb.Append("    <dc:publisher id=`"$pubId`">$($this.h($nr[0]))</dc:publisher>`n")
                    # Ruby 5.9.0 uses role 'prt' (not $role) for a plain-string publisher.
                    $pubRole = if ($v -is [System.Collections.IDictionary]) { $role } else { 'prt' }
                    [void]$sb.Append("    <meta refines=`"#$pubId`" property=`"role`" scheme=`"marc:relators`">$pubRole</meta>`n")
                    foreach ($r in $nr[1]) {
                        [void]$sb.Append("    <meta refines=`"#$pubId`" property=`"$($r[0])`">$([ReviewEpubMaker]::RubyToS($r[1]))</meta>`n")
                    }
                }
                $i++
            }
        }

        $opfMeta = $this.Config.Get('opf_meta')
        if ($opfMeta -is [System.Collections.IDictionary]) {
            foreach ($k in $opfMeta.Keys) {
                [void]$sb.Append("    <meta property=`"$($this.h($k))`">$($this.h([ReviewEpubMaker]::RubyToS($opfMeta[$k])))</meta>`n")
            }
        }
        return $sb.ToString()
    }

    hidden [string] Opf() {
        $coverImage = $this.CoverImageItem()
        $opfCoverImage = ''
        if ($this.Config.Get('coverimage')) {
            if (-not $coverImage) {
                throw [ReviewApplicationError]::new("coverimage $($this.Config.Get('coverimage')) not found. Abort.")
            }
            $opfCoverImage = "    <meta name=`"cover`" content=`"$($coverImage.Id)`"/>`n"
        }

        $packageAttrs = ''
        $prefix = $this.Config.Get('opf_prefix')
        if ($prefix -is [System.Collections.IDictionary] -and $prefix.Count -gt 0) {
            $packageAttrs = " prefix=`"$(@($prefix.Keys | ForEach-Object { "${_}: $($prefix[$_])" }) -join ' ')`""
        }

        $bn = $this.Bookname(); $ext = $this.Ext()
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n")
        [void]$sb.Append("<package version=`"3.0`" xmlns=`"http://www.idpf.org/2007/opf`" unique-identifier=`"BookId`" xml:lang=`"$($this.Config.Get('language'))`"$packageAttrs>`n")
        [void]$sb.Append("  <metadata xmlns:dc=`"http://purl.org/dc/elements/1.1/`" xmlns:opf=`"http://www.idpf.org/2007/opf`">`n")
        [void]$sb.Append($this.OpfMetainfo())
        [void]$sb.Append($opfCoverImage)
        [void]$sb.Append("  </metadata>`n")

        # manifest
        [void]$sb.Append("  <manifest>`n")
        [void]$sb.Append("    <item properties=`"nav`" id=`"$bn-toc.$ext`" href=`"$bn-toc.$ext`" media-type=`"application/xhtml+xml`"/>`n")
        $cover = $this.Config.Get('cover')
        if ($cover) { [void]$sb.Append("    <item id=`"$bn`" href=`"$cover`" media-type=`"application/xhtml+xml`"/>`n") }
        if ($coverImage) {
            [void]$sb.Append("    <item properties=`"cover-image`" id=`"cover-$($coverImage.Id)`" href=`"$($coverImage.File)`" media-type=`"$($coverImage.Media)`"/>`n")
        }
        $items = [System.Collections.Generic.List[ReviewEpubContent]]::new()
        foreach ($c in $this.Contents) {
            if ($c.File.Contains('#')) { continue }
            if ($coverImage -and $c.Id -eq $coverImage.Id) { continue }
            $items.Add($c)
        }
        # sort_by(&:id) -- Ruby compares strings bytewise, i.e. ordinal.
        $sortedItems = $items.ToArray()
        $keys = [string[]]@($sortedItems | ForEach-Object { $_.Id })
        [array]::Sort($keys, $sortedItems, [System.StringComparer]::Ordinal)
        foreach ($item in $sortedItems) {
            [void]$sb.Append("    <item id=`"$($item.Id)`" href=`"$($item.File)`" media-type=`"$($item.Media)`"$($item.PropertiesAttribute())/>`n")
        }
        [void]$sb.Append("  </manifest>`n")

        # spine
        $direction = $this.Config.Get('direction')
        if ($direction) { [void]$sb.Append("  <spine page-progression-direction=`"$direction`">`n") }
        else { [void]$sb.Append("  <spine>`n") }
        $coverLinearCfg = $this.EpubCfg('cover_linear')
        $coverLinear = if ($coverLinearCfg -and $coverLinearCfg -ne 'no') { 'yes' } else { 'no' }
        if ([ReviewEpubMaker]::Present($cover)) { [void]$sb.Append("    <itemref idref=`"$bn`" linear=`"$coverLinear`"/>`n") }
        $tocDone = $false
        foreach ($item in $this.Contents) {
            if ($item.Media -notmatch 'xhtml\+xml') { continue }
            if (-not $tocDone -and $item.Chaptype -ne 'pre') {
                if ($this.Config.Get('toc')) { [void]$sb.Append("    <itemref idref=`"$bn-toc.$ext`" />`n") }
                $tocDone = $true
            }
            [void]$sb.Append("    <itemref idref=`"$($item.Id)`"/>`n")
        }
        [void]$sb.Append("  </spine>`n")

        # guide
        [void]$sb.Append("  <guide>`n")
        if ([ReviewEpubMaker]::Present($cover)) {
            [void]$sb.Append("    <reference type=`"cover`" title=`"$([ReviewI18n]::T('covertitle'))`" href=`"$cover`"/>`n")
        }
        if ([ReviewEpubMaker]::Present($this.Config.Get('titlepage'))) {
            [void]$sb.Append("    <reference type=`"title-page`" title=`"$([ReviewI18n]::T('titlepagetitle'))`" href=`"titlepage.$ext`"/>`n")
        }
        [void]$sb.Append("    <reference type=`"toc`" title=`"$([ReviewI18n]::T('toctitle'))`" href=`"$bn-toc.$ext`"/>`n")
        if ([ReviewEpubMaker]::Present($this.Config.Get('colophon'))) {
            [void]$sb.Append("    <reference type=`"colophon`" title=`"$([ReviewI18n]::T('colophontitle'))`" href=`"colophon.$ext`"/>`n")
        }
        [void]$sb.Append("  </guide>`n")
        [void]$sb.Append("</package>`n")
        return $sb.ToString()
    }

    hidden [string] Cover() {
        $title = $this.h($this.Config.NameOf('title'))
        $sb = [System.Text.StringBuilder]::new()
        if ($this.Config.Get('coverimage')) {
            $item = $this.CoverImageItem()
            if (-not $item) { throw [ReviewApplicationError]::new("coverimage $($this.Config.Get('coverimage')) not found. Abort.") }
            [void]$sb.Append("  <div id=`"cover-image`" class=`"cover-image`">`n")
            [void]$sb.Append("    <img src=`"$($item.File)`" alt=`"$title`" class=`"max`"/>`n")
            [void]$sb.Append("  </div>`n")
        }
        else {
            [void]$sb.Append("<h1 class=`"cover-title`">$title</h1>`n")
            if ($this.Config.Get('subtitle')) { [void]$sb.Append("<h2 class=`"cover-subtitle`">$($this.h($this.Config.NameOf('subtitle')))</h2>`n") }
        }
        return $this.Layout($title, $sb.ToString(), ' epub:type="cover"')
    }

    hidden [string] IsbnHyphen() {
        $str = [ReviewEpubMaker]::RubyToS($this.Config.Get('isbn'))
        if ($str -match '^\d{10}$') { return "$($str[0])-$($str.Substring(1, 5))-$($str.Substring(6, 3))-$($str[9])" }
        if ($str -match '^\d{13}$') { return "$($str.Substring(0, 3))-$($str[3])-$($str.Substring(4, 5))-$($str.Substring(9, 3))-$($str[12])" }
        return $null
    }

    hidden [string] ColophonHistory() {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("    <div class=`"pubhistory`">`n")
        $history = $this.Config.Get('history')
        if ($history) {
            $edit = 0
            foreach ($items in @($history)) {
                $rev = 0
                foreach ($itemObj in @($items)) {
                    $item = [ReviewEpubMaker]::RubyToS($itemObj)
                    $editStr = if ($edit -eq 0) { [ReviewI18n]::T('first_edition') } else { [ReviewI18n]::T('nth_edition', [string]($edit + 1)) }
                    $revStr = [ReviewI18n]::T('nth_impression', [string]($rev + 1))
                    $line = $item
                    if ($item -match '^\d+-\d+-\d+$') {
                        $line = [ReviewI18n]::T('published_by1', @($this.DateToS($item), ($editStr + $revStr)))
                    }
                    elseif ($item -match '^(\d+-\d+-\d+)[\s　](.+)') {
                        $line = [ReviewI18n]::T('published_by3', @($this.DateToS($Matches[1]), $Matches[2]))
                    }
                    [void]$sb.Append("      <p>$line</p>`n")
                    $rev++
                }
                $edit++
            }
        }
        else {
            [void]$sb.Append("      <p>$([ReviewI18n]::T('published_by2', $this.DateToS($this.Config.Get('date'))))</p>`n")
        }
        [void]$sb.Append("    </div>`n")
        return $sb.ToString()
    }

    hidden [string] Colophon() {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("  <div class=`"colophon`">`n")
        $title = $this.h($this.Config.NameOf('title'))
        if ($null -eq $this.Config.Get('subtitle')) {
            [void]$sb.Append("    <p class=`"title`">$title</p>`n")
        }
        else {
            [void]$sb.Append("    <p class=`"title`">$title<br /><span class=`"subtitle`">$($this.h($this.Config.NameOf('subtitle')))</span></p>`n")
        }
        if ($this.Config.Get('date') -or $this.Config.Get('history')) { [void]$sb.Append($this.ColophonHistory()) }
        [void]$sb.Append("    <table class=`"colophon`">`n")
        foreach ($role in @($this.Config.Get('colophon_order'))) {
            if ($this.Config.Get($role)) {
                [void]$sb.Append("      <tr><th>$($this.h([ReviewI18n]::T($role)))</th><td>$($this.h($this.JoinNames($role)))</td></tr>`n")
            }
        }
        $isbn = $this.IsbnHyphen()
        if ($isbn) { [void]$sb.Append("      <tr><th>ISBN</th><td>$isbn</td></tr>`n") }
        [void]$sb.Append("    </table>`n")
        $rights = $this.Config.Get('rights')
        if ($rights -and @($rights).Count -gt 0) {
            [void]$sb.Append("    <p class=`"copyright`">$(@($this.Config.NamesOf('rights') | ForEach-Object { [ReviewHtmlUtils]::Escape($_) }) -join '<br />')</p>`n")
        }
        [void]$sb.Append("  </div>`n")
        return $this.Layout($this.h([ReviewI18n]::T('colophontitle')), $sb.ToString(), $null)
    }

    hidden [ReviewEpubContent[]] CoverItem() {
        $cover = $this.Config.Get('cover')
        if (-not $cover) { return @() }
        return @([ReviewEpubContent]::new([string]$cover, 1, [ReviewI18n]::T('covertitle'), 'cover', $null, $null))
    }

    # EPUBCommon#hierarchy_ncx -- builds the nested list with a REXML-equivalent tree so
    # the serialization (and the "ugly" post-gsubs) come out byte-identical.
    hidden [string] HierarchyNcx([string]$Type) {
        $level = 1
        $findJump = $false
        $tocLevel = [int]$this.Config.Get('toclevel')

        $hasPart = $false
        foreach ($item in $this.Contents) {
            if ($null -eq $item.Notoc -and $item.Chaptype -eq 'part') { $hasPart = $true; break }
        }
        if ($hasPart) {
            foreach ($item in $this.Contents) {
                if ($item.Chaptype -eq 'part' -and $item.Level -gt 0) { $item.Level = $item.Level - 1 }
                if ($item.Chaptype -eq 'part' -or $item.Chaptype -eq 'body') { $item.Level = $item.Level + 1 }
            }
            $tocLevel++
        }

        $root = [ReviewXmlNode]::Element($Type)
        $root.SetAttribute('class', "toc-h$level")
        $e = $root.AddElement('li')
        $all = [System.Collections.Generic.List[ReviewEpubContent]]::new()
        foreach ($c in $this.CoverItem()) { $all.Add($c) }
        foreach ($c in $this.Contents) { $all.Add($c) }
        foreach ($item in $all) {
            if ($null -ne $item.Notoc -or $null -eq $item.Level -or $null -eq $item.File -or $null -eq $item.Title -or [int]$item.Level -gt $tocLevel) { continue }
            $itemLevel = [int]$item.Level
            if ($itemLevel -eq $level) {
                $e = $e.Parent.AddElement('li')
            }
            elseif ($itemLevel -gt $level) {
                if (($itemLevel - $level) -gt 1) { $findJump = $true }
                for ($n = $level + 1; $n -le $itemLevel; $n++) {
                    if ($e.Children.Count -eq 0) {
                        $e.SetAttribute('style', 'list-style-type: none;')
                        $es = $e.AddElement('span')
                        $es.SetAttribute('style', 'display:none;')
                        $es.AddText('&#xa0;', $true)
                    }
                    $e2 = $e.AddElement($Type)
                    $e2.SetAttribute('class', "toc-h$n")
                    $e = $e2.AddElement('li')
                }
                $level = $itemLevel
            }
            else {
                for ($n = $level - 1; $n -ge $itemLevel; $n--) { $e = $e.Parent.Parent }
                $e = $e.Parent.AddElement('li')
                $level = $itemLevel
            }
            $a = $e.AddElement('a')
            $a.SetAttribute('href', $item.File)
            $a.AddText($item.Title, $false)
        }
        if ($findJump) {
            Write-Warning "found level jumping in table of contents. consider to use 'epubmaker:flattoc: true' for strict ePUB validator."
        }
        return $root.ToXml().Replace('<li/>', '').Replace('</li>', "</li>`n").Replace("<$Type ", "`n<$Type ")
    }

    hidden [string] FlatNcx([string]$Type, [object]$Indent) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("<$Type class=`"toc-h1`">`n")
        $tocLevel = [int]$this.Config.Get('toclevel')
        $all = [System.Collections.Generic.List[ReviewEpubContent]]::new()
        foreach ($c in $this.CoverItem()) { $all.Add($c) }
        foreach ($c in $this.Contents) { $all.Add($c) }
        foreach ($item in $all) {
            if ($null -ne $item.Notoc -or $null -eq $item.Level -or $null -eq $item.File -or $null -eq $item.Title -or [int]$item.Level -gt $tocLevel) { continue }
            $is = if ($Indent -eq $true) { '　' * [int]$item.Level } else { '' }
            [void]$sb.Append("<li><a href=`"$($item.File)`">$is$($this.h($item.Title))</a></li>`n")
        }
        [void]$sb.Append("</$Type>`n")
        return $sb.ToString()
    }

    hidden [string] Ncx() {
        $main = if ($null -eq $this.EpubCfg('flattoc')) { $this.HierarchyNcx('ol') } else { $this.FlatNcx('ol', $this.EpubCfg('flattocindent')) }
        $tocTitle = $this.h([ReviewI18n]::T('toctitle'))
        $body = "  <nav xmlns:epub=`"http://www.idpf.org/2007/ops`" epub:type=`"toc`" id=`"toc`">`n" +
            "  <h1 class=`"toc-title`">$tocTitle</h1>`n" +
            "$main  </nav>`n"
        return $this.Layout($tocTitle, $body, $null)
    }

    # EPUBCommon#produce_write_common + EPUBv3#produce
    hidden [void] ProduceEpub([string]$EpubFile, [string]$WorkDir, [string]$TmpDir) {
        $this.WriteText((Join-Path $TmpDir 'mimetype'), 'application/epub+zip')
        New-Item -ItemType Directory -Force -Path (Join-Path $TmpDir 'META-INF') | Out-Null
        $this.WriteText((Join-Path $TmpDir 'META-INF/container.xml'), $this.Container())
        $oebps = Join-Path $TmpDir 'OEBPS'
        New-Item -ItemType Directory -Force -Path $oebps | Out-Null
        $this.WriteText((Join-Path $oebps "$($this.Bookname()).opf"), $this.Opf())

        $cover = $this.Config.Get('cover')
        if ($cover) {
            $existing = Join-Path $WorkDir $cover
            if (Test-Path -LiteralPath $existing -PathType Leaf) { Copy-Item -LiteralPath $existing -Destination $oebps }
            else { $this.WriteText((Join-Path $oebps $cover), $this.Cover()) }
        }

        $colophon = $this.Config.Get('colophon')
        if ($colophon -and $colophon -isnot [string]) {
            $this.WriteText((Join-Path $WorkDir "colophon.$($this.Ext())"), $this.Colophon())
        }

        foreach ($item in $this.Contents) {
            if ($item.File.Contains('#')) { continue }
            $src = Join-Path $WorkDir $item.File
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
                throw [ReviewApplicationError]::new("$src is not found.")
            }
            $dest = Join-Path $oebps $item.File
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $src -Destination $dest
        }

        $this.WriteText((Join-Path $oebps "$($this.Bookname())-toc.$($this.Ext())"), $this.Ncx())
        $this.CallHook('hook_prepack', @($TmpDir))
        $this.ExportZip($EpubFile, $TmpDir)
    }

    # ZipExporter#export_zip_rubyzip: mimetype first and stored, then every file under
    # META-INF/, OEBPS/ (and zip_addpath) in sorted path order.
    hidden [void] ExportZip([string]$EpubFile, [string]$TmpDir) {
        $paths = [System.Collections.Generic.List[string]]::new()
        $dirs = [System.Collections.Generic.List[string]]::new()
        $dirs.Add('META-INF'); $dirs.Add('OEBPS')
        $addPath = $this.Config.Get('zip_addpath')
        if ([ReviewEpubMaker]::Present($addPath)) { $dirs.Add([string]$addPath) }
        foreach ($d in $dirs) {
            $full = Join-Path $TmpDir $d
            if (-not (Test-Path -LiteralPath $full)) { continue }
            foreach ($f in Get-ChildItem -LiteralPath $full -Recurse -File -Force) {
                $paths.Add([System.IO.Path]::GetRelativePath($TmpDir, $f.FullName).Replace('\', '/'))
            }
        }
        $sorted = [string[]]$paths.ToArray()
        [array]::Sort($sorted, [System.StringComparer]::Ordinal)

        $stream = [System.IO.File]::Open($EpubFile, [System.IO.FileMode]::Create)
        try {
            $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $zip.CreateEntry('mimetype', [System.IO.Compression.CompressionLevel]::NoCompression)
                $w = $entry.Open()
                $bytes = [System.Text.Encoding]::ASCII.GetBytes('application/epub+zip')
                $w.Write($bytes, 0, $bytes.Length)
                $w.Dispose()
                foreach ($rel in $sorted) {
                    $src = Join-Path $TmpDir $rel
                    $e = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
                    $e.LastWriteTime = [System.IO.File]::GetLastWriteTime($src)
                    $w = $e.Open()
                    $data = [System.IO.File]::ReadAllBytes($src)
                    $w.Write($data, 0, $data.Length)
                    $w.Dispose()
                }
            }
            finally {
                $zip.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
}
