BeforeDiscovery {
    $ps1 = Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Filter *.ps1 -Recurse | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

Describe 'PowerShell files' {
    It '<Name> parses with zero errors' -ForEach $ps1 {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'PSScriptAnalyzer reports zero Error-severity findings' {
        Invoke-ScriptAnalyzer -Path (Join-Path $PSScriptRoot '..') -Recurse -Severity Error | Should -BeNullOrEmpty
    }

    It 'uses only Windows PowerShell 5.1 syntax' {
        $settings = @{ IncludeRules = @('PSUseCompatibleSyntax'); Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } } }
        Invoke-ScriptAnalyzer -Path (Join-Path $PSScriptRoot '..') -Recurse -Settings $settings | Should -BeNullOrEmpty
    }

    It '<Name> is ASCII only, so Windows PowerShell reads it the same without a BOM' -ForEach $ps1 {
        [IO.File]::ReadAllText($Path) | Should -Not -Match '[^\x00-\x7F]'
    }
}

Describe 'config\cd-dfir-config.xml' {
    BeforeAll {
        [xml]$config = Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\config\cd-dfir-config.xml')
        [xml]$upstream = Get-Content -Raw -Path (Join-Path $PSScriptRoot 'fixtures\upstream-config.xml')
        $names = @($config.config.packages.package.name)
    }

    It 'holds exactly the 90 packages of the brief' {
        $expected = Get-Content -Path (Join-Path $PSScriptRoot 'fixtures\packages.txt') | ForEach-Object { "$_.vm" }
        $names.Count | Should -Be 90
        Compare-Object $expected $names | Should -BeNullOrEmpty
    }

    It 'keeps every other section identical to upstream FLARE-VM' {
        foreach ($node in $upstream.config.ChildNodes | Where-Object Name -NE 'packages') {
            $config.config[$node.Name].OuterXml | Should -Be $node.OuterXml -Because $node.Name
        }
    }

    It 'names only packages that exist in VM-Packages (set VM_PACKAGES_CLONE to a clone)' -Skip:(-not $env:VM_PACKAGES_CLONE) {
        $present = git -C $env:VM_PACKAGES_CLONE ls-tree -d --name-only HEAD:packages
        $names | Where-Object { $_ -notin $present } | Should -BeNullOrEmpty
    }
}
