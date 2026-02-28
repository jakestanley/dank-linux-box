Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Administrator {
    $currentUser = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        return
    }

    if (-not $PSCommandPath) {
        throw 'Cannot self-elevate because PSCommandPath is unavailable.'
    }

    Write-Host 'Elevation required. Launching elevated installer...'
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait -PassThru
    if ($null -eq $proc) {
        throw 'Failed to launch elevated installer process.'
    }
    exit $proc.ExitCode
}

function Set-FileContentIfChanged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $needsWrite = $true
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -ceq $Content) {
            $needsWrite = $false
        }
    }

    if ($needsWrite) {
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }
}

function Get-ImageMagickCommand {
    $cmd = Get-Command magick -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw "ImageMagick is required to create a Windows .ico from Linux SVG. Install ImageMagick so 'magick' is available in PATH."
    }
    return $cmd.Source
}

function Get-CSharpCompiler {
    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $cmd = Get-Command csc -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    throw "C# compiler not found. Install .NET Framework developer tools so csc.exe is available."
}

function Get-LinuxFirmwareIdentifier {
    $output = & bcdedit /enum firmware 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit failed while enumerating firmware entries.`n$output"
    }

    $joined = ($output | Out-String)
    $blocks = [Regex]::Split($joined, "(\r?\n){2,}")

    $exactShimId = $null
    $shimFamilyId = $null
    $linuxAnyId = $null

    foreach ($block in $blocks) {
        $pathMatch = [Regex]::Match($block, '(?im)^\s*path\s+(\\EFI\\[^\r\n]+)\s*$')
        if (-not $pathMatch.Success) {
            continue
        }

        $pathValue = $pathMatch.Groups[1].Value
        $idMatch = [Regex]::Match($block, '(?im)^\s*identifier\s+(\{[0-9a-fA-F\-]+\})\s*$')
        if (-not $idMatch.Success) {
            continue
        }

        $idValue = $idMatch.Groups[1].Value

        if ($pathValue -imatch '^\\EFI\\SYSTEMD\\SYSTEMD-BOOTX64\.EFI$') {
            $exactShimId = $idValue
            break
        }

        if (-not $shimFamilyId -and $pathValue -imatch '^\\EFI\\SYSTEMD\\BOOTX64\.EFI$') {
            $shimFamilyId = $idValue
        }

        if (-not $linuxAnyId -and $pathValue -imatch '^\\EFI\\SYSTEMD\\.+\.EFI$') {
            $linuxAnyId = $idValue
        }
    }

    if ($exactShimId) { return $exactShimId }
    if ($shimFamilyId) { return $shimFamilyId }
    if ($linuxAnyId) { return $linuxAnyId }

    throw "Could not find any firmware entry under \EFI\SYSTEMD\ in 'bcdedit /enum firmware'."
}

function Confirm-LinuxIdentifier {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identifier
    )

    Write-Host ''
    Write-Host "Detected Linux firmware identifier: $Identifier"
    $answer = Read-Host 'Proceed with this identifier? [y/N]'
    if ($answer -notmatch '^(?i:y(?:es)?)$') {
        throw 'Installation cancelled by user before making changes.'
    }
}

function Download-LinuxLogo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    $commonsUrl = 'https://upload.wikimedia.org/wikipedia/commons/3/35/Tux.svg'
    $tmpOutFile = "$OutFile.download"
    Invoke-WebRequest -Uri $commonsUrl -OutFile $tmpOutFile -UseBasicParsing
    Move-Item -LiteralPath $tmpOutFile -Destination $OutFile -Force
}

function Convert-SvgToIco {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MagickPath,
        [Parameter(Mandatory = $true)]
        [string]$SvgPath,
        [Parameter(Mandatory = $true)]
        [string]$IcoPath
    )

    if (-not (Test-Path -LiteralPath $SvgPath)) {
        throw "SVG file not found: $SvgPath"
    }

    $edgeAlphaMultiplier = 0.75
    $sizes = @(256, 128, 64, 48, 32, 24, 16)
    $tmpIco = "$IcoPath.tmp"
    $tmpPngPaths = New-Object 'System.Collections.Generic.List[string]'
    $frames = New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($size in $sizes) {
            $tmpPng = "$IcoPath.$size.png"
            $tmpPngPaths.Add($tmpPng)

            & $MagickPath $SvgPath -background none -resize "${size}x${size}" "png32:$tmpPng"
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpPng)) {
                throw "ImageMagick failed rendering Linux SVG at ${size}x${size}."
            }

            & $MagickPath "png32:$tmpPng" -channel A -fx "u<1 ? u*$edgeAlphaMultiplier : u" +channel "png32:$tmpPng"
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpPng)) {
                throw "ImageMagick failed applying edge transparency adjustment at ${size}x${size}."
            }

            $pngInfo = Get-Item -LiteralPath $tmpPng
            if ($pngInfo.Length -le 0) {
                throw "Rendered PNG is empty at ${size}x${size}: $tmpPng"
            }

            $frames.Add([PSCustomObject]@{
                Size  = $size
                Bytes = [System.IO.File]::ReadAllBytes($tmpPng)
            }) | Out-Null
        }

        $count = $frames.Count
        if ($count -eq 0) {
            throw "No icon frames were generated."
        }

        $iconDirSize = 6 + (16 * $count)
        $offset = [uint32]$iconDirSize

        $fs = [System.IO.File]::Open($tmpIco, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $bw = New-Object System.IO.BinaryWriter($fs)
            $bw.Write([UInt16]0)       # reserved
            $bw.Write([UInt16]1)       # type: icon
            $bw.Write([UInt16]$count)  # frame count

            foreach ($frame in $frames) {
                $size = [int]$frame.Size
                $bytes = [byte[]]$frame.Bytes
                $imageSize = [uint32]$bytes.Length

                $bw.Write([Byte]($(if ($size -ge 256) { 0 } else { $size })))
                $bw.Write([Byte]($(if ($size -ge 256) { 0 } else { $size })))
                $bw.Write([Byte]0)         # color count
                $bw.Write([Byte]0)         # reserved
                $bw.Write([UInt16]1)       # planes
                $bw.Write([UInt16]32)      # bit count
                $bw.Write($imageSize)
                $bw.Write($offset)
                $offset = [uint32]($offset + $imageSize)
            }

            foreach ($frame in $frames) {
                $bw.Write([byte[]]$frame.Bytes)
            }
            $bw.Flush()
        }
        finally {
            $fs.Dispose()
        }
    }
    finally {
        foreach ($tmp in $tmpPngPaths) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $tmpIco)) {
        throw "Failed to create ICO from rendered bitmap."
    }
    Move-Item -LiteralPath $tmpIco -Destination $IcoPath -Force
}

function Build-RebootExe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CscPath,
        [Parameter(Mandatory = $true)]
        [string]$LinuxIdentifier,
        [Parameter(Mandatory = $true)]
        [string]$IconPath,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$ExePath
    )

    $sourceTemplate = @'
using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string linuxId = "__SYSTEMD_ID__";
        bool confirmed = false;
        foreach (string arg in args)
        {
            if (string.Equals(arg, "--confirmed", StringComparison.OrdinalIgnoreCase))
            {
                confirmed = true;
                break;
            }
        }

        if (!confirmed)
        {
            DialogResult result = MessageBox.Show(
                "Reboot into Linux now?",
                "Reboot to Linux",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);
            if (result != DialogResult.Yes)
            {
                return 0;
            }
        }

        if (!IsAdministrator())
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = Application.ExecutablePath,
                    Arguments = "--confirmed",
                    UseShellExecute = true,
                    Verb = "runas",
                    WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory
                };
                Process.Start(psi);
                return 0;
            }
            catch (Exception ex)
            {
                MessageBox.Show("Failed to elevate: " + ex.Message, "Reboot to Linux", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        try
        {
            RunHidden("bcdedit", "/set {fwbootmgr} bootsequence " + linuxId);
            RunHidden("shutdown", "/r /t 0");
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Failed to set boot target or reboot: " + ex.Message, "Reboot to Linux", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static bool IsAdministrator()
    {
        WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static void RunHidden(string fileName, string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        using (Process process = Process.Start(psi))
        {
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException(fileName + " exited with code " + process.ExitCode + ".");
            }
        }
    }
}
'@

    $source = $sourceTemplate.Replace('__SYSTEMD_ID__', $LinuxIdentifier)
    Set-FileContentIfChanged -Path $SourcePath -Content $source

    & $CscPath `
        '/nologo' `
        '/optimize+' `
        '/target:winexe' `
        "/win32icon:$IconPath" `
        "/out:$ExePath" `
        '/r:System.Windows.Forms.dll' `
        '/r:System.Drawing.dll' `
        $SourcePath

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ExePath)) {
        throw "Failed to compile launcher executable with csc."
    }
}

$startMenuProgramsDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuProgramsDir 'Reboot to Linux.lnk'

Ensure-Administrator

Write-Host 'Resolving Linux firmware identifier from bcdedit...'
$linuxId = Get-LinuxFirmwareIdentifier
Confirm-LinuxIdentifier -Identifier $linuxId

$magickPath = Get-ImageMagickCommand
$cscPath = Get-CSharpCompiler

$installDir = Join-Path $env:LOCALAPPDATA 'RebootToLinux'
$sourcePath = Join-Path $installDir 'reboot-to-linux.cs'
$exeLauncherPath = Join-Path $installDir 'reboot-to-linux.exe'
$svgIconPath = Join-Path $installDir 'linux-logo.svg'
$icoIconPath = Join-Path $installDir 'linux-logo.ico'

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $startMenuProgramsDir -Force | Out-Null

Write-Host 'Downloading Linux logo...'
Download-LinuxLogo -OutFile $svgIconPath

Write-Host 'Converting Linux SVG to Windows ICO...'
Convert-SvgToIco -MagickPath $magickPath -SvgPath $svgIconPath -IcoPath $icoIconPath

Write-Host 'Building native launcher executable...'
Build-RebootExe -CscPath $cscPath -LinuxIdentifier $linuxId -IconPath $icoIconPath -SourcePath $sourcePath -ExePath $exeLauncherPath

if (-not (Test-Path -LiteralPath $icoIconPath)) {
    throw "Expected icon file was not created: $icoIconPath"
}

if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
}

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exeLauncherPath
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $installDir
$shortcut.IconLocation = $icoIconPath
$shortcut.Description = 'Prompt and reboot into Linux on next boot'
$shortcut.Save()

$savedShortcut = $wsh.CreateShortcut($shortcutPath)
if ($savedShortcut.IconLocation -notlike "$icoIconPath*") {
    throw "Shortcut icon assignment failed. Expected icon path: $icoIconPath ; actual: $($savedShortcut.IconLocation)"
}

Write-Host ''
Write-Host 'Install complete.'
Write-Host "Linux identifier: $linuxId"
Write-Host "Logo SVG: $svgIconPath"
Write-Host "Logo ICO: $icoIconPath"
Write-Host "Launcher Source: $sourcePath"
Write-Host "Launcher EXE: $exeLauncherPath"
Write-Host "Shortcut: $shortcutPath"
Write-Host ''
Write-Host 'You can pin "Reboot to Linux" from the Start Menu to the taskbar.'
