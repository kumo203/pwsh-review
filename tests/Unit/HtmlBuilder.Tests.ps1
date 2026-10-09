$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

# Exact-string checks of the HTML/EPUB helpers against values verified with Ruby 5.9.0
# (CGI.escapeHTML, HTMLUtils#normalize_id, EPUBMaker::Content#complement).
Describe 'HTML builder helpers' {
    InModuleScope PwshReview {
        It 'escapes like CGI.escapeHTML (apostrophe as &#39;)' {
            [ReviewHtmlUtils]::Escape(@'
a&b<c>"d"'e'
'@.Trim()) | Should -BeExactly 'a&amp;b&lt;c&gt;&quot;d&quot;&#39;e&#39;'
        }

        It 'normalizes ids like HTMLUtils#normalize_id' {
            [ReviewHtmlUtils]::NormalizeId('sample-1.a_b') | Should -BeExactly 'sample-1.a_b'
            [ReviewHtmlUtils]::NormalizeId('1abc') | Should -BeExactly 'id_1abc'
            [ReviewHtmlUtils]::NormalizeId('a b') | Should -BeExactly 'id_a-b'
            [ReviewHtmlUtils]::NormalizeId('図_1') | Should -BeExactly 'id__E5_9B_B3__1'
        }

        It 'derives EPUB manifest ids and media types like EPUBMaker::Content' {
            $c = [ReviewEpubContent]::new('images/ch01/fig 1.PNG')
            $c.Id | Should -BeExactly 'images-ch01-fig-1-PNG'
            $c.Media | Should -BeExactly 'image/png'
            [ReviewEpubContent]::new('1st.xhtml').Id | Should -BeExactly 'rv-1st-xhtml'
            [ReviewEpubContent]::new('ch01.xhtml#h1-1').Media | Should -BeExactly 'xhtml#h1-1'
            [ReviewEpubContent]::new('epub_style.scss').Media | Should -BeExactly 'scss'
        }

        It 'serializes the nav tree like REXML (escaping, self-closing empty elements, double quotes)' {
            $root = [ReviewXmlNode]::Element('ol')
            $root.SetAttribute('class', 'toc-h1')
            $li = $root.AddElement('li')
            [void]$root.AddElement('li')
            $a = $li.AddElement('a')
            $a.SetAttribute('href', "a&b`"c'.xhtml")
            $a.AddText("T & <x> `"q`" 'a'", $false)
            $root.ToXml() | Should -BeExactly '<ol class="toc-h1"><li><a href="a&amp;b&quot;c&apos;.xhtml">T &amp; &lt;x&gt; &quot;q&quot; &apos;a&apos;</a></li><li/></ol>'
        }
    }
}
