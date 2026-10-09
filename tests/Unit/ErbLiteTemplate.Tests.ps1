$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'ReviewErbLiteTemplate (restricted ERB subset for project-local overrides)' {
    InModuleScope PwshReview {
        BeforeAll {
            function Invoke-Erb {
                param([string]$Source, [hashtable]$Binding = @{})
                $b = [hashtable]::new([System.StringComparer]::Ordinal)
                foreach ($k in $Binding.Keys) { $b[$k] = $Binding[$k] }
                $tpl = [ReviewErbLiteTemplate]::new($Source, 'test.erb')
                return $tpl.Render($b, [ReviewLaTeXEscaper]::new('uplatex'))
            }
        }

        It 'renders FirstStepReVIEW-v3''s real layouts/config-local.tex.erb with trim-mode semantics' {
            # Verbatim content of FirstStepReVIEW-v3/articles/layouts/config-local.tex.erb
            $src = "\makeatletter`n" +
                "<%- if @config['techbooster'] && @config['techbooster']['cover_fit_page'] -%>`n" +
                "\recls@coverfitpagetrue`n" +
                "<%- end -%>`n" +
                "<%- if @config['techbooster'] && @config['techbooster']['backcoverimage'] -%>`n" +
                "\def\techbooster@coverimage{images/<%= @config['techbooster']['backcoverimage'] %>}`n" +
                "<%- end -%>`n" +
                "\makeatother`n"

            $conf = [ReviewConfigure]::Values()
            $conf.Set('techbooster', @{ cover_fit_page = $true })
            Invoke-Erb $src @{ '@config' = $conf } | Should -Be "\makeatletter`n\recls@coverfitpagetrue`n\makeatother`n"

            $conf.Set('techbooster', @{ backcoverimage = 'back.png' })
            Invoke-Erb $src @{ '@config' = $conf } | Should -Be "\makeatletter`n\def\techbooster@coverimage{images/back.png}`n\makeatother`n"

            $conf.Set('techbooster', $null)
            Invoke-Erb $src @{ '@config' = $conf } | Should -Be "\makeatletter`n\makeatother`n"
        }

        It 'uses Ruby truthiness: empty string and 0 are TRUE, only nil/false are falsy' {
            Invoke-Erb "<% if @a %>T<% else %>F<% end %>" @{ '@a' = '' } | Should -Be 'T'
            Invoke-Erb "<% if @a %>T<% else %>F<% end %>" @{ '@a' = 0 } | Should -Be 'T'
            Invoke-Erb "<% if @a %>T<% else %>F<% end %>" @{ '@a' = $false } | Should -Be 'F'
            Invoke-Erb "<% if @missing %>T<% else %>F<% end %>" | Should -Be 'F'
        }

        It 'supports elsif / unless / ! / || / == and .present?' {
            Invoke-Erb "<% if @a == 'x' %>X<% elsif @a == 'y' %>Y<% else %>Z<% end %>" @{ '@a' = 'y' } | Should -Be 'Y'
            Invoke-Erb "<% unless @a %>none<% end %>" | Should -Be 'none'
            Invoke-Erb "<%= @a || 'dflt' %>" | Should -Be 'dflt'
            Invoke-Erb "<% if !@a.present? %>blank<% end %>" @{ '@a' = '  ' } | Should -Be 'blank'
        }

        It 'supports .each loops over arrays, [x].flatten, and escape()' {
            Invoke-Erb "<%- [@s].flatten.each do |x| -%>`n\usepackage{<%= x %>}`n<%- end -%>`n" @{ '@s' = @('a', 'b') } |
                Should -Be "\usepackage{a}`n\usepackage{b}`n"
            Invoke-Erb "<%= escape(@t) %>" @{ '@t' = '50% & $5' } | Should -Be '50\% \& \textdollar{}5'
        }

        It 'invokes scriptblock bindings as bare identifiers (e.g. latex_config)' {
            Invoke-Erb "[<%= latex_config %>]" @{ 'latex_config' = { 'CFG' } } | Should -Be '[CFG]'
        }

        It 'throws a clear error for unsupported Ruby rather than silently mis-rendering' {
            { Invoke-Erb "<%= @a.gsub(/x/, 'y') %>" @{ '@a' = 'x' } } | Should -Throw '*unsupported ERB construct*'
            { Invoke-Erb "<% def foo; end %>" } | Should -Throw '*unsupported ERB construct*'
            { Invoke-Erb "<%= `"#{1+1}`" %>" } | Should -Throw '*unsupported ERB construct*'
        }
    }
}
