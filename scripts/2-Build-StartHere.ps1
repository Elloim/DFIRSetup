<#
.SYNOPSIS
Builds Desktop\Start Here\{Artifacts,Tools} the way the CyberDefenders lab image lays it out.
.DESCRIPTION
Copies every FLARE-VM shortcut from the FLARE tool list folder into a Start Here
category folder (name rules first, then the FLARE category), downloads Eric
Zimmerman's tools with Get-ZimmermanTools.ps1, and installs Volatility 3 with pip.
Run it after 1-Install-Flare.ps1 finishes. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StartHere = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Start Here'),
    [string]$FlareTools = $(if ($env:TOOL_LIST_DIR) { $env:TOOL_LIST_DIR } else { Join-Path ([Environment]::GetFolderPath('Desktop')) 'Tools' }),
    [switch]$SkipZimmerman,
    [switch]$SkipVolatility
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Folder names under Start Here\Tools. The lab's own names come first; the last
# four are ours because no writeup shows them, so rename them freely.
$Log      = 'Log Analysis'
$Memory   = 'Memory Analysis'
$Mobile   = 'Mobile Forensics'
$Misc     = 'Miscellaneous'
$Disk     = 'Disk Forensics'
$Registry = 'Registry'
$Malware  = 'Malware Analysis'
$Network  = 'Network Analysis'

# Shortcut name rules, checked in order; the first match wins.
$NameRules = @(
    @{ Pattern = 'Timeline|Event Log Explorer|EvtxECmd|Hayabusa|Chainsaw'; Folder = $Log }
    @{ Pattern = 'MemProcFS|pe-sieve'; Folder = $Memory }
    @{ Pattern = 'ALEAPP|apktool'; Folder = $Mobile }
    @{ Pattern = 'jadx|FLOSS|DB Browser|sqlite|CyberChef'; Folder = $Misc }
    @{ Pattern = 'Registry|RECmd|\bRLA\b|ShellBags|Amcache|AppCompat'; Folder = $Registry }
)

# FLARE category folder (the <tags> value of the package) to Start Here folder.
# Anything not listed lands in $Misc.
$CategoryMap = @{
    'Forensic'          = $Disk
    'Memory'            = $Memory
    'Registry'          = $Registry
    'Networking'        = $Network
    'Java and Android'  = $Mobile
    'PE'                = $Malware
    'dotNet'            = $Malware
    'Debuggers'         = $Malware
    'Disassemblers'     = $Malware
    'Documents'         = $Malware
    'Packers'           = $Malware
    'Shellcode'         = $Malware
    'File Information'  = $Malware
    'Javascript'        = $Malware
    'Visual Basic'      = $Malware
    'IDA Plugins'       = $Malware
    'Hex Editors'       = $Malware
    'Credential Access' = $Malware
}

$ZimmermanUrl = 'https://raw.githubusercontent.com/EricZimmerman/Get-ZimmermanTools/master/Get-ZimmermanTools.ps1'
$VolatilityApi = 'https://api.github.com/repos/volatilityfoundation/volatility3/releases/latest'

function Get-StartHereFolder([string]$Shortcut, [string]$Category) {
    foreach ($rule in $NameRules) {
        if ($Shortcut -match $rule.Pattern) { return $rule.Folder }
    }
    if ($CategoryMap.ContainsKey($Category)) { return $CategoryMap[$Category] }
    $Misc
}

$tools = Join-Path $StartHere 'Tools'
foreach ($dir in @((Join-Path $StartHere 'Artifacts')) + (@($Log, $Memory, $Mobile, $Misc, $Disk, $Registry, $Malware, $Network) | ForEach-Object { Join-Path $tools $_ })) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

if (Test-Path $FlareTools) {
    foreach ($lnk in Get-ChildItem -Path $FlareTools -Filter *.lnk -Recurse) {
        $folder = Get-StartHereFolder $lnk.BaseName $lnk.Directory.Name
        Copy-Item -Path $lnk.FullName -Destination (Join-Path $tools $folder) -Force
        [pscustomobject]@{ Shortcut = $lnk.BaseName; Category = $lnk.Directory.Name; Folder = $folder }
    }
}
else { Write-Warning "FLARE tool list folder not found: $FlareTools" }

if (-not $SkipZimmerman) {
    $ez = Join-Path $tools 'ZimmermanTools'
    if ($PSCmdlet.ShouldProcess($ez, 'Download Get-ZimmermanTools.ps1 and run it with -NetVersion 9')) {
        New-Item -ItemType Directory -Force -Path $ez | Out-Null
        $ezScript = Join-Path $ez 'Get-ZimmermanTools.ps1'
        Invoke-WebRequest -UseBasicParsing -Uri $ZimmermanUrl -OutFile $ezScript
        Unblock-File $ezScript
        & $ezScript -Dest $ez -NetVersion 9
    }
}

if (-not $SkipVolatility) {
    $vol = Join-Path $tools "$Memory\volatility3"
    if (Test-Path $vol) { Write-Verbose "Volatility 3 already present: $vol" }
    elseif ($PSCmdlet.ShouldProcess($vol, 'Download the latest Volatility 3 release and pip install it with [full]')) {
        $release = Invoke-RestMethod -UseBasicParsing -Uri $VolatilityApi
        $zip = Join-Path ([IO.Path]::GetTempPath()) "volatility3-$($release.tag_name).zip"
        $src = Join-Path ([IO.Path]::GetTempPath()) "volatility3-$($release.tag_name)"
        Invoke-WebRequest -UseBasicParsing -Uri $release.zipball_url -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $src -Force
        # The zipball holds one folder named after the commit; move it into place.
        Move-Item -Path (Get-ChildItem -Path $src -Directory | Select-Object -First 1).FullName -Destination $vol
        & python -m pip install "$vol[full]"
        if ($LASTEXITCODE) { throw "pip install of Volatility 3 failed with exit code $LASTEXITCODE" }
    }
}
