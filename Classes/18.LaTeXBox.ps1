# Port of review/lib/review/latexbox.rb -- generates \renewenvironment{review<name>}
# tcolorbox-styled minicolumn snippets, driven entirely by config['pdfmaker']['boxsetting'].
# A no-op (empty string) unless that config key is actually set.

class ReviewLaTeXBox {
    [string] Tcbox([ReviewConfigure]$Config) {
        $ret = [System.Text.StringBuilder]::new()
        $pdfmaker = $Config.Get('pdfmaker')
        $boxSetting = if ($pdfmaker) { $pdfmaker['boxsetting'] } else { $null }

        foreach ($name in @('column', 'note', 'memo', 'tip', 'info', 'warning', 'important', 'caution', 'notice')) {
            if (-not $boxSetting) { continue }
            $entry = $boxSetting[$name]
            if (-not $entry -or -not $entry['style']) { continue }

            $style = $entry['style']
            $options = if ($entry['options']) { "[$($entry['options'])]" } else { '[]' }
            $optionsWithCaption = if ($entry['options_with_caption']) { "[$($entry['options_with_caption'])]" } elseif ($entry['options']) { $options } else { '[]' }

            [void]$ret.Append(@"
\renewenvironment{review$name}[1][]{%
  \csdef{rv@tmp@withcaption}{true}
  \notblank{##1}{
    \begin{rv@${style}@caption}{##1}$optionsWithCaption
   }{
    \csundef{rv@tmp@withcaption}
    \begin{rv@${style}@nocaption}$options
   }
}{
  \ifcsdef{rv@tmp@withcaption}{
    \end{rv@${style}@caption}
  }{
    \end{rv@${style}@nocaption}
  }
}

"@)
        }

        return $ret.ToString()
    }
}
