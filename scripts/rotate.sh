#!/usr/bin/env bash
# rotate.sh — MAC を付けかえる（sh 版）
#
#   ./scripts/rotate.sh                    付けかえ + 位置情報(IP)
#   ./scripts/rotate.sh --no-location      位置情報なし
#   ./scripts/rotate.sh --no-restart       設定だけ書く（link を落とさない）
#   ./scripts/rotate.sh --dry-run          何も変えずに表示だけ
#   ./scripts/rotate.sh --adapter wlan0    アダプタ名を指定
#
# 動く場所:
#   - Windows 付属の bash (Git Bash / MSYS2) と WSL → PowerShell 版 scripts/rotate.ps1 に丸投げ
#   - Linux → ip link（あれば macchanger）で付けかえ
#   - macOS → ifconfig で付けかえ
# どの場合も記録は同じ data/db.jsonl に同じ形で残す。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="$REPO/data/db.jsonl"

ADAPTER=""
NO_LOCATION=0
NO_RESTART=0
DRY=0

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --adapter)     ADAPTER="${2:-}"; shift 2 ;;
    --no-location) NO_LOCATION=1; shift ;;
    --no-restart)  NO_RESTART=1; shift ;;
    --dry-run|-n)  DRY=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# JSON 文字列用に " と \ を落とす（位置情報の地名などに使う）
clean() { printf '%s' "${1:-}" | tr -d '"\\' | tr -d '\n'; }

# 02:XX:XX:XX:XX:XX を作る（02 = ローカル管理ユニキャスト）
rand_mac() {
  local h
  if command -v od >/dev/null 2>&1; then
    h=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
  else
    h=$(printf '%02x%02x%02x%02x%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
  fi
  h=$(printf '%s' "$h" | tr 'A-F' 'a-f')
  printf '02:%s:%s:%s:%s:%s' \
    "${h:2:2}" "${h:4:2}" "${h:6:2}" "${h:8:2}" "${h:10:2}"
}

# ip-api.com からおおよその場所を取る（JSON の最小限の取り出し）
ip_location() {
  local raw v
  raw=$(curl -s --max-time 6 "http://ip-api.com/json/?fields=status,country,regionName,city,lat,lon,isp,query" 2>/dev/null) || return 1
  [ -n "$raw" ] || return 1

  if command -v node >/dev/null 2>&1; then
    v=$(printf '%s' "$raw" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        try{const j=JSON.parse(s);
          if(j.status!=="success"){process.exit(1);}
          console.log([j.lat,j.lon,j.city||"",j.regionName||"",j.country||"",j.isp||"",j.query||""].join("\t"));
        }catch(e){process.exit(1);}
      });' 2>/dev/null) || return 1
  elif command -v python3 >/dev/null 2>&1; then
    v=$(printf '%s' "$raw" | python3 -c '
import sys, json
j = json.load(sys.stdin)
if j.get("status") != "success": sys.exit(1)
print("\t".join(str(x) for x in [j.get("lat"), j.get("lon"), j.get("city",""), j.get("regionName",""), j.get("country",""), j.get("isp",""), j.get("query","")]))
' 2>/dev/null) || return 1
  else
    return 1
  fi

  [ -n "$v" ] || return 1
  IFS=$'\t' read -r lat lon city region country isp pubip <<< "$v"
  printf '{"source":"ip","gps":false,"lat":%s,"lon":%s,"city":"%s","region":"%s","country":"%s","isp":"%s","public_ip":"%s"}' \
    "$lat" "$lon" "$(clean "$city")" "$(clean "$region")" "$(clean "$country")" "$(clean "$isp")" "$(clean "$pubip")"
}

record() {
  local rec="$1"
  if [ "$DRY" -eq 1 ]; then
    say "DRY-RUN record: $rec"
    return
  fi
  mkdir -p "$(dirname "$DB")"
  printf '%s\n' "$rec" >> "$DB"
}

# ---------------------------------------------------------------- Windows
is_windows_bash() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  # WSL
  grep -qi microsoft /proc/version 2>/dev/null
}

to_win_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$p"; return; fi
  if command -v wslpath >/dev/null 2>&1; then wslpath -w "$p"; return; fi
  printf '%s' "$p"
}

delegate_to_powershell() {
  local ps1
  local -a args=(-NoProfile -ExecutionPolicy Bypass)
  local -a rest=()
  ps1="$(to_win_path "$REPO/scripts/rotate.ps1")"
  [ -n "$ADAPTER" ]        && rest+=(-AdapterName "$ADAPTER")
  [ "$NO_LOCATION" -eq 1 ] && rest+=(-NoLocation)
  [ "$NO_RESTART" -eq 1 ]  && rest+=(-NoRestart)
  [ "$DRY" -eq 1 ]         && rest+=(-DryRun)

  say "→ Windows なので PowerShell 版に丸投げします"
  powershell.exe "${args[@]}" -File "$ps1" "${rest[@]:-}"
}

if is_windows_bash; then
  delegate_to_powershell
  exit $?
fi

# ---------------------------------------------------------------- Linux / macOS
if [ -z "$ADAPTER" ]; then
  if command -v ip >/dev/null 2>&1; then
    ADAPTER=$(ip -o link show 2>/dev/null | awk -F': ' '$2 ~ /^wl/ {print $2; exit}')
  fi
  if [ -z "$ADAPTER" ] && command -v iwconfig >/dev/null 2>&1; then
    ADAPTER=$(iwconfig 2>/dev/null | awk '/802\.11/ {print $1; exit}')
  fi
  if [ -z "$ADAPTER" ] && [ "$(uname -s)" = "Darwin" ]; then
    ADAPTER=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
  fi
fi
[ -n "$ADAPTER" ] || die "Wi-Fi アダプタが見つかりません。--adapter で指定してください。"

MAC=$(rand_mac)
PRETTY=$(printf '%s' "$MAC" | tr ':' '-')

get_mac() {
  if [ -r "/sys/class/net/$ADAPTER/address" ]; then cat "/sys/class/net/$ADAPTER/address"; return; fi
  if command -v ip >/dev/null 2>&1; then
    ip link show dev "$ADAPTER" 2>/dev/null | awk '/link\/ether/ {print $2; exit}'; return
  fi
  ifconfig "$ADAPTER" 2>/dev/null | awk '/ether/ {print $2; exit}'
}

OLD=$(get_mac)

if [ "$DRY" -eq 1 ]; then
  say "DRY-RUN: ${OLD:-?} -> $MAC ($ADAPTER)"
  ok=true
else
  if [ "$(id -u)" -ne 0 ]; then
    say "ERROR: 管理者権限が必要です（sudo で実行してください）"
    ok=false
  else
    if [ "$NO_RESTART" -eq 0 ]; then
      if command -v ip >/dev/null 2>&1; then ip link set dev "$ADAPTER" down 2>/dev/null; fi
      if command -v ifconfig >/dev/null 2>&1 && [ "$(uname -s)" = "Darwin" ]; then ifconfig "$ADAPTER" down 2>/dev/null; fi
    fi

    if command -v macchanger >/dev/null 2>&1 && [ "$(uname -s)" != "Darwin" ]; then
      macchanger --mac="$MAC" "$ADAPTER" >/dev/null 2>&1 || true
    elif [ "$(uname -s)" = "Darwin" ]; then
      ifconfig "$ADAPTER" ether "$MAC" 2>/dev/null || true
    elif command -v ip >/dev/null 2>&1; then
      ip link set dev "$ADAPTER" address "$MAC" 2>/dev/null || true
    else
      ifconfig "$ADAPTER" hw ether "$MAC" 2>/dev/null || true
    fi

    if [ "$NO_RESTART" -eq 0 ]; then
      if command -v ip >/dev/null 2>&1; then ip link set dev "$ADAPTER" up 2>/dev/null; fi
      if command -v ifconfig >/dev/null 2>&1 && [ "$(uname -s)" = "Darwin" ]; then ifconfig "$ADAPTER" up 2>/dev/null; fi
      sleep 1
    fi

    APPLIED=$(get_mac)
    if [ -n "$APPLIED" ] && [ "$(printf '%s' "$APPLIED" | tr 'A-F' 'a-f')" = "$(printf '%s' "$MAC" | tr 'A-F' 'a-f')" ]; then
      ok=true
      say "MAC: ${OLD:-?} -> $APPLIED ($ADAPTER)"
    else
      ok=false
      say "MAC apply failed: 現在の値は ${APPLIED:-unknown} です"
    fi
  fi
fi

# --- 記録 ---
LOC=""
if [ "$NO_LOCATION" -eq 0 ]; then
  LOC=$(ip_location) || LOC=""
fi

rec="{\"t\":\"$(iso_now)\",\"cmd\":\"rotate\",\"mac\":\"$PRETTY\",\"ok\":$ok,\"adapter\":\"$ADAPTER\",\"os\":\"$(uname -s)\""
[ -n "$LOC" ] && rec="$rec,\"location\":$LOC"
[ "$DRY" -eq 1 ] && rec="$rec,\"dry_run\":true"
rec="$rec}"
record "$rec"

[ -n "$LOC" ] && say "LOC: $LOC"
[ "$ok" = true ] && exit 0 || exit 1
