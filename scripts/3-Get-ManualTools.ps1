<#
.SYNOPSIS
Downloads the tools FLARE-VM does not package, as listed in manifests\manual-tools.json.
.DESCRIPTION
Each entry lands in Start Here\Tools\<folder>. Entries whose folder already has
files are skipped, so you can rerun the script. Every download is logged with its
SHA256 in Tools\manual-tools.log. Gated entries are printed as a checklist and
never downloaded. -WhatIf lists every entry and its destination without any
network access. Extracting .7z files and password-protected zips needs 7-Zip,
which FLARE-VM installs.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Manifest = (Join-Path $PSScriptRoot '..\manifests\manual-tools.json'),
    [string]$ToolsRoot = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Start Here\Tools'),
    [string]$SevenZip = (Join-Path $env:ProgramFiles '7-Zip\7z.exe')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$log = Join-Path $ToolsRoot 'manual-tools.log'
$cache = Join-Path ([IO.Path]::GetTempPath()) 'cd-dfir-downloads'

function Get-SourceUrl($Tool) {
    switch ($Tool.kind) {
        'github-release' {
            # source is owner/repo, or owner/repo@tag to pin a release.
            $repo, $tag = $Tool.source -split '@', 2
            $api = if ($tag) { "https://api.github.com/repos/$repo/releases/tags/$tag" } else { "https://api.github.com/repos/$repo/releases/latest" }
            $assets = @((Invoke-RestMethod -UseBasicParsing -Uri $api).assets | Where-Object { $_.name -match $Tool.assetPattern })
            if (-not $assets) { throw "no asset in $api matches '$($Tool.assetPattern)'" }
            $assets.browser_download_url
        }
        'github-archive' {
            # source is owner/repo for the whole default branch, or owner/repo/path for one file in it.
            $owner, $repo, $path = $Tool.source -split '/', 3
            if ($path) { "https://github.com/$owner/$repo/raw/HEAD/$path" } else { "https://github.com/$owner/$repo/archive/HEAD.zip" }
        }
        'url' { $Tool.source }
    }
}

function Save-Download($Tool, [string]$Url) {
    $dir = Join-Path $cache $Tool.name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir ([IO.Path]::GetFileName(([uri]$Url).AbsolutePath))
    # NirSoft refuses downloads without a Referer, and SourceForge sends an HTML
    # page instead of the file to browser User-Agents. Other hosts ignore both.
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $file -Headers @{ Referer = $Url } -UserAgent 'cd-dfir-vm'
    $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash
    Add-Content -Path $log -Value ("{0:s}`t{1}`t{2}`t{3}" -f (Get-Date), $Tool.name, $Url, $hash)
    Write-Verbose "$($Tool.name): $Url SHA256 $hash"
    $file
}

function Test-ReleaseHash($Tool, [string]$File) {
    # hashFile names a release asset that lists the expected hashes.
    $repo, $tag = $Tool.source -split '@', 2
    $asset = (Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$repo/releases/tags/$tag").assets | Where-Object { $_.name -eq $Tool.hashFile }
    $list = (Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -UserAgent 'cd-dfir-vm').Content
    if ($list -is [byte[]]) { $list = [Text.Encoding]::ASCII.GetString($list) }
    $known = foreach ($alg in 'SHA256', 'SHA1', 'MD5') { (Get-FileHash -Path $File -Algorithm $alg).Hash }
    if (-not ($known | Where-Object { $list -match $_ })) { throw "$File matches no hash in $($Tool.hashFile)" }
}

function Expand-Download($Tool, [string]$File, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    if ($File -match '\.zip$' -and -not $Tool.zipPassword) {
        Expand-Archive -Path $File -DestinationPath $Dest -Force
    }
    elseif ($File -match '\.(zip|7z)$') {
        if (-not (Test-Path $SevenZip)) { throw "7-Zip not found at $SevenZip" }
        $sevenArgs = @('x', '-y', "-o$Dest")
        if ($Tool.zipPassword) { $sevenArgs += "-p$($Tool.zipPassword)" }
        & $SevenZip @sevenArgs $File | Out-Null
        if ($LASTEXITCODE) { throw "7-Zip exited with $LASTEXITCODE on $File" }
    }
    elseif ($File -match '\.gz$') {
        $in = [IO.File]::OpenRead($File)
        $out = [IO.File]::Create((Join-Path $Dest ([IO.Path]::GetFileNameWithoutExtension($File))))
        try { (New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)).CopyTo($out) }
        finally { $out.Dispose(); $in.Dispose() }
    }
    else { Copy-Item -Path $File -Destination $Dest -Force }
}

$failed = 0
foreach ($tool in (Get-Content -Raw -Path $Manifest | ConvertFrom-Json)) {
    $dest = if ($tool.kind -eq 'pip') { 'python -m pip' } elseif ($tool.folder) { Join-Path $ToolsRoot $tool.folder } else { '' }
    $row = [pscustomobject]@{ Name = $tool.name; Kind = $tool.kind; Destination = $dest; Action = '' }

    if ($tool.kind -eq 'gated') {
        $row.Action = "download by hand from $($tool.source)"
    }
    elseif ($tool.kind -ne 'pip' -and (Test-Path -LiteralPath $dest) -and (Get-ChildItem -LiteralPath $dest | Select-Object -First 1)) {
        $row.Action = 'skipped, already present'
    }
    elseif (-not $PSCmdlet.ShouldProcess("$($tool.name) -> $dest", "Get $($tool.kind) $($tool.source)")) {
        $row.Action = 'would download'
    }
    else {
        try {
            New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
            if ($tool.kind -eq 'pip') {
                & python -m pip install $tool.source
                if ($LASTEXITCODE) { throw "pip exited with $LASTEXITCODE" }
                Add-Content -Path $log -Value ("{0:s}`t{1}`tpip install {2}`tn/a, pip checks PyPI hashes" -f (Get-Date), $tool.name, $tool.source)
            }
            else {
                foreach ($url in Get-SourceUrl $tool) {
                    $file = Save-Download $tool $url
                    if ($tool.hashFile) { Test-ReleaseHash $tool $file }
                    Expand-Download $tool $file $dest
                }
            }
            $row.Action = 'installed'
        }
        catch {
            $failed++
            # The folder was missing or empty before this run, so a rerun can try again.
            if ($tool.kind -ne 'pip') { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
            $row.Action = "FAILED: $_"
        }
    }
    $row
}
if ($failed) { throw "$failed manual tool(s) failed; see the Action column above." }
