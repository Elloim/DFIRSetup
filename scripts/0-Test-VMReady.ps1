<#
.SYNOPSIS
Reports whether this VM is ready for the FLARE-VM install. Changes nothing.
.DESCRIPTION
Checks administrator rights, OS build, free space on the system drive, RAM,
and the Defender and Tamper Protection state. FLARE-VM needs Tamper Protection
and Defender turned off before it runs; this script only reports them.
#>
[CmdletBinding()]
param(
    [int]$MinFreeGB = 150
)
$ErrorActionPreference = 'Stop'

function New-Row([string]$Check, $Value, [string]$Status, [string]$Advice) {
    [pscustomobject]@{ Check = $Check; Value = $Value; Status = $Status; Advice = $Advice }
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$os = Get-CimInstance Win32_OperatingSystem
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
$freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
$ramGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$mp = $null
try { $mp = Get-MpComputerStatus } catch { Write-Verbose "Get-MpComputerStatus failed: $_" }

$rows = @(
    if ($isAdmin) { New-Row 'Administrator' $true 'OK' '' }
    else { New-Row 'Administrator' $false 'WARN' 'Run from an elevated Windows PowerShell.' }

    if ($os.Version -like '10.*' -and $os.OSArchitecture -like '64*') { New-Row 'OS' "$($os.Caption) build $($os.BuildNumber)" 'OK' '' }
    else { New-Row 'OS' "$($os.Caption) build $($os.BuildNumber) $($os.OSArchitecture)" 'WARN' 'FLARE-VM needs Windows 10 or 11 x64.' }

    if ($freeGB -ge $MinFreeGB) { New-Row "Free space $env:SystemDrive" "$freeGB GB" 'OK' '' }
    else { New-Row "Free space $env:SystemDrive" "$freeGB GB" 'WARN' "Grow the disk to at least $MinFreeGB GB free." }

    New-Row 'RAM' "$ramGB GB" 'INFO' ''

    if (-not $mp) { New-Row 'Defender' 'not reported' 'INFO' 'Get-MpComputerStatus returned nothing.' }
    else {
        if ($mp.RealTimeProtectionEnabled) { New-Row 'Defender real-time protection' $true 'WARN' 'Turn it off before running FLARE-VM (see the FLARE-VM README).' }
        else { New-Row 'Defender real-time protection' $false 'OK' '' }
        if ($mp.IsTamperProtected) { New-Row 'Tamper Protection' $true 'WARN' 'Turn it off in Windows Security first, or Defender settings will not stick.' }
        else { New-Row 'Tamper Protection' $false 'OK' '' }
    }
)
$rows
