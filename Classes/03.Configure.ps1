# Port of review/lib/review/configure.rb.
#
# Ruby's Configure < Hash, with Configure#[] doing maker-specific shadowing (if
# self.maker is set and self[maker][key] exists, it wins over the top-level self[key]).
# PowerShell classes can't subclass Hashtable, so this is composition: ReviewConfigure
# wraps a [hashtable] $Store and exposes Get/Set/ContainsKey, with Get() implementing the
# maker-shadow lookup. Nested values (e.g. $Config.Get('pdfmaker')) are plain
# [hashtable]s, which support PowerShell's native `[key]` indexer directly -- only the
# top-level Configure needs the custom Get().
#
# Per the project-wide null-coercion rule (see 01.LineInput.ps1), Get() is declared
# [object] so a missing/nil key correctly yields $null, not a coerced empty value.

class ReviewConfigure {
    [hashtable] $Store
    [string] $Maker

    ReviewConfigure() {
        $this.Store = @{}
        $this.Maker = $null
    }

    ReviewConfigure([hashtable]$Store) {
        $this.Store = $Store
        $this.Maker = $null
    }

    static [ReviewConfigure] Values() {
        $now = Get-Date
        $defaults = @{
            bookname           = 'book'
            booktitle          = 'Re:VIEW Sample Book'
            title              = $null
            aut                = $null
            prt                = $null
            asn                = $null
            ant                = $null
            clb                = $null
            edt                = $null
            dsr                = $null
            ill                = $null
            pht                = $null
            trl                = $null
            date               = $now.ToString('yyyy-MM-dd')
            rights             = $null
            description        = $null
            urnid              = "urn:uuid:$([guid]::NewGuid().ToString())"
            stylesheet         = @()
            coverfile          = $null
            mytoc              = $null
            params             = ''
            toclevel           = 3
            secnolevel         = 2
            epubversion        = 3
            titlepage          = $true
            toc                = $null
            colophon           = $null
            debug              = $null
            catalogfile        = 'catalog.yml'
            language           = 'ja'
            math_format        = $null
            htmlext            = 'html'
            htmlversion        = 5
            contentdir         = '.'
            imagedir           = 'images'
            image_ext          = @('png', 'gif', 'jpg', 'jpeg', 'svg', 'ttf', 'woff', 'otf')
            fontdir            = 'fonts'
            chapter_file       = 'CHAPS'
            part_file          = 'PART'
            reject_file        = 'REJECT'
            predef_file        = 'PREDEF'
            postdef_file       = 'POSTDEF'
            page_metric        = 'A5'
            ext                = '.re'
            image_types        = @('.ai', '.psd', '.eps', '.pdf', '.tif', '.tiff', '.png', '.bmp', '.jpg', '.jpeg', '.gif', '.svg')
            bib_file           = 'bib.re'
            words_file         = $null
            colophon_order     = @('aut', 'csl', 'trl', 'dsr', 'ill', 'cov', 'edt', 'pbl', 'contact', 'prt', 'pht')
            chapterlink        = $true
            externallink       = $true
            join_lines_by_lang = $null
            table_row_separator = 'tabs'
            playwright_options = @{
                playwright_path = './node_modules/.bin/playwright'
                selfcrop        = $true
                pdfcrop_path    = 'pdfcrop'
                pdftocairo_path = 'pdftocairo'
            }
            tableopt           = $null
            listinfo           = $null
            nolf               = $true
            chapref            = $null
            structuredxml      = $null
            pt_to_mm_unit      = 0.3528
            footnotetext       = $null
            texcommand         = 'uplatex'
            texoptions         = '-interaction=nonstopmode -file-line-error -halt-on-error'
            _texdocumentclass  = @('review-jsbook', '')
            texstyle           = @('reviewmacro')
            dvicommand         = 'dvipdfmx'
            dvioptions         = '-d 5 -z 9'
            pdfmaker            = @{
                image_scale2width   = $true
                makeindex           = $null
                makeindex_command   = 'mendex'
                makeindex_options   = '-f -r -I utf8'
                makeindex_sty       = $null
                makeindex_dic       = $null
                makeindex_mecab     = $true
                makeindex_mecab_opts = '-Oyomi'
                use_cover_nombre    = $true
                use_original_image_size = $null
            }
            imgmath_options     = @{
                format              = 'png'
                converter           = 'pdfcrop'
                pdfcrop_cmd         = 'pdfcrop --hires %i %o'
                extract_singlepage  = $null
                pdfextract_cmd      = 'pdfjam -q --outfile %o %i %p'
                preamble_file       = $null
                fontsize            = 10
                lineheight          = 12.0
                pdfcrop_pixelize_cmd = 'pdftocairo -%t -r 90 -f %p -l %p -singlefile %i %O'
                dvipng_cmd          = 'dvipng -T tight -z 9 -p %p -l %p -o %o %i'
            }
            caption_position    = @{
                list     = 'top'
                image    = 'bottom'
                table    = 'top'
                equation = 'top'
            }
            modified            = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            isbn                = $null
            titlefile           = $null
            originaltitlefile   = $null
            profile             = $null
            direction           = 'ltr'
            image_maxpixels     = 4000000
            font_ext            = @('ttf', 'woff', 'otf')
            epubmaker           = @{
                flattoc              = $null
                flattocindent        = $true
                ncx_indent           = @()
                zip_stage1           = 'zip -0Xq'
                zip_stage2           = 'zip -Xr9Dq'
                zip_addpath          = $null
                hook_beforeprocess   = $null
                hook_afterfrontmatter = $null
                hook_afterbody       = $null
                hook_afterbackmatter = $null
                hook_aftercopyimage  = $null
                hook_prepack         = $null
                rename_for_legacy    = $null
                verify_target_images = $null
                force_include_images = @()
                cover_linear         = $null
                back_footnote        = $null
            }
            textmaker           = @{
                th_bold = $null
            }
        }
        $conf = [ReviewConfigure]::new($defaults)
        $conf.Maker = $null
        return $conf
    }

    static [ReviewConfigure] Create([string]$Maker, [string]$YamlFile, [hashtable]$CmdConfig) {
        $conf = [ReviewConfigure]::Values()
        $conf.Maker = $Maker

        if ($YamlFile) {
            try {
                $loader = [ReviewYamlLoader]::new()
                $conf.Store = [ReviewYamlLoader]::DeepMerge($conf.Store, $loader.LoadFile($YamlFile))
            }
            catch {
                throw [ReviewConfigError]::new("yaml error $($_.Exception.Message)")
            }
        }

        if ($CmdConfig) {
            $conf.Store = [ReviewYamlLoader]::DeepMerge($conf.Store, $CmdConfig)
        }

        $conf.MigrateParameters()
        return $conf
    }

    hidden static [string[]] $StringToArrayKeys = @(
        'subject', 'aut',
        'a-adp', 'a-ann', 'a-arr', 'a-art', 'a-asn', 'a-aqt', 'a-aft', 'a-aui', 'a-ant', 'a-bkp', 'a-clb', 'a-cmm', 'a-dsr', 'a-edt',
        'a-ill', 'a-lyr', 'a-mdc', 'a-mus', 'a-nrt', 'a-oth', 'a-pht', 'a-prt', 'a-red', 'a-rev', 'a-spn', 'a-ths', 'a-trc', 'a-trl',
        'adp', 'ann', 'arr', 'art', 'asn', 'aqt', 'aft', 'aui', 'ant', 'bkp', 'clb', 'cmm', 'dsr', 'edt',
        'ill', 'lyr', 'mdc', 'mus', 'nrt', 'oth', 'pht', 'pbl', 'prt', 'red', 'rev', 'spn', 'ths', 'trc', 'trl',
        'stylesheet', 'rights'
    )

    [void] MigrateParameters() {
        foreach ($item in [ReviewConfigure]::StringToArrayKeys) {
            $value = $this.Store[$item]
            if ($null -ne $value -and $value -is [string]) {
                $this.Store[$item] = @($value)
            }
        }

        if ($this.Store['mathml']) {
            Write-Warning '"mathml: true" is obsoleted. Please use "math_format: mathml"'
            $this.Store['math_format'] = 'mathml'
        }
        if ($this.Store['imgmath']) {
            Write-Warning '"imgmath: true" is obsoleted. Please use "math_format: imgmath"'
            $this.Store['math_format'] = 'imgmath'
        }
    }

    # Mirrors Configure#[] -- maker-specific shadowing before the top-level lookup.
    [object] Get([string]$Key) {
        if ($this.Maker -and $this.Store.ContainsKey($this.Maker)) {
            $makerHash = $this.Store[$this.Maker]
            if ($makerHash -is [hashtable] -and $makerHash.ContainsKey($Key)) {
                return $makerHash[$Key]
            }
        }
        if ($this.Store.ContainsKey($Key)) {
            return $this.Store[$Key]
        }
        return $null
    }

    [void] Set([string]$Key, [object]$Value) {
        $this.Store[$Key] = $Value
    }

    [bool] ContainsKey([string]$Key) {
        return $this.Store.ContainsKey($Key)
    }

    [bool] CheckVersion([string]$Version) {
        return $this.CheckVersion($Version, $true)
    }

    [bool] CheckVersion([string]$Version, [bool]$ThrowOnFail) {
        if (-not $this.ContainsKey('review_version')) {
            if ($ThrowOnFail) {
                throw [ReviewConfigError]::new('configuration file has no review_version property.')
            }
            return $false
        }

        $reviewVersion = [string]$this.Get('review_version')
        if ([string]::IsNullOrWhiteSpace($reviewVersion)) {
            return $true
        }

        $confMajor = [ReviewConfigure]::MajorVersionOf($reviewVersion)
        $targetMajor = [ReviewConfigure]::MajorVersionOf($Version)
        if ($confMajor -ne $targetMajor) {
            if ($ThrowOnFail) {
                throw [ReviewConfigError]::new('major version of configuration file is different.')
            }
            return $false
        }

        $confFloat = [double]([ReviewConfigure]::ToFloat($reviewVersion))
        $targetFloat = [double]([ReviewConfigure]::ToFloat($Version))
        if ($confFloat -gt $targetFloat) {
            if ($ThrowOnFail) {
                throw [ReviewConfigError]::new("Re:VIEW version '$Version' is older than configuration file's version '$reviewVersion'.")
            }
            return $false
        }

        return $true
    }

    hidden static [int] MajorVersionOf([string]$Version) {
        $parts = $Version -split '\.'
        $value = 0
        [void][int]::TryParse($parts[0], [ref]$value)
        return $value
    }

    hidden static [double] ToFloat([string]$Version) {
        $parts = $Version -split '\.'
        $text = if ($parts.Count -ge 2) { "$($parts[0]).$($parts[1])" } else { $parts[0] }
        $value = 0.0
        [void][double]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)
        return $value
    }

    [object] NameOf([string]$Key) {
        $value = $this.Get($Key)
        if ($value -is [System.Collections.IList]) {
            return ($value -join ',')
        }
        elseif ($value -is [hashtable]) {
            return $value['name']
        }
        else {
            return $value
        }
    }

    [string[]] NamesOf([string]$Key) {
        $value = $this.Get($Key)
        if ($value -is [System.Collections.IList]) {
            return @($value | ForEach-Object {
                if ($_ -is [hashtable]) { $_['name'] } else { $_ }
            })
        }
        elseif ($value -is [hashtable]) {
            return @($value['name'])
        }
        else {
            return @($value)
        }
    }
}
