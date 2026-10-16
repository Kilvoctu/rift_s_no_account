param(
    [switch]$Fix,
    [switch]$NoPause,
    [Parameter(Position = 0)][string]$Command
)

$ErrorActionPreference = 'SilentlyContinue'
if ($Command -ieq 'fix') { $Fix = $true }

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedFix {
    Write-Host 'Requesting elevation (UAC prompt)...' -ForegroundColor Yellow
    try {
        Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Fix' -Wait
    } catch {
        Write-Host 'Elevation cancelled or failed.' -ForegroundColor Red
    }
}

if ($Fix -and -not (Test-IsAdmin)) { Invoke-ElevatedFix; exit 0 }

function Get-LogInfo {
    $log = Get-ChildItem "$env:LOCALAPPDATA\Oculus\Service_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $log) { return $null }
    $raw = Get-Content $log.FullName -Raw
    $f = [regex]::Matches($raw, 'valid_frames=(\d+)')
    $p = [regex]::Matches($raw, 'is_proximity_active=(\d+)')
    [pscustomobject]@{
        Time      = $log.LastWriteTime
        Frames    = if ($f.Count) { [int]$f[$f.Count - 1].Groups[1].Value } else { -1 }
        Proximity = if ($p.Count) { [int]$p[$p.Count - 1].Groups[1].Value } else { -1 }
    }
}

function Test-DeviceNotPresent($dev) {
    $p = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_IsPresent' -ErrorAction SilentlyContinue
    return [bool]($p -and $p.Data -eq $false)
}

function Get-OculusRootHub {
    $first = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like '*VID_2833*' } | Select-Object -First 1
    if (-not $first) { return $null }
    $cur = $first.InstanceId
    for ($i = 0; $i -lt 8; $i++) {
        $p = Get-PnpDeviceProperty -InstanceId $cur -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue
        if (-not $p -or -not $p.Data) { break }
        $cur = $p.Data
        if ($cur -like 'USB\ROOT_*') { return (Get-PnpDevice -InstanceId $cur -ErrorAction SilentlyContinue) }
    }
    return $null
}

function Get-State {
    $oc = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like '*VID_2833*' })
    $usbErr = @(Get-PnpDevice -Status Error -ErrorAction SilentlyContinue | Where-Object { $_.Class -eq 'USB' })
    $svc = Get-Service OVRService -ErrorAction SilentlyContinue
    $hs = $null
    $ctrl = @()
    $probErr = @()
    if (Test-Path "$env:LOCALAPPDATA\Oculus\DeviceCache.json") {
        $dc = Get-Content "$env:LOCALAPPDATA\Oculus\DeviceCache.json" -Raw | ConvertFrom-Json
        $hs = $dc.devices | Where-Object { $_.type -eq 'headset' } | Select-Object -First 1
        $ctrl = @($dc.devices | Where-Object { $_.type -eq 'controller' })
        if ($hs -and $hs.problems) { $probErr = @($hs.problems | ForEach-Object { $_.error }) }
    }
    $ghosts = @($oc | Where-Object { $_.Status -ne 'OK' -and (Test-DeviceNotPresent $_) })
    [pscustomobject]@{
        Oculus        = $oc
        UsbErrors     = $usbErr
        Service       = $svc
        Headset       = $hs
        Controllers   = $ctrl
        ProblemErrors = $probErr
        Ghosts        = $ghosts
        Log           = Get-LogInfo
        SteamVR       = [bool](Get-Process vrserver -ErrorAction SilentlyContinue)
    }
}

function Show-Steps {
    Write-Host ''
    Write-Host 'PHYSICAL STEPS (in order):' -ForegroundColor Yellow
    Write-Host '  1. Close SteamVR.'
    Write-Host '  2. Plug the Rift S USB DIRECTLY into a rear motherboard USB 3 port (bypass any hub/extension).'
    Write-Host '  3. If you must use the powered hub: unplug its power adapter 10 s, plug it back, try another port/cable.'
    Write-Host '  4. At the end of this report press F to repair (bounces stuck devices + Oculus service, one UAC).'
    Write-Host '  5. Put the headset ON - cameras stay asleep while idle (amber/off LED).'
    Write-Host '  6. Launch SteamVR; press the Oculus button on each controller to wake them.'
    Write-Host ''
    Write-Host 'Do not unplug the headset while SteamVR is running - hot-unplug can crash vrserver.' -ForegroundColor DarkYellow
}

function Show-Report($s) {
    Write-Host ''
    Write-Host '== Rift S status ==' -ForegroundColor Cyan
    $svcTxt = if ($s.Service -and $s.Service.Status -eq 'Running') { 'Running' } else { 'NOT RUNNING' }
    Write-Host ('OVRService     : ' + $svcTxt)
    $bad = @($s.Oculus | Where-Object { $_.Status -ne 'OK' })
    $ok = @($s.Oculus | Where-Object { $_.Status -eq 'OK' })
    Write-Host ('USB devices    : ' + $ok.Count + ' OK, ' + $bad.Count + ' bad')
    foreach ($b in $bad) {
        $tag = if (Test-DeviceNotPresent $b) { '  [NOT PRESENT - ghost]' } else { '' }
        Write-Host ('   BAD: ' + $b.Status + '  ' + $b.FriendlyName + $tag) -ForegroundColor Red
    }
    if ($s.UsbErrors.Count) {
        $ghost = if ($bad.Count -eq 0) { ' (leftover ghost - harmless while Oculus devices are OK)' } else { '' }
        foreach ($e in $s.UsbErrors) { Write-Host ('   PORT ERROR: ' + $e.FriendlyName + $ghost) -ForegroundColor Yellow }
    }
    if ($s.ProblemErrors.Count) { Write-Host ('Headset problem: ' + ($s.ProblemErrors -join ', ')) -ForegroundColor Red }
    if ($s.Headset) {
        Write-Host ('Headset        : conn=' + $s.Headset.connectionState + '  oper=' + $s.Headset.operationalState + '  problems=' + $s.Headset.problems.Count)
    }
    foreach ($c in $s.Controllers) {
        if ($c.subtype -notin 'rlcon', 'llcon') { continue }
        $cc = if ($c.connectionState -eq 'connected') { 'connected' } else { 'asleep/disconnected' }
        Write-Host ('Controller     : ' + $c.subtype + '  ' + $cc)
    }
    if ($s.Log) {
        $fr = if ($s.Log.Frames -lt 0) { 'no telemetry yet' } elseif ($s.Log.Frames -gt 0) { "$($s.Log.Frames) /min - STREAMING" } else { '0 /min - idle' }
        Write-Host ('Camera frames  : ' + $fr)
        $px = if ($s.Log.Proximity -eq 1) { 'worn/active' } else { 'not worn (up to ~1 min lag)' }
        Write-Host ('Proximity      : ' + $px)
        Write-Host ('Log updated    : ' + $s.Log.Time.ToString('HH:mm:ss'))
    }
    Write-Host ('SteamVR        : ' + $(if ($s.SteamVR) { 'running' } else { 'closed' }))
}

function Show-Verdict($s) {
    $badOc = @($s.Oculus | Where-Object { $_.Status -ne 'OK' })
    $badHub = @($badOc | Where-Object { $_.FriendlyName -like '*USB Hub*' })
    $linkFail = ($badOc.Count -gt 0) -and (($s.ProblemErrors -contains 'badUSBPort') -or $badHub.Count -gt 0)
    Write-Host ''
    Write-Host '== Verdict ==' -ForegroundColor Cyan
    if ($linkFail) {
        if ($s.Ghosts.Count -gt 0) {
            Write-Host ('Camera/hub branch is NOT on the USB bus - ' + $s.Ghosts.Count + ' device(s) report not-present (ghosts).') -ForegroundColor Red
            Write-Host 'Windows kept only phantom entries; service restarts cannot fix this.'
            Write-Host ''
            Write-Host 'PRESS F FIRST: repair will power-cycle the USB root hub (software replug - no cable touching).' -ForegroundColor Yellow
            Write-Host 'If that does not bring it back: close SteamVR, then physically replug the USB-A into a rear motherboard USB 3 port.'
            return 'ghost'
        }
        Write-Host 'USB/link failure - the headset hub or its port is down.' -ForegroundColor Red
        if ($s.ProblemErrors -contains 'badUSBPort') {
            Write-Host 'Oculus reports badUSBPort (-4003) = port/link problem, not software.' -ForegroundColor Red
        }
        Show-Steps
        return 'hardware'
    }
    if ($badOc.Count -gt 0) {
        Write-Host 'Tracking cameras dropped off USB - usually just the headset going to sleep.' -ForegroundColor Yellow
        Write-Host 'Put the headset ON (~30 s) and run TrackFix again.'
        Write-Host 'Still bad after that: press F to repair, then replug it (rear USB 3 port).'
        return 'idle'
    }
    if (-not $s.Service -or $s.Service.Status -ne 'Running') {
        Write-Host 'Oculus service is stopped - repair can fix this.' -ForegroundColor Yellow
        return 'service'
    }
    if ($s.ProblemErrors.Count -gt 0) {
        Write-Host ('Service recorded problems (' + ($s.ProblemErrors -join ',') + ') - repair can clear this.') -ForegroundColor Yellow
        return 'problems'
    }
    if ($s.Log -and $s.Log.Frames -eq 0) {
        if ($s.Log.Proximity -eq 0) {
            Write-Host 'Hardware OK. Cameras asleep because the headset is not worn.' -ForegroundColor Yellow
            Write-Host 'Put the headset on, wait ~60 s, run TrackFix again.' -ForegroundColor Yellow
            return 'standby'
        }
        Write-Host 'Headset worn but cameras not streaming - close SteamVR, then repair.' -ForegroundColor Yellow
        return 'idle'
    }
    if ($s.Log -and $s.Log.Frames -lt 0) {
        Write-Host 'No camera telemetry yet - service may have just started, wait ~60 s and re-run.' -ForegroundColor Yellow
        return 'unknown'
    }
    Write-Host 'ALL GREEN - tracking pipeline is healthy.' -ForegroundColor Green
    if (@($s.Controllers | Where-Object { $_.connectionState -ne 'connected' }).Count) {
        Write-Host 'Controllers disconnected = just asleep: press their Oculus button to wake.' -ForegroundColor DarkYellow
    }
    return 'ok'
}

if ($Fix) {
    Write-Host ''
    Write-Host '== Repair mode ==' -ForegroundColor Cyan
    if (Get-Process vrserver -ErrorAction SilentlyContinue) {
        Write-Host 'SteamVR is RUNNING - close it first for a clean repair.' -ForegroundColor Yellow
    }
    $st = Get-State
    $bad = @($st.Oculus | Where-Object { $_.Status -ne 'OK' })
    $ghosts = @($bad | Where-Object { Test-DeviceNotPresent $_ })
    $present = @($bad | Where-Object { -not (Test-DeviceNotPresent $_) })
    foreach ($b in $present) {
        Write-Host ('Bouncing device: ' + $b.FriendlyName)
        Start-Process pnputil -ArgumentList '/restart-device', "`"$($b.InstanceId)`"" -Wait -WindowStyle Hidden
    }
    if (-not $present.Count -and -not $ghosts.Count) { Write-Host 'All Oculus USB devices OK - no device bounce needed.' }
    if ($ghosts.Count) {
        Write-Host ('Ghosts detected (' + $ghosts.Count + ' not-present device(s)) - software replug of the root hub.')
        $hub = Get-OculusRootHub
        if ($hub) {
            Write-Host ('Power-cycling: ' + $hub.FriendlyName)
            Write-Host '  (all USB 3 devices on this controller will blink for a few seconds)'
            Disable-PnpDevice -InstanceId $hub.InstanceId -Confirm:$false -ErrorAction Continue
            Start-Sleep -Seconds 3
            Enable-PnpDevice -InstanceId $hub.InstanceId -Confirm:$false -ErrorAction Continue
            Start-Sleep -Seconds 5
            Write-Host 'Root hub re-enabled - devices re-enumerating.'
        } else {
            Write-Host 'Could not resolve the USB root hub - physical replug required.' -ForegroundColor Red
        }
    }
    Write-Host 'Restarting OVRService...'
    Restart-Service OVRService -Force
    Write-Host 'Waiting 30 s for re-enumeration...'
    Start-Sleep -Seconds 30
}

$state = Get-State
Show-Report $state
$level = Show-Verdict $state

if ($NoPause) { exit 0 }
if ($Fix) {
    Read-Host "`nRepair finished. Press Enter to close"
    exit 0
}
if ($level -in 'service', 'problems', 'hardware', 'ghost', 'idle') {
    $ans = Read-Host 'Press F to attempt repair now (UAC), or Enter to quit'
    if ($ans -ieq 'f') { Invoke-ElevatedFix }
} else {
    Read-Host 'Press Enter to close'
}
