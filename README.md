# cd-dfir-vm

This kit turns a clean Windows 10 or 11 x64 VM into a DFIR workstation laid out like the CyberDefenders cloud-lab image. It installs FLARE-VM with a custom package list, then builds `Desktop\Start Here\{Artifacts,Tools}` and adds 28 tools that FLARE-VM does not package.

## Run Order

Run every script from an elevated Windows PowerShell 5.1 prompt on the target VM. Take a snapshot first. Each script that writes or downloads accepts `-WhatIf`.

1. `.\scripts\0-Test-VMReady.ps1` reports administrator rights, OS build, free disk space, RAM, and the Defender and Tamper Protection state. It warns below 150 GB free and changes nothing.
2. Turn off Tamper Protection and Defender yourself, as the [FLARE-VM README](https://github.com/mandiant/flare-vm) describes. No script in this kit touches Defender.
3. `.\scripts\1-Install-Flare.ps1` downloads FLARE-VM's `install.ps1`, unblocks it, and runs it with `config\cd-dfir-config.xml`. It asks for your Windows password because FLARE-VM logs back in after each reboot. The VM reboots several times. `-NoChecks` and `-NoReboots` pass through to FLARE-VM.
4. `.\scripts\2-Build-StartHere.ps1` creates the Start Here tree and copies every FLARE shortcut into a category folder. It also downloads Eric Zimmerman's tools into `Tools\ZimmermanTools` and installs the latest Volatility 3 release into `Tools\Memory Analysis\volatility3` with `pip install .[full]`. Use `-SkipZimmerman` or `-SkipVolatility` to leave either out.
5. `.\scripts\3-Get-ManualTools.ps1` downloads the entries in `manifests\manual-tools.json`. Each tool lands in `Start Here\Tools\<folder>`, and the script skips folders that already have files, so you can rerun it. It appends every download with its SHA256 to `Start Here\Tools\manual-tools.log`, and it prints the gated tools as a checklist at the end of its table.

## Shortcut Placement

`2-Build-StartHere.ps1` checks name rules first, and the first match wins. Next it maps the FLARE category, which is the `<tags>` value of each VM-Packages nuspec. Unmatched shortcuts go to `Miscellaneous`. Both tables sit at the top of the script, together with the folder names. No lab writeup shows `Disk Forensics`, `Registry`, `Malware Analysis` or `Network Analysis`, so we chose those names. Rename them there.

## Manifest

Each entry in `manifests/manual-tools.json` has a `name`, a `folder` under Start Here\Tools, a `kind`, a `source`, an `assetPattern`, and `notes`.

- `github-release` sources take the form `owner/repo`, or `owner/repo@tag` to pin a release. `assetPattern` is a regex, and the script downloads every asset it matches.
- `github-archive` sources take the form `owner/repo` for the default branch as a zip, or `owner/repo/path` for one file in that branch.
- `url` sources are direct download links.
- `pip` sources are PyPI package names.
- `gated` sources are vendor pages. The script never downloads them.

Two optional fields cover single tools. `zipPassword` lets 7-Zip open PasswordFox's zip. `hashFile` names a release asset that lists hashes, and Volatility 2.6 uses it to check its download.

## Gated Tools

Get these by hand and put them in the folder shown.

- [ ] KAPE into `Disk Forensics\KAPE` from https://www.kroll.com/en/services/cyber-risk/investigate-and-respond/kroll-artifact-parser-extractor-kape. The licence bars paid engagements on third-party networks.
- [ ] NTFS Log Tracker into `Disk Forensics\NTFS Log Tracker` from https://sites.google.com/site/forensicnote/ntfs-log-tracker, which links a Google Drive download.
- [ ] R-Studio into `Disk Forensics\R-Studio` from https://www.r-studio.com/.
- [ ] 4n6 Outlook Forensics Wizard into `Miscellaneous\4n6 Outlook Forensics Wizard` from https://forensiksoft.com/outlook-forensics.html.
- [ ] USB Forensic Tracker into `Registry\USB Forensic Tracker`. Its vendor page at https://www.orionforensics.com/ no longer lists it, so find a copy you trust.
- [ ] An Event Log Explorer licence key from https://eventlogxp.com/. FLARE-VM installs the program, but the free personal key excludes forensic and corporate use.
- [ ] Maltego CE from https://www.maltego.com/downloads/. It needs a free account.
- [ ] Sublime Text from https://www.sublimetext.com/download.

## Known Differences From the Lab Image

- The lab keeps Zimmerman's tools in `ZimmermanTools\net6\`. `Get-ZimmermanTools.ps1` accepts only `-NetVersion` 0, 4 or 9, so this kit writes `ZimmermanTools\net9\`. Writeup paths that name `net6` need `net9` here.
- The lab has a `Memory Analysis\MemProcFS` folder. FLARE-VM installs MemProcFS under `C:\Tools`, so this kit puts a MemProcFS shortcut in `Memory Analysis` instead.
- The lab's Tools folder holds a mix of folders and loose executables such as `floss.exe`. This kit copies FLARE shortcuts, so most entries are `.lnk` files.
- GitHub archive downloads unpack into a subfolder named after the repo and commit, such as `RegRipper3.0\RegRipper3.0-ec96dd4...`. Volatility 2.6, rifiuti2 and ClamAV also unpack into their own subfolders.
- FLARE-VM's upstream config, which this kit keeps unchanged apart from the package list, turns off Windows Firewall and adds seven system locales.
- Zui ships only an installer for Windows. The script saves `Zui-Setup-<version>.exe` in `Network Analysis\Zui`, and you run it.
- The script does not check ClamAV's GPG signature because the VM has no gpg. To check it, fetch `https://www.clamav.net/downloads/production/clamav-1.5.4.win.x64.zip.sig` and verify it with the Talos key on another machine.
- dfir-unfurl 20261007 needs Python 3.11 or newer. If FLARE's Python is older, pip fails for that entry, and the other entries still install.
- Two upstream repos have moved. HindSight now lives at RyanDFIR/hindsight and Zui at superdb/zui, and the manifest uses the new names.

## Unresolved

All 28 downloadable sources resolved on 13 Oct 2026. Each GitHub API query found its asset, and each URL returned HTTP 200 or a redirect to the file. Two hosts need special handling, and the script provides it:

- NirSoft returns a 403 page for PasswordFox unless the request carries a Referer.
- SourceForge sends an HTML page instead of the DiffUtils zip when the request carries a browser User-Agent or a Referer, so the script sends the Referer to nirsoft.net only.

Two gated pages fail to scripts but work in a browser. Kroll's KAPE page returns 403 to scripted requests because of Cloudflare, and the old USB Forensic Tracker product page returns 404.

## Tests

The tests run on Windows PowerShell 5.1 or pwsh 7 with Pester 5 and PSScriptAnalyzer:

    Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck
    Install-Module PSScriptAnalyzer -Scope CurrentUser
    $env:VM_PACKAGES_CLONE = 'C:\src\VM-Packages'   # optional, a blobless clone
    Invoke-Pester .\tests

They check five things:

- Every script parses and contains only ASCII, with no PSScriptAnalyzer errors and no syntax newer than PowerShell 5.1.
- The config holds exactly the 90 packages in `tests/fixtures/packages.txt`. Every other section matches the upstream snapshot in `tests/fixtures/upstream-config.xml`.
- If you set `VM_PACKAGES_CLONE`, every package exists in mandiant/VM-Packages. Make the clone with `git clone --filter=blob:none https://github.com/mandiant/VM-Packages`.
- Fake FLARE shortcuts from `tests/fixtures/flare-shortcuts.csv` land in the expected Start Here folders.
- `3-Get-ManualTools.ps1 -WhatIf` lists every manifest entry with its destination and never touches the network.
