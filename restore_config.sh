#!/usr/bin/env bash
# =============================================================================
# restore_config.sh — Restaura la configuración completa del ESP32 RTSP Mic
# Backup date: 2026-03-07  |  FW: v1.6.0-le.1
# Usage: bash restore_config.sh [IP]
# =============================================================================
set -euo pipefail

HOST="http://${1:-192.168.1.76}"
H="X-ESP32MIC-CSRF: 1"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; RST='\033[0m'

s() {  # s <key> <value> [description]
    local R
    R=$(curl -sf --max-time 10 -X POST -H "$H" "$HOST/api/set?key=$1&value=$2")
    if echo "$R" | grep -qF '"ok":true'; then
        echo -e "  ${GRN}OK${RST}  $1=${3:-$2}"
    else
        echo -e "  ${RED}FAIL${RST} $1=${3:-$2}  → $R"
    fi
}

check_online() {
    if ! curl -sf --max-time 8 "$HOST/api/status" > /dev/null 2>&1; then
        echo -e "${RED}Device not reachable at $HOST — abortando.${RST}"
        exit 1
    fi
    echo -e "${GRN}Device online: $HOST${RST}\n"
}

# --------------------------------------------------------------------------
check_online

echo -e "${CYN}=== Audio ===${RST}"
s rate          48000
s gain          1.2
s buffer        1024
s shift         12
s hp_enable     on
s hp_cutoff     500

echo -e "\n${CYN}=== CPU ===${RST}"
s cpu_freq      160

echo -e "\n${CYN}=== WiFi TX ===${RST}"
s wifi_tx       -2.0    "adaptive (Auto)"
sleep 3  # allow TX power change to settle

echo -e "\n${CYN}=== mDNS ===${RST}"
s mdns_enable   on

echo -e "\n${CYN}=== Time ===${RST}"
s time_sync     on
s time_offset   60      "UTC+1 (60 min)"

echo -e "\n${CYN}=== MQTT ===${RST}"
s mqtt_enable   on
s mqtt_host     192.168.1.55
s mqtt_port     1883
s mqtt_user     alejandro
s mqtt_topic    esp32mic
s mqtt_discovery homeassistant
s mqtt_interval 30
sleep 2  # allow MQTT reconnect

echo -e "\n${CYN}=== Stream Schedule ===${RST}"
s stream_sched      on
s stream_start_min  360     "06:00"
s stream_stop_min   1439    "23:59"

echo -e "\n${CYN}=== Deep Sleep ===${RST}"
s deep_sleep_sched  on      "wakes at stream start (06:00)"

echo -e "\n${CYN}=== Performance ===${RST}"
s auto_recovery     on
s thr_mode          auto
s check_interval    15
s sched_reset       off
s reset_hours       24

echo -e "\n${CYN}=== Thermal ===${RST}"
s oh_enable         on
s oh_limit          80

# --------------------------------------------------------------------------
echo -e "\n${YLW}IMPORTANTE: El MQTT password NO se restaura automáticamente.${RST}"
echo -e "${YLW}Introdúcelo manualmente en el Web UI: $HOST${RST}"
echo ""

# Verificación final
echo -e "${CYN}=== Verificación final ===${RST}"
STATUS=$(curl -sf --max-time 10 "$HOST/api/status")
python3 -c "
import sys, json
d = json.loads('$STATUS'.replace(\"'\", \"'\"))
" 2>/dev/null || STATUS=$(curl -sf --max-time 10 "$HOST/api/status")

echo "$STATUS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
checks = [
    ('wifi_tx_adaptive', True,    'WiFi TX adaptive'),
    ('mqtt_enabled',     True,    'MQTT enabled'),
    ('mdns_enabled',     True,    'mDNS enabled'),
    ('time_sync_enabled',True,    'Time sync'),
    ('stream_schedule_enabled', True, 'Stream schedule'),
    ('deep_sleep_sched_enabled', True, 'Deep sleep'),
    ('stream_schedule_start_min', 360,  'Stream start 06:00'),
    ('stream_schedule_stop_min',  1439, 'Stream stop 23:59'),
    ('time_offset_min',  60,      'Time offset UTC+1'),
]
ok = 0; fail = 0
for key, expected, label in checks:
    val = d.get(key)
    if val == expected:
        print(f'  \033[0;32mOK\033[0m  {label}: {val}')
        ok += 1
    else:
        print(f'  \033[0;31mFAIL\033[0m {label}: got {val!r}, expected {expected!r}')
        fail += 1
print()
if fail == 0:
    print('\033[0;32mConfiguración restaurada correctamente.\033[0m')
else:
    print(f'\033[0;31m{fail} campo(s) no coinciden — revisa manualmente.\033[0m')
"
