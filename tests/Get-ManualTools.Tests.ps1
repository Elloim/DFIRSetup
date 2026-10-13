Describe '3-Get-ManualTools.ps1 -WhatIf' {
    BeforeAll {
        $manifest = Join-Path $PSScriptRoot '..\manifests\manual-tools.json'
        $tools = Get-Content -Raw -Path $manifest | ConvertFrom-Json
        Mock Invoke-WebRequest { throw 'network used' }
        Mock Invoke-RestMethod { throw 'network used' }
        $root = Join-Path $TestDrive 'Tools'
        $rows = & (Join-Path $PSScriptRoot '..\scripts\3-Get-ManualTools.ps1') -WhatIf -ToolsRoot $root -SevenZip 'none'
    }

    It 'lists every manifest entry once' {
        $rows.Name | Should -Be $tools.name
    }

    It 'shows the destination folder of each downloadable entry' {
        foreach ($t in $tools | Where-Object { $_.kind -notin 'gated', 'pip' }) {
            ($rows | Where-Object Name -EQ $t.name).Destination | Should -Be (Join-Path $root $t.folder)
        }
    }

    It 'points gated entries at their source page' {
        foreach ($t in $tools | Where-Object kind -EQ 'gated') {
            ($rows | Where-Object Name -EQ $t.name).Action | Should -Match ([regex]::Escape($t.source))
        }
    }

    It 'downloads and writes nothing' {
        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Invoke-RestMethod -Times 0
        Test-Path $root | Should -BeFalse
    }
}
