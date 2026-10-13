<#
.SYNOPSIS
Downloads FLARE-VM's install.ps1 and runs it with config\cd-dfir-config.xml.
.DESCRIPTION
Run in an elevated Windows PowerShell on the target VM, after 0-Test-VMReady.ps1
reports Defender and Tamper Protection as off. FLARE-VM reboots the VM several
times and logs back in with -Password. Use -WhatIf to print the command only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Config = (Join-Path $PSScriptRoot '..\config\cd-dfir-config.xml'),
    [securestring]$Password,
    [string]$InstallUrl = 'https://raw.githubusercontent.com/mandiant/flare-vm/main/install.ps1',
    [switch]$NoChecks,
    [switch]$NoReboots
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Config = (Resolve-Path $Config).Path
$installer = Join-Path ([IO.Path]::GetTempPath()) 'flare-vm-install.ps1'
$flareArgs = @('-customConfig', $Config, '-noWait', '-noGui')
if ($NoChecks) { $flareArgs += '-noChecks' }
if ($NoReboots) { $flareArgs += '-noReboots' }

$shown = $flareArgs | ForEach-Object { if ($_ -match ' ') { "'$_'" } else { $_ } }
$command = "& '$installer' $($shown -join ' ') -password ********"
if (-not $PSCmdlet.ShouldProcess($command, "Download $InstallUrl and run it")) { return }

if (-not $Password) { $Password = Read-Host 'Windows password for FLARE-VM auto-logon' -AsSecureString }
Invoke-WebRequest -UseBasicParsing -Uri $InstallUrl -OutFile $installer
Unblock-File $installer
& $installer @flareArgs -password ([pscredential]::new('flare', $Password).GetNetworkCredential().Password)
