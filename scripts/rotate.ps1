# rotate.ps1 — Wi-Fi MAC を付けかえる本体（レジストリ方式 / Intel AC 8265 などで必要）— 管理者で実行
#
#   .\rotate.ps1                        MAC付けかえ + 位置情報
#   .\rotate.ps1 -NoLocation            位置情報なし（オフライン/高速）
#   .\rotate.ps1 -GpsOnly               GPS(Satellite)が取れたときだけ記録
#   .\rotate.ps1 -NoRestart             レジストリに書くだけ（アダプタ再起動しない = 旧 rotate-registry.ps1）
#   .\rotate.ps1 -DryRun                何も書きかえずに、やることだけ表示
#   .\rotate.ps1 -AdapterName "Wi-Fi 2" アダプタ名を指定
#
# 旧 rotate-registry.ps1 はこの -NoRestart に統合しました。
param(
    [string]$AdapterName = "Wi-Fi",
    [switch]$NoLocation,
    [switch]$GpsOnly,
    [switch]$NoRestart,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$here   = $PSScriptRoot                 # <repo>/scripts
$root   = Split-Path $here -Parent      # <repo>
$dbPath = Join-Path $root "data\db.jsonl"

function Write-Record($record) {
    if ($DryRun) { Write-Output ("DRY-RUN record: " + ($record | ConvertTo-Json -Compress -Depth 5)); return }
    New-Item -ItemType Directory -Force -Path (Split-Path $dbPath) | Out-Null
    ($record | ConvertTo-Json -Compress -Depth 5) | Out-File -Append -Encoding utf8 $dbPath
}

# --- 1. 位置情報（GPS優先 → Wi-Fi測位 → IP）---
$location = $null
if (-not $NoLocation) {
    try {
        . (Join-Path $here "location.ps1")
        $location = if ($GpsOnly) { Get-LocationInfo -GpsOnly } else { Get-LocationInfo }
    } catch {
        Write-Output "location failed: $($_.Exception.Message)"
    }
}

# --- 2. アダプタのレジストリ棚を探す ---
$base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
try {
    $adapter = Get-NetAdapter -Name $AdapterName -Physical
} catch {
    Write-Output "ERROR: adapter '$AdapterName' not found.  Get-NetAdapter で名前を確認してください。"
    exit 2
}

$key = Get-ChildItem $base -ErrorAction SilentlyContinue |
    Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).NetCfgInstanceId -eq $adapter.InterfaceGuid } |
    Select-Object -First 1 -ExpandProperty PSPath

if (-not $key) {
    Write-Output "ERROR: registry key for adapter '$AdapterName' not found (管理者権限が必要かもしれません)"
    exit 2
}

# --- 3. ローカル管理ユニキャスト MAC を生成 (02:xx:xx:xx:xx:xx) ---
$mac    = "02" + (-join (1..5 | ForEach-Object { (Get-Random -Maximum 256).ToString("X2") }))
$pretty = ($mac -split '(..)' | Where-Object { $_ }) -join '-'
$old    = (Get-ItemProperty $key).NetworkAddress

if ($DryRun) {
    Write-Output "DRY-RUN: $old -> $pretty  (key: $key)"
} else {
    Set-ItemProperty -Path $key -Name NetworkAddress -Value $mac
}

# --- 4. 適用（アダプタをオフ→オンして読み直させる）---
$ok = $false
if ($NoRestart) {
    # レジストリに書いただけ。-NoRestart では「反映されたか」は判定できないので ok は書いたこと自体
    $ok = -not $DryRun
    Write-Output "MAC: $old -> $pretty (registry only / -NoRestart)"
} elseif ($DryRun) {
    Write-Output "DRY-RUN: adapter '$AdapterName' をオフ→オンする予定（実行していません）"
    $ok = $true
} else {
    try {
        netsh interface set interface name="$AdapterName" admin=disable | Out-Null
        Start-Sleep -Milliseconds 800
        netsh interface set interface name="$AdapterName" admin=enable  | Out-Null
        Start-Sleep -Milliseconds 800
        $applied = (Get-NetAdapter -Name $AdapterName).MacAddress
        $ok = ($applied -replace '[:-]', '').ToLower() -eq $mac.ToLower()
        Write-Output "MAC: $old -> $applied"
        if (-not $ok) { Write-Output "WARNING: adapter still reports old MAC (再起動やドライバ依存)" }
    } catch {
        Write-Output "MAC apply failed: $($_.Exception.Message)"
    }
}

# --- 5. 記録（成功も失敗も残す = 安全装置）---
$rec = [ordered]@{
    t       = (Get-Date).ToString("o")
    cmd     = "rotate"
    mac     = $pretty
    ok      = $ok
    adapter = $AdapterName
    dry_run = [bool]$DryRun
}
if ($location) {
    $rec.location = [ordered]@{
        source     = $location.source
        gps        = $location.gps
        lat        = $location.lat
        lon        = $location.lon
        accuracy_m = $location.accuracy_m
        city       = $location.city
        region     = $location.region
        country    = $location.country
        isp        = $location.isp
        public_ip  = $location.public_ip
    }
}
Write-Record $rec

if ($location) {
    $tag = if ($location.gps) { "GPS" } else { $location.source }
    Write-Output ("LOC: {0} ({1} / {2}m) {3}, {4}" -f $location.lat, $location.lon, $location.accuracy_m, $location.city, $tag)
}
if (-not $location -and -not $NoLocation) { Write-Output "LOC: 取得できませんでした" }

if ($ok) { exit 0 } else { exit 1 }
