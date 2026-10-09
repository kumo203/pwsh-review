# Hand-ported review/templates/html/layout-html5.html.erb (ERB trim mode '>': the
# newline after any tag that ends a line is dropped), plus the project-local override
# <basedir>/layouts/layout.html.erb rendered through ReviewErbLiteTemplate in the same
# trim mode. Shared by ReviewHTMLBuilder (chapter pages) and the EPUB maker (title,
# part, cover, colophon and TOC pages).
#
# Binding keys mirror the Ruby instance variables: '@title', '@body', '@language',
# '@stylesheets', '@javascripts', '@body_ext' (+ '@next'/'@prev'/'@next_title'/
# '@prev_title' for chapter pages, available to custom layouts).

function Format-ReviewHtmlLayout {
    param(
        [string]$BaseDir,
        [hashtable]$Binding
    )

    if ($BaseDir) {
        $local = Join-Path $BaseDir 'layouts/layout.html.erb'
        if (-not (Test-Path -LiteralPath $local) -and (Test-Path -LiteralPath (Join-Path $BaseDir 'layouts/layout.erb'))) {
            throw [ReviewConfigError]::new('layout.erb is obsoleted. Please use layout.html.erb.')
        }
        if (Test-Path -LiteralPath $local) {
            $src = [System.IO.File]::ReadAllText($local)
            $b = [hashtable]::new([System.StringComparer]::Ordinal)
            foreach ($k in $Binding.Keys) { $b[$k] = $Binding[$k] }
            $b['__basedir'] = $BaseDir
            $tpl = [ReviewErbLiteTemplate]::new($src, 'layouts/layout.html.erb', '>')
            return $tpl.Render($b, $null)
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n")
    [void]$sb.Append("<!DOCTYPE html>`n")
    [void]$sb.Append("<html xmlns=`"http://www.w3.org/1999/xhtml`" xmlns:epub=`"http://www.idpf.org/2007/ops`" xmlns:ops=`"http://www.idpf.org/2007/ops`" xml:lang=`"$($Binding['@language'])`">`n")
    [void]$sb.Append("<head>`n")
    [void]$sb.Append("  <meta charset=`"UTF-8`" />`n")
    foreach ($js in @($Binding['@javascripts'])) {
        if ($null -ne $js) { [void]$sb.Append("  $js`n") }
    }
    foreach ($style in @($Binding['@stylesheets'])) {
        if ($null -ne $style) { [void]$sb.Append("  <link rel=`"stylesheet`" type=`"text/css`" href=`"$style`" />`n") }
    }
    [void]$sb.Append("  <meta name=`"generator`" content=`"Re:VIEW`" />`n")
    [void]$sb.Append("  <title>$($Binding['@title'])</title>`n")
    [void]$sb.Append("</head>`n")
    [void]$sb.Append("<body$($Binding['@body_ext'])>`n")
    [void]$sb.Append($Binding['@body'])
    [void]$sb.Append("</body>`n")
    [void]$sb.Append("</html>`n")
    return $sb.ToString()
}
