# tux-gamevm guest-setup: Windows side of the hybrid gaming VM (runs as SYSTEM through the guest agent).
#   * Looking Glass host B7 (must match the Linux client)
#   * a virtual monitor on the passed-through GPU: with nothing plugged into its HDMI port Windows
#     only has a phantom 1024x768 output that never shows a picture, so Looking Glass sees nothing.
#       Windows 11: Virtual Display Driver 25.x (needs IddCx 1.10)
#       Windows 10: Amyuni usbmmidd v2 (WHQL-signed, IddCx 1.2; VDD 25.x fails there with
#                   IddCxDeviceInitConfig 0xC000000D), switched on again by a startup task
#   * the virtual monitor at 1920x1080 (Windows picks the first mode, 1024x768, otherwise)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$ProgressPreference = 'SilentlyContinue'
$d = 'C:\tuxcraft'; New-Item -ItemType Directory -Force $d | Out-Null
function Get-File($url, $out) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out }
$user = (Get-CimInstance Win32_ComputerSystem).UserName -replace '.*\\'   # the signed-in user

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
  Write-Output "== Amyuni usbmmidd v2 (Windows 10, build $build)"
  if (-not (Get-PnpDevice -PresentOnly -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'USB Mobile Monitor' })) {
    Get-File 'https://www.amyuni.com/downloads/usbmmidd_v2.zip' "$d\usbmmidd.zip"
    Expand-Archive -Force "$d\usbmmidd.zip" $d
    Push-Location "$d\usbmmidd_v2"
    & .\deviceinstaller64.exe install usbmmidd.inf usbmmidd
    & .\deviceinstaller64.exe enableidd 1
    Pop-Location
  }
  # enableidd adds one monitor per call: at boot remove one (if any survived) and add one.
  $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c cd /d $d\usbmmidd_v2 && deviceinstaller64.exe enableidd 0 & deviceinstaller64.exe enableidd 1"
  Register-ScheduledTask -TaskName 'tux-gamevm virtual monitor' -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
}
Start-Sleep 5

Write-Output '== Screen at 1920x1080'
# Display settings belong to the signed-in user's session; the agent runs in session 0.
Set-Content "$d\res1080.ps1" @'
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
  public static int Set(string dev, int w, int h) {
    DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(dev, -1, ref dm)) return -100;
    dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000;
    return ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, 1, IntPtr.Zero);
  }
}
"@
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
  "$($s.DeviceName) -> 1920x1080: $([Res]::Set($s.DeviceName, 1920, 1080))" | Out-File -Append C:\tuxcraft\display.log
}
'@
if ($user) {
  $t = 'tux-gamevm screen'
  schtasks /create /f /tn $t /tr "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $d\res1080.ps1" /sc once /st 23:59 /ru $user /it | Out-Null
  schtasks /run /tn $t | Out-Null; Start-Sleep 8; schtasks /delete /f /tn $t | Out-Null
  Get-Content "$d\display.log" -Tail 2 -ErrorAction SilentlyContinue
} else { Write-Output 'nobody signed in: set 1920x1080 in Display settings yourself' }

Get-PnpDevice -PresentOnly -Class Display | Format-Table -AutoSize Status, FriendlyName | Out-String -Width 150 | Write-Output
Write-Output 'GUEST-SETUP-DONE'
