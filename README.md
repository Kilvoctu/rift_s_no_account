I recently received a Rift S headset and wanted to use it without creating a Meta/Oculus/whatever account. After fairly heavy LLM usage, a process was created. I'm sharing this guide in case it helps anyone else (the LLM also wrote the guide, which I edited and cleaned up the best I can for human readibility).  
I don't provide support, any 1-click setup app/script, nor make guarantees it will work for you. All the steps are laid out transparently, so you can see exactly what is being done to your system.


--------------------
## Rift S without a Meta account setup guide

A complete, from-scratch guide to using an Oculus Rift S on a Windows PC with zero Meta account or telemetry.

| Works (no account needed) | Does not work (needs an account) |
|---|---|
| Headset display, audio, mic | Oculus store / app library |
| Inside-out tracking (all 5 cameras) | Social, casting, remote desktop |
| Both Touch controllers | Firmware/software updates (intentionally blocked) |
| SteamVR games (OpenVR) | OculusClient home screen (never opens) |
| OpenXR games via SteamVR | |
| Everything through Steam | |

---

### Requirements

- Oculus Rift S + both Touch controllers
- A free DisplayPort output on your GPU
- USB 3.0 port at SS10 speed or better
- Steam + SteamVR installed
- Windows 10/11, admin rights for the one-time setup

---

### Step 1 - Install the Oculus software

The official download page now nags you to log in just to download. Avoid it entirely with winget (built into Windows 10/11):

```bat
winget install -e --id Meta.Oculus
```

This downloads the identical official package and installs it silently. If winget is unavailable on your system, use the installer from Meta's site instead; if it opens a login window when it finishes, simply close the window.

Notes:

- Reboot if the installer asks.
- The installer downloads from Meta's CDN, so apply the network blocks in Step 3 only after installation is complete.
- Don't sign in. You will not be asked to again once Step 3 is done.
- Default install location: `C:\Program Files\Oculus\` (yours may differ, so remember the path, it's used below).

---

### Step 2 - Windows camera privacy

Windows gates camera hardware behind a privacy setting, and the Rift S tracking cameras are, to Windows, cameras. You need this for tracking to work.

1. `Settings` → `Privacy & security` → `Camera` (on Windows 10: `Settings` → `Privacy` → `Camera`)
2. Turn **on** "Let apps access your camera"
3. Turn **on** access for desktop apps as well

---

### Step 3 - Remove the nagging, phone-home, and more

All commands below run in an **elevated** terminal (right-click → Run as administrator).

#### 3a. Block the in-headset wall (Dash) and block updates

```bat
reg add "HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config" /v PreventDashLaunch /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config" /v CoreChannel /t REG_SZ /d NO_UPDATES /f
```

- `PreventDashLaunch=1` - the dashboard/launcher can never auto-start.
- `CoreChannel=NO_UPDATES` - the software stops checking for updates.

#### 3b. Sinkhole the phone-home domains

Back up the hosts file first (same elevated prompt):

```bat
copy C:\Windows\System32\drivers\etc\hosts C:\Windows\System32\drivers\etc\hosts.oculus-backup
```

Then append these six lines (works in both CMD and PowerShell):

```bat
echo 127.0.0.1 graph.oculus.com >> C:\Windows\System32\drivers\etc\hosts
echo 127.0.0.1 edge-mqtt.facebook.com >> C:\Windows\System32\drivers\etc\hosts
echo 127.0.0.1 scontent.oculuscdn.com >> C:\Windows\System32\drivers\etc\hosts
echo 127.0.0.1 securecdn.oculus.com >> C:\Windows\System32\drivers\etc\hosts
echo 127.0.0.1 graph.facebook.com >> C:\Windows\System32\drivers\etc\hosts
echo 127.0.0.1 platform.oculus.com >> C:\Windows\System32\drivers\etc\hosts
```

Anything the software still tries to reach now fails instantly with "connection refused", you will see those errors in its logs. This is intended.

#### 3c. Firewall: block every Oculus/Meta executable outbound

Block the exes themselves. Run this in an **elevated PowerShell** (adjust `$root` if your install path differs):

```powershell
$root = 'C:\Program Files\Oculus'
$created = 0
Get-ChildItem -Path $root -Recurse -Filter *.exe -File | ForEach-Object {
    $dn = 'OculusLockdown - ' + $_.FullName
    if (-not (Get-NetFirewallRule -DisplayName $dn -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $dn -Direction Outbound -Action Block -Program $_.FullName -Profile Any | Out-Null
    }
    $created++
}
Write-Host "$created outbound block rules in place"
```

**Verify the block:**

```powershell
reg query "HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config" /v PreventDashLaunch
reg query "HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config" /v CoreChannel
findstr /i "oculus facebook" C:\Windows\System32\drivers\etc\hosts
(Get-NetFirewallRule -DisplayName 'OculusLockdown*' -ErrorAction SilentlyContinue).Count
```

Six entries should be listed for hosts. Two of them are `facebook.com` domains, which is why the search includes "facebook".  
Firewall rules should print a nonzero number, one rule per .exe in the Oculus install folder (25 on the version this guide was tested with).

#### 3d. Kill the login-window app (Meta Horizon Link)

On every service start, the Oculus service tries to spawn the desktop login app "Meta Horizon Link" (`Client.exe`, ~180 MB under `Support\oculus-client\`). The runtime layer does not need it.

Elevated PowerShell (adjust the install path):

```powershell
Rename-Item -LiteralPath 'C:\Program Files\Oculus\Support\oculus-client\Client.exe' -NewName 'Client.exe.disabled'
```

After this, the service still *tries* to launch it once per start, fails instantly, and leaves a 0-byte log file (`%LOCALAPPDATA%\Oculus\Client_*.txt`). **Rollback:** rename `Client.exe.disabled` back to `Client.exe` (a future repair/reinstall of the Oculus software would also restore it; updates are disabled anyway, so it won't happen by itself).

---

### Step 4 - Make SteamVR the OpenXR runtime

OpenXR games pick a runtime from one registry value. Out of the box the Oculus installer points it at itself; point it at SteamVR instead.

**4a.** Find your SteamVR runtime file - normally:

```
C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\openvr_runtime.json
```

(If Steam lives elsewhere, search for `openvr_runtime.json` under your Steam folder. It ships with SteamVR - nothing to create.)

**4b.** Elevated command (adjust the path to match):

```bat
reg add "HKLM\SOFTWARE\Khronos\OpenXR\1" /v ActiveRuntime /t REG_SZ /d "C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\openvr_runtime.json" /f
```

**4c.** Also disable the Oculus runtime's 64-bit OpenXR entry (adjust the install path):

```bat
reg add "HKLM\SOFTWARE\Khronos\OpenXR\1\AvailableRuntimes" /v "C:\Program Files\Oculus\Support\oculus-runtime\oculus_openxr_64.json" /t REG_DWORD /d 0 /f
```

**4d.** Verify:

```bat
reg query "HKLM\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime"
reg query "HKLM\SOFTWARE\Khronos\OpenXR\1\AvailableRuntimes"
```

Expected: `ActiveRuntime` = your SteamVR path; the `oculus_openxr_64.json` entry = `0x0`.
(The 32-bit `WOW6432Node` view is left untouched. Modern games are 64-bit, and it has no effect.)

From now on: **OpenXR game → SteamVR → local Oculus runtime → Rift S.** No Meta server exists anywhere in that chain.

---

### Step 5 - Test

1. **Cables:** DisplayPort into the GPU, USB-A into USB 3.0 port. Recommended to use a rear motherboard port, not a front-panel hub. If you have a powered USB hub, it may work.
2. **Put the headset on.** LED language:
   - **White** = on and active
   - **Amber** = some type of issue
   - **Off** = unplugged or you're wearing it
3. **Controllers:** press each controller's buttons to wake them.
4. **Launch SteamVR.** Room setup is optional if you mostly play seated.
5. **Don headset.** The Oculus Dash should be skipped, and you should be directly into SteamVR environment. Head and controller tracking should work.

---

### TrackFix - automatic diagnosis and repair

`TrackFix.cmd` runs `TrackFix.ps1`, which checks the Rift S tracking pipeline and can repair common issues (repair asks for elevation via UAC). No install needed - just run it from this folder. Works on any Windows 10/11 machine following this guide.

**Usage:** double-click `TrackFix.cmd`. It prints a status report and a verdict. If the verdict says a software fix is possible, press **F** to repair (one UAC prompt), or Enter to quit.

**What repair does:**
- Bounces any bad-but-present Oculus USB devices
- If devices are "ghosts" (Windows reports them as not present, common after a reboot): power-cycles the USB root hub - a software replug, no cable touching
- Restarts the Oculus service and waits 30 s for devices to re-enumerate

**Verdict meanings:**

| Verdict | Meaning |
|---|---|
| all green | Tracking healthy, nothing to do |
| standby | Hardware fine, headset not worn - put it on and re-run |
| idle | Cameras asleep or dropped off USB - put the headset on (~30 s), re-run; press F if still stuck |
| ghost | Devices not on the bus - press F first (root-hub power-cycle); if that fails, replug into a rear USB 3 port |
| hardware | USB link failure - follow the physical steps it prints (direct rear USB 3 port) |
| service / problems | Oculus service stopped or recorded errors - press F to repair |

For anything TrackFix can't clear, see Troubleshooting below. Don't unplug the headset while SteamVR is running.

---

### Troubleshooting

Symptom → cause → fix. These were failures encountered during the process.

**`-3001` / "Unable to load LibOVRRT DLL" when starting VR**  
Cause: a process (or terminal) was started *before* the Oculus env vars (`OculusBase`, PATH) existed, so it has a stale environment.  
Fix: reboot once after installing, or close and relaunch the app/terminal fresh. Nothing is broken.

**A "Meta Horizon Link" login window appears on boot or service restart**  
Cause: stock behavior - the service spawns the login app (`Client.exe`) on every start.  
Fix: Step 3d renames the binary away; after that the window cannot appear.

**Display works, but view is frozen + amber LED = tracking dead**  
Run `TrackFix.cmd` first - it detects ghosts, sleep drops, and link failures automatically and can repair most of them. Don't trust SteamVR's status popup (it reports last-known state); trust whether head movement moves the view. If TrackFix can't clear it:

1. Camera privacy - re-check the Step 2 toggle, restart the Oculus service, retry.
2. Plug the USB-A directly into a rear motherboard USB 3 port - powered USB hubs are the most common cause of this (their SuperSpeed link dies while USB 2 audio keeps working, giving picture + sound with dead tracking). If you must use a hub: power-cycle its PSU (10 s), try other ports/cables.

**Controllers show "disconnected / inoperable"**  
They're asleep. Press the Oculus button. If still dead: run `TrackFix.cmd` - its repair restarts the Oculus service; wake them again after.

---

### Undo / restore

- **Hosts:** replace it with your backup:
  ```bat
  copy /y C:\Windows\System32\drivers\etc\hosts.oculus-backup C:\Windows\System32\drivers\etc\hosts
  ```
- **Firewall rules:**
  ```powershell
  Get-NetFirewallRule -DisplayName 'OculusLockdown*' | Remove-NetFirewallRule
  ```
- **Dash/updater registry values:**
  ```bat
  reg delete "HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config" /v PreventDashLaunch /f
  reg delete "HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config" /v CoreChannel /f
  ```
- **Login-window app:**
  ```powershell
  Rename-Item -LiteralPath 'C:\Program Files\Oculus\Support\oculus-client\Client.exe.disabled' -NewName 'Client.exe'
  ```
- **OpenXR back to Oculus runtime:**
  ```bat
  reg add "HKLM\SOFTWARE\Khronos\OpenXR\1" /v ActiveRuntime /t REG_SZ /d "C:\Program Files\Oculus\Support\oculus-runtime\oculus_openxr_64.json" /f
  reg add "HKLM\SOFTWARE\Khronos\OpenXR\1\AvailableRuntimes" /v "C:\Program Files\Oculus\Support\oculus-runtime\oculus_openxr_64.json" /t REG_DWORD /d 1 /f
  ```
  (adjust the install path; or delete the values entirely if you uninstall the Oculus software)

---

### Appendix

**Exact values applied by this guide**

**Registry**
```
HKLM\SOFTWARE\WOW6432Node\Oculus VR, LLC\Oculus\Config
    PreventDashLaunch = 0x1 (REG_DWORD)
    CoreChannel       = NO_UPDATES (REG_SZ)

HKLM\SOFTWARE\Khronos\OpenXR\1
    ActiveRuntime = <SteamVR>\bin\win64\openvr_runtime.json (REG_SZ)
    AvailableRuntimes\oculus_openxr_64.json = 0x0 (REG_DWORD)
```

**Hosts** (all → `127.0.0.1`): `graph.oculus.com`, `edge-mqtt.facebook.com`, `scontent.oculuscdn.com`, `securecdn.oculus.com`, `graph.facebook.com`, `platform.oculus.com`

**Firewall:** outbound block rule per `.exe` under the install folder, display name `OculusLockdown - <full path>`

**Login app:** `Support\oculus-client\Client.exe` → renamed `Client.exe.disabled` (service spawn then fails silently)

**`openvr_runtime.json`** (ships with SteamVR, shown for reference):
```json
{
   "file_format_version" : "1.0.0",
   "runtime" : {
      "library_path" : ".\\openxr_loader.dll",
      "library_path_win64" : ".\\openxr_loader.dll",
      "library_path_win32" : ".\\openxr_loader.dll"
   }
}
```

**Where logs live**

| What | Path |
|---|---|
| Oculus service log | `%LOCALAPPDATA%\Oculus\Service_*.txt` |
| Device/problem state | `%LOCALAPPDATA%\Oculus\DeviceCache.json` |
| Client crash logs (proof it exits when blocked) | `%LOCALAPPDATA%\Oculus\OculusClientError-*.txt` |
| SteamVR server log | `<Steam>\steamapps\common\SteamVR\logs\vrserver.txt` |
| Windows USB events | Event Viewer → Applications and Services Logs → Microsoft → Windows → USB-UCX / USBHUB3 |

**Tested environment**

| | |
|---|---|
| OS | Windows 11 Home, build 26300 |
| GPU | NVIDIA RTX 4080 SUPER (DisplayPort) |
| Headset | Rift S, firmware 2.2.0 |
| Oculus software | 1.115, driver 1.78.0.000004 |
| SteamVR | 2.17.10, registered as active OpenXR runtime |
