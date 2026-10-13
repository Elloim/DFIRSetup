BeforeDiscovery {
    $cases = Import-Csv (Join-Path $PSScriptRoot 'fixtures\flare-shortcuts.csv') | ForEach-Object { @{ Category = $_.Category; Shortcut = $_.Shortcut; Expected = $_.Expected } }
}

Describe '2-Build-StartHere.ps1 shortcut placement' {
    BeforeAll {
        # Fake FLARE tool list: one folder per category, empty .lnk files inside.
        $flare = Join-Path $TestDrive 'Tools'
        $startHere = Join-Path $TestDrive 'Start Here'
        $fixtures = Import-Csv (Join-Path $PSScriptRoot 'fixtures\flare-shortcuts.csv')
        foreach ($c in $fixtures) {
            $dir = New-Item -ItemType Directory -Force -Path (Join-Path $flare $c.Category)
            New-Item -ItemType File -Force -Path (Join-Path $dir "$($c.Shortcut).lnk") | Out-Null
        }
        $rows = & (Join-Path $PSScriptRoot '..\scripts\2-Build-StartHere.ps1') -StartHere $startHere -FlareTools $flare -SkipZimmerman -SkipVolatility
    }

    It 'creates Start Here\Artifacts' {
        Join-Path $startHere 'Artifacts' | Should -Exist
    }

    It 'puts <Shortcut> (<Category>) in <Expected>' -ForEach $cases {
        Join-Path $startHere "Tools\$Expected\$Shortcut.lnk" | Should -Exist
        ($rows | Where-Object Shortcut -EQ $Shortcut).Folder | Should -Be $Expected
    }

    It 'copies each shortcut exactly once' {
        @(Get-ChildItem -Path (Join-Path $startHere 'Tools') -Filter *.lnk -Recurse).Count | Should -Be $fixtures.Count
    }
}
