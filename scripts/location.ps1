# location.ps1 — 現在地取得（GPS 優先 → WiFi/携帯/セルフ位置測位 → IP）
#
#   . .\location.ps1                 # dot-source して使う
#   $loc = Get-LocationInfo          # GPS 優先、だめなら WiFi→IP にフォールバック
#   $loc = Get-LocationInfo -GpsOnly # GPS が取れなければ $null
#   .\location.ps1                   # 直接実行 = JSON を1行表示
#
# Windows 位置情報の PositionSource は Satellite / WiFi / Cellular / IPAddress / Unknown。
# Satellite のときだけ gps = $true になる（GPS レシーバ非搭載機では WiFi になる）。

$script:LocPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }

# PowerShell 7 (.NET Core) では WinRT の AsTask 連携が取れないことが多い。
# その場合は powershell.exe (5.1) に Windows 位置情報だけ取りに行く。
function Get-WindowsLocationViaPS51 {
    param([int]$TimeoutMs = 8000)
    if (-not $script:LocPath) { return $null }
    $exe = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $exe) { return $null }
    try {
        $out = & $exe.Source -NoProfile -ExecutionPolicy Bypass -File $script:LocPath -WindowsOnly 2>$null
        if (-not $out) { return $null }
        $o = ($out | Select-Object -Last 1) | ConvertFrom-Json
        if (-not $o -or -not $o.src) { return $null }
        return [ordered]@{
            source     = $o.src
            gps        = ($o.src -eq 'gps')
            lat        = [double]$o.lat
            lon        = [double]$o.lon
            accuracy_m = if ($null -ne $o.acc) { [double]$o.acc } else { $null }
            altitude_m = if ($null -ne $o.alt) { [double]$o.alt } else { $null }
            speed_mps  = if ($null -ne $o.spd) { [double]$o.spd } else { $null }
        }
    } catch {
        return $null
    }
}

function Get-WindowsLocation {
    param(
        [int]$TimeoutMs = 8000,
        [int]$AccuracyMeters = 1     # 1m を要求 = GPS を優先させる
    )

    # PowerShell 7 では WinRT が使えないので 5.1 に任せる
    if ($PSVersionTable.PSEdition -eq 'Core') {
        return Get-WindowsLocationViaPS51 -TimeoutMs $TimeoutMs
    }

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        [Windows.Devices.Geolocation.Geolocator, Windows.Devices.Geolocation, ContentType = WindowsRuntime] | Out-Null
        [Windows.Devices.Geolocation.GeolocationAccessStatus, Windows.Devices.Geolocation, ContentType = WindowsRuntime] | Out-Null

        $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } | Select-Object -First 1
        if (-not $asTask) { throw "AsTask helper not found" }

        function _Await($op, $type, $ms) {
            $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
            if (-not $t.Wait($ms)) { throw "geolocation timeout (${ms}ms)" }
            $t.Result
        }

        $access = _Await ([Windows.Devices.Geolocation.Geolocator]::RequestAccessAsync()) `
                         ([Windows.Devices.Geolocation.GeolocationAccessStatus]) $TimeoutMs
        if ("$access" -ne "Allowed") { throw "geolocation access: $access" }

        $g = New-Object Windows.Devices.Geolocation.Geolocator
        $g.DesiredAccuracyInMeters = $AccuracyMeters
        $g.ReportInterval = 0

        $pos = _Await ($g.GetGeopositionAsync()) ([Windows.Devices.Geolocation.Geoposition]) $TimeoutMs
        $c = $pos.Coordinate
        $p = $c.Point.Position

        $psrc = "$($c.PositionSource)"
        $source = switch -Regex ($psrc) {
            'Satellite' { 'gps' }
            'WiFi'      { 'wifi' }
            'Cellular'  { 'cellular' }
            'IPAddress' { 'ip' }
            default     { 'windows' }
        }

        return [ordered]@{
            source     = $source
            gps        = ($source -eq 'gps')
            lat        = [math]::Round($p.Latitude, 7)
            lon        = [math]::Round($p.Longitude, 7)
            accuracy_m = $c.Accuracy
            altitude_m = if ([double]::IsNaN($p.Altitude)) { $null } else { [math]::Round($p.Altitude, 1) }
            speed_mps  = if ([double]::IsNaN($c.Speed)) { $null } else { [math]::Round($c.Speed, 2) }
        }
    } catch {
        return $null
    }
}

function Get-IpLocation {
    param([int]$TimeoutSec = 8)
    try {
        $r = Invoke-RestMethod -Uri "http://ip-api.com/json/?fields=status,country,regionName,city,lat,lon,isp,query" `
             -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($r.status -ne "success") { return $null }
        return [ordered]@{
            source     = 'ip'
            gps        = $false
            lat        = $r.lat
            lon        = $r.lon
            accuracy_m = $null
            city       = $r.city
            region     = $r.regionName
            country    = $r.country
            isp        = $r.isp
            public_ip  = $r.query
        }
    } catch {
        return $null
    }
}

function Get-LocationInfo {
    param(
        [int]$TimeoutSec = 8,
        [switch]$IpOnly,
        [switch]$GpsOnly     # GPS(Satellite) 以外は捨てる
    )

    $out = [ordered]@{
        source     = $null
        gps        = $false
        lat        = $null
        lon        = $null
        accuracy_m = $null
        altitude_m = $null
        speed_mps  = $null
        city       = $null
        region     = $null
        country    = $null
        isp        = $null
        public_ip  = $null
        at         = (Get-Date).ToString("o")
    }

    $win = if ($IpOnly) { $null } else { Get-WindowsLocation }
    if ($null -eq $win -and $GpsOnly) { return $null }

    $ip = Get-IpLocation -TimeoutSec $TimeoutSec

    # 座標は Windows(測位) を優先、地名/ISP/公IP は IP から補完
    foreach ($src in @($win, $ip)) {
        if (-not $src) { continue }
        foreach ($k in $src.Keys) {
            $v = $src[$k]
            if ($null -ne $v -and ($null -eq $out[$k] -or $out[$k] -eq $false)) { $out[$k] = $v }
        }
    }

    if ($GpsOnly -and -not $out.gps) { return $null }
    if ($null -eq $out.lat -and $null -eq $out.city) { return $null }
    return $out
}

# 直接実行したときだけ表示
if ($MyInvocation.InvocationName -ne '.') {
    # PowerShell 5.1 の子プロセスとして呼ばれたとき（pwsh からの委譲先）
    if ($args -contains '-WindowsOnly') {
        $w = Get-WindowsLocation
        if ($w) {
            [ordered]@{ src = $w.source; lat = $w.lat; lon = $w.lon; acc = $w.accuracy_m; alt = $w.altitude_m; spd = $w.speed_mps } |
                ConvertTo-Json -Compress
        } else {
            '{}'
        }
    } else {
        $loc = Get-LocationInfo
        if ($loc) { $loc | ConvertTo-Json -Compress } else { '{"error":"location unavailable"}' }
    }
}
