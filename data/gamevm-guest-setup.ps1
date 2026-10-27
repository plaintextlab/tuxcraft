# tux-gamevm guest-setup: Windows side of the hybrid gaming VM (runs as SYSTEM through the guest agent).
#   * Looking Glass host B7 (must match the Linux client)
#   * a virtual monitor on the passed-through GPU: with nothing plugged into its HDMI port Windows
#     only has a phantom 1024x768 output that never shows a picture, so Looking Glass sees nothing.
#       Windows 11: Virtual Display Driver 25.x (needs IddCx 1.10)
#       Windows 10: Parsec VDD 0.41 (IddCx 1.4) + ParsecVDisplay, which keeps it alive. Tested on
#                   10 21H2: VDD 25.x and Parsec 0.45 fail with code 31; Amyuni works but is 60 Hz only.
#   * the virtual monitor at the Linux screen's mode (tux-gamevm passes it, e.g. 1920 1080 165)
param([int]$Width = 1920, [int]$Height = 1080, [int]$Hz = 60)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$ProgressPreference = 'SilentlyContinue'
$d = 'C:\tuxcraft'; New-Item -ItemType Directory -Force $d | Out-Null
function Get-File($url, $out) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out }
$user = (Get-CimInstance Win32_ComputerSystem).UserName -replace '.*\\'   # the signed-in user
function In-User($name, $cmd) {  # display settings belong to the user's session; the agent runs in session 0
  schtasks /create /f /tn $name /tr $cmd /sc once /st 23:59 /ru $user /it | Out-Null
  schtasks /run /tn $name | Out-Null; Start-Sleep 8; schtasks /delete /f /tn $name | Out-Null
}
if (-not $user) { throw 'nobody is signed in to Windows (the unattended install signs in automatically)' }

Write-Output '== Looking Glass host B7'
if (-not (Get-Service 'Looking Glass (host)' -ErrorAction SilentlyContinue)) {
  Get-File 'https://looking-glass.io/artifact/B7/host' "$d\lg.zip"
  Expand-Archive -Force "$d\lg.zip" "$d\lg"
  Start-Process -Wait "$d\lg\looking-glass-host-setup.exe" -ArgumentList '/S'
}
Get-Service 'Looking Glass (host)' | Format-Table -AutoSize Name, Status, StartType | Out-String | Write-Output

$build = [Environment]::OSVersion.Version.Build
if ($build -ge 22000) {
  Write-Output "== Virtual Display Driver 25.7.23 (Windows 11, build $build)"
  if (-not (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.HardwareID -contains 'Root\MttVDD' })) {
    Get-File 'https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/25.7.23/VirtualDisplayDriver-x86.Driver.Only.zip' "$d\vdd.zip"
    Expand-Archive -Force "$d\vdd.zip" 'C:\'          # -> C:\VirtualDisplayDriver (the driver reads its settings there)
    Get-File 'https://github.com/nefarius/nefcon/releases/download/v1.21.0/nefcon_v1.21.0.zip' "$d\nefcon.zip"
    Expand-Archive -Force "$d\nefcon.zip" "$d\nefcon"
    # Trust the driver's publisher so it installs without a confirmation dialog.
    $cert = (Get-AuthenticodeSignature 'C:\VirtualDisplayDriver\mttvdd.cat').SignerCertificate
    $s = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine'); $s.Open('ReadWrite'); $s.Add($cert); $s.Close()
    $nef = "$d\nefcon\x64\nefconc.exe"
    & $nef --create-device-node --hardware-id 'Root\MttVDD' --class-name Display --class-guid '4d36e968-e325-11ce-bfc1-08002be10318'
    & $nef --install-driver --inf-path 'C:\VirtualDisplayDriver\MttVDD.inf'
  }
} else {
  Write-Output "== Parsec VDD 0.41 + ParsecVDisplay v0.45.1 (Windows 10, build $build)"
  $p = "$d\parsec"; New-Item -ItemType Directory -Force $p | Out-Null
  if (-not (Get-PnpDevice -PresentOnly -Class Display -ErrorAction SilentlyContinue | Where-Object FriendlyName -match 'Parsec')) {
    Get-File 'https://builds.parsec.app/vdd/parsec-vdd-0.41.0.0.exe' "$p\parsec-vdd-0.41.0.0.exe"
    Start-Process -Wait "$p\parsec-vdd-0.41.0.0.exe" -ArgumentList '/S'     # Parsec's signed driver setup
  }
  if (-not (Test-Path "$p\ParsecVDisplay.exe")) {
    Get-File 'https://github.com/nomi-san/parsec-vdd/releases/download/v0.45.1/ParsecVDisplay-v0.45-portable.zip' "$p\pvd.zip"
    Expand-Archive -Force "$p\pvd.zip" $p          # the bundled driver setup (0.45) is not used: code 31 here
  }
  # The driver's extra modes (max 5): the Linux screen's mode first.
  $i = 0
  foreach ($m in @(@($Width, $Height, $Hz), @(1920, 1080, 144), @(1920, 1080, 120))) {
    $k = "HKLM:\SOFTWARE\Parsec\vdd\$i"; New-Item -Force $k | Out-Null
    New-ItemProperty -Force $k -Name width  -PropertyType DWord -Value $m[0] | Out-Null
    New-ItemProperty -Force $k -Name height -PropertyType DWord -Value $m[1] | Out-Null
    New-ItemProperty -Force $k -Name hz     -PropertyType DWord -Value $m[2] | Out-Null
    $i++
  }
  # ParsecVDisplay keeps the display alive (the driver drops it without a ping every 100 ms);
  # FallbackDisplay adds one whenever no other monitor is connected.
  $sid = (New-Object System.Security.Principal.NTAccount($user)).Translate([System.Security.Principal.SecurityIdentifier]).Value
  $app = "Registry::HKEY_USERS\$sid\SOFTWARE\ParsecVDisplay"; New-Item -Force $app | Out-Null
  Set-ItemProperty $app -Name FallbackDisplay -Value '1'
  # v0.45.1 crashes (NullReferenceException in Display.GetDisplayPaths) while no monitor device
  # exists, e.g. after every boot: it reads HKLM\...\Services\monitor\Enum unchecked. Create the
  # empty key first; elevated for that. Task Scheduler restarts it if it ever exits.
  Set-Content "$d\parsec-start.ps1" @'
$k = 'HKLM:\SYSTEM\CurrentControlSet\Services\monitor\Enum'
if (-not (Test-Path $k)) { New-Item -Force $k | Out-Null; New-ItemProperty -Force $k -Name Count -PropertyType DWord -Value 0 | Out-Null }
& 'C:\tuxcraft\parsec\ParsecVDisplay.exe' -silent | Out-Null
exit 1
'@
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $d\parsec-start.ps1"
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $user; $trg.Delay = 'PT5S'
  $set = New-ScheduledTaskSettingsSet -RestartCount 20 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
  $pri = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName 'tux-gamevm parsec display' -Action $act -Trigger $trg -Settings $set -Principal $pri -Force | Out-Null
  if (-not (Get-Process ParsecVDisplay -ErrorAction SilentlyContinue)) { Start-ScheduledTask -TaskName 'tux-gamevm parsec display' }
  Start-Sleep 10
}

Write-Output "== Screen at ${Width}x${Height} @ $Hz Hz"
Set-Content "$d\screen-mode.ps1" @"
`$W = $Width; `$H = $Height; `$F = $Hz
"@
Add-Content "$d\screen-mode.ps1" @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Res {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DEVMODE { [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency,
    dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lParam);
  public static string Set(string dev, int w, int h, int hz) {
    DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(dev, -1, ref dm)) return "no settings";
    dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmDisplayFrequency = hz; dm.dmFields = 0x80000 | 0x100000 | 0x400000;
    int r = ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, 1, IntPtr.Zero);   // CDS_UPDATEREGISTRY: Windows keeps it
    DEVMODE cur = new DEVMODE(); cur.dmSize = dm.dmSize; EnumDisplaySettings(dev, -1, ref cur);
    return "result " + r + ", now " + cur.dmPelsWidth + "x" + cur.dmPelsHeight + "@" + cur.dmDisplayFrequency;
  }
}
"@
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
  "$($s.DeviceName) -> ${W}x${H}@${F}: $([Res]::Set($s.DeviceName, $W, $H, $F))" | Out-File -Append C:\tuxcraft\display.log
}
'@
In-User 'tux-gamevm screen' "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $d\screen-mode.ps1"
Get-Content "$d\display.log" -Tail 2 -ErrorAction SilentlyContinue
Restart-Service 'Looking Glass (host)'

Get-PnpDevice -PresentOnly -Class Display | Format-Table -AutoSize Status, FriendlyName | Out-String -Width 150 | Write-Output
Write-Output 'GUEST-SETUP-DONE'
