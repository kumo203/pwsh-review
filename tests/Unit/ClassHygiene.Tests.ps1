# Guards against a PowerShell-class pitfall that silently broke several builder commands:
# member lookup is case-INsensitive, so a property and a method whose names differ only
# in case (e.g. property $FirstLineNum vs. method firstlinenum()) collide -- calling
# $obj.firstlinenum(...) resolves to the PROPERTY and fails with the misleading
# "does not contain a method named 'firstlinenum'". The builder classes are especially
# exposed because their method names are Ruby's snake_case command names (dispatched
# dynamically by the Compiler), which naturally echo the state they store.

$moduleManifest = Join-Path $PSScriptRoot '..\..\PwshReview.psd1'
Import-Module $moduleManifest -Force

Describe 'Module class hygiene' {
    InModuleScope PwshReview {
        It 'has no class whose method name collides case-insensitively with a property name' {
            $types = [AppDomain]::CurrentDomain.GetAssemblies() |
                ForEach-Object { try { $_.GetTypes() } catch { } } |
                Where-Object { $_.Name -like 'Review*' -and $_.IsClass -and $_.Assembly.IsDynamic } |
                Sort-Object Name -Unique
            $flags = [Reflection.BindingFlags]'Public,NonPublic,Instance,Static'

            $collisions = foreach ($t in $types) {
                $props = @($t.GetProperties($flags) | ForEach-Object Name)
                $methods = @($t.GetMethods($flags) | Where-Object { -not $_.IsSpecialName } | ForEach-Object Name | Sort-Object -Unique)
                foreach ($m in $methods) {
                    foreach ($p in $props) { if ($p -ieq $m) { "$($t.Name): method '$m' vs property '$p'" } }
                }
            }

            $types.Count | Should -BeGreaterThan 10
            @($collisions) | Should -BeNullOrEmpty
        }
    }
}
