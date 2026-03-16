# ESP32 RTSP Mic for BirdNET-Go — Contexto para Claude

## Descripción del Proyecto

Firmware Arduino para **Seeed XIAO ESP32-C6** que captura audio I2S (ICS-43434) y transmite RTSP mono 16-bit PCM para BirdNET-Go. Versión actual: **v1.6.0-lp**.

---

## Archivos Clave

| Archivo | Rol |
|---------|-----|
| `esp32_rtsp_mic_birdnetgo/esp32_rtsp_mic_birdnetgo.ino` | Sketch principal, globals, loop |
| `esp32_rtsp_mic_birdnetgo/WebUI.cpp` | HTTP server, JSON API, manejo de settings |
| `esp32_rtsp_mic_birdnetgo/WebUI.h` | Interfaz pública del módulo WebUI |
| `esp32_rtsp_mic_birdnetgo/WebUI_gz.h` | HTML gzipeado embebido como array C (generado) |
| `esp32_rtsp_mic_birdnetgo/webui/index_v2.html` | Fuente del Web UI (compilar con script) |
| `esp32_rtsp_mic_birdnetgo/tools/gen_webui_gzip_header.sh` | Genera `WebUI_gz.h` desde `index_v2.html` |

---

## Arquitectura

- **Persistencia:** `Preferences` (NVS flash)
- **CSRF:** mutaciones HTTP requieren header `X-ESP32MIC-CSRF: 1` + método POST
- **MQTT:** `PubSubClient`, Home Assistant Discovery, telemetría periódica + eventos
- **Deep sleep:** `RTC_DATA_ATTR` para datos que sobreviven al deep sleep
- **OTA:** `ArduinoOTA`, hostname `esp32mic.local`
- **Código OTA-safe:** NUNCA introducir bloqueos ni delays largos en el loop

### Gotcha C++ importante
`extern const int ADAPT_TX_STEPS_COUNT = ...` en el `.ino` es correcto e intencional.
`const` a nivel de namespace tiene linkage interno en C++; `extern` en la definición es el único modo de dar linkage externo para que `WebUI.cpp` lo enlace. **NO quitar el `extern`.**

---

## Build & Deploy OTA

### FQBN exacto
```
esp32:esp32:XIAO_ESP32C6:UploadSpeed=921600,CDCOnBoot=cdc,CPUFreq=160,FlashFreq=80,FlashMode=qio,FlashSize=4M,PartitionScheme=default,DebugLevel=none,EraseFlash=none,JTAGAdapter=default,ZigbeeMode=default
```

> **IMPORTANTE:** Usar board `XIAO_ESP32C6`, NO el genérico `esp32c6` — produce binarios ~24KB más grandes.

### Partición
`default` (1.2MB APP / 1.5MB SPIFFS) — binario resultante ~1,294,266 bytes (98% de 1,310,720).

### Datos del dispositivo
| Dato | Valor |
|------|-------|
| Device IP | `192.168.1.76` |
| Host IP | `192.168.1.36` |
| OTA password | `1234` |
| OTA port | `3232` |

### Herramientas
- **arduino-cli:** symlink en `/tmp/arduino-cli` → `/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli`
- **espota.py:** `/Volumes/Alejandro SSD/alejandro/Library/Arduino15/packages/esp32/hardware/esp32/3.3.7/tools/espota.py`
- **Librerías:** `/Users/alejandro/Documents/Arduino/libraries` (PubSubClient 2.8 instalada)

### Crear script OTA (si `/tmp/compile_ota.sh` no existe)
```bash
cat > /tmp/compile_ota.sh << 'EOF'
#!/bin/bash
set -e
SKETCH="/Volumes/Alejandro SSD/alejandro/Documents/Arduino/birdnetgo-esp32-rtsp-mic/esp32_rtsp_mic_birdnetgo/esp32_rtsp_mic_birdnetgo.ino"
FQBN="esp32:esp32:XIAO_ESP32C6:UploadSpeed=921600,CDCOnBoot=cdc,CPUFreq=160,FlashFreq=80,FlashMode=qio,FlashSize=4M,PartitionScheme=default,DebugLevel=none,EraseFlash=none,JTAGAdapter=default,ZigbeeMode=default"
DEVICE_IP="192.168.1.76"; OTA_PASSWORD="1234"
ARDUINO_CLI="/tmp/arduino-cli"
ESPOTA="/Volumes/Alejandro SSD/alejandro/Library/Arduino15/packages/esp32/hardware/esp32/3.3.7/tools/espota.py"
LIB_DIR="/Users/alejandro/Documents/Arduino/libraries"; BUILD_DIR="/tmp/arduino_build"
echo "=== Compilando ===" && "$ARDUINO_CLI" compile --fqbn "$FQBN" --libraries "$LIB_DIR" --build-path "$BUILD_DIR" "$SKETCH"
echo "=== Subiendo via OTA ===" && python3 "$ESPOTA" -i "$DEVICE_IP" -p 3232 -a "$OTA_PASSWORD" -f "$BUILD_DIR/esp32_rtsp_mic_birdnetgo.ino.bin"
echo "=== DONE ==="
EOF
chmod +x /tmp/compile_ota.sh
```

### Symlink arduino-cli (si no existe)
```bash
ln -s "/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli" /tmp/arduino-cli
```

### Antes de subir OTA (si está streaming)
```bash
curl -X POST http://192.168.1.76/api/action/server_stop -H "X-ESP32MIC-CSRF: 1"
```

---

## Preferencias de Trabajo

- Cambios por pasos, validar como CodeRabbit antes de implementar
- Logging en Web UI + MQTT para todos los cambios de estado relevantes
- Código OTA-safe: sin bloqueos, sin delays largos en loop
- Respuestas concisas, en español

---

## Feature: Low Power (rama `feature/low-power` / `feature/v1.6.0-lp`)

### Feature 1 — Adaptive WiFi TX Power (IMPLEMENTADO v1.6.0-le.1)

Reduce gradualmente la potencia TX WiFi hasta el mínimo que garantice streaming estable.

- Pasos: 5, 7, 8.5, 11, 13, 15, 17, 18.5 dBm
- RSSI medido cada 30s (promedio)
- **Zona excelente** (RSSI > -65 dBm): baja 1 paso cada 2 min
- **Zona confort** (-65 a -78 dBm): mantiene nivel actual
- **Zona peligro** (RSSI < -78 dBm): sube a 18.5 dBm inmediatamente
- Boot: siempre arranca desde 18.5 dBm
- Wake from deep sleep: usa `wifiLastGoodDbm` (NVS) como punto de partida
- NVS keys: `wifiAdaptTx` (bool), `wifiLastGoodDbm` (float)
- RTC: `rtcAdaptTxLastGoodDbm`, `rtcAdaptTxValid`
- Sentinel `-2.0` en API `wifi_tx` activa adaptive; valor numérico lo desactiva
- MQTT Discovery: `binary_sensor wifi_tx_adaptive`, `sensor wifi_tx_dbm`

### Feature 2 — RTSP Server OFF Idle Mode (IMPLEMENTADO v1.6.0-le.0)

Cuando RTSP está desactivado, minimiza consumo manteniendo WiFi para control remoto.

**Al APAGAR servidor RTSP:**
1. `i2s_driver_uninstall`
2. `setCpuFrequencyMhz(80)`
3. `WiFi.setSleep(WIFI_PS_MIN_MODEM)`

**Al REACTIVAR servidor RTSP:**
1. `WiFi.setSleep(WIFI_PS_NONE)`
2. Restaurar CPU a frecuencia configurada
3. Reinicializar I2S

> `WIFI_PS_MIN_MODEM` preferido sobre `WIFI_PS_MAX_MODEM`: mantiene Web UI y MQTT funcionales.

### Bugs corregidos (CodeRabbit review, v1.6.0-le.1 commit 2216e92)

1. `ADAPT_TX_STEPS_COUNT` necesita `extern const` — linkage interno por defecto en C++
2. `httpThermalClear()` crash: faltaba `exitIdleMode()` antes de reactivar RTSP
3. `httpThermalClear()` no publicaba MQTT al limpiar latch térmico
4. `adaptTxStepIdx = 7` hardcodeado → reemplazado por `ADAPT_TX_STEPS_COUNT - 1`
5. `exitIdleMode()` memory leak ~9KB: no liberaba buffers antes de malloc
6. `resetToDefaultSettings()` no reseteaba `timeSyncEnabled`, `adaptTxStepIdx`, etc.
7. `WiFi.setSleep(false)` antes de `wm.autoConnect()` — WiFiManager lo resetea internamente

---

## Deep Sleep Power Bug (150-200 mW con USB) — FIX PENDIENTE DE VALIDAR

### Síntoma
Device en deep sleep muestra 150-200 mW en medidor USB (debería ser 0 mW).

### Root cause
`WiFi.setSleep(false)` incondicional en `setup()` pone WiFi en `WIFI_PS_NONE`.
En ESP32-C6 (IDF5): entrar en deep sleep desde `WIFI_PS_NONE` deja el USB-JTAG PHY activo → 150-200 mW.
Desde `WIFI_PS_MIN_MODEM` → 0 mW.

### Fix propuesto (NO validado)
```cpp
// En setup() — hacer condicional:
if (rtspServerEnabled) WiFi.setSleep(false);

// En checkWiFiHealth (reconnect handler):
if (!idleModeActive) WiFi.setSleep(false);
```

### Lo que NO funciona (no repetir)
- `esp_wifi_stop()` extra — redundante, `WiFi.mode(WIFI_OFF)` ya lo hace
- Restaurar CPU a 160MHz antes de sleep — inelegante y no era la causa real

---

## RTSP Streaming — Reglas Críticas

### Orden del loop (OBLIGATORIO)
```cpp
void loop() {
    ArduinoOTA.handle();
    // RTSP PRIMERO — tiempo crítico para evitar overflow DMA I2S
    if (rtspServerEnabled) { processRTSP(); streamAudio(); }
    // Resto después
    webui_handleClient();
    checkTemperature(); checkWiFi(); checkMqtt(); ...
}
```
Si `streamAudio()` no va al principio, el DMA I2S hace overflow → glitches de audio.

### Parámetros DMA I2S
- `dma_desc_num=16`, `dma_frame_num=512` → **170ms @ 48kHz** de margen
- Tolera spikes de loop de hasta 170ms sin perder audio

### Timeout TCP
- `SO_SNDTIMEO` se setea en el socket al aceptar cada cliente (`setRtspSndTimeout`)
- `RTSP_WRITE_TIMEOUT_MS = 500ms` — nunca usar < 100ms (lwIP blocking)
- `availableForWrite() == 0` NO es condición fiable para saltarse `write()` en ESP32

### processRTSP
Procesa máximo 1 comando por iteración del loop (evita starvation de `streamAudio`).

### Diagnóstico de glitches
Comparar `current_rate_pkt_s` vs `sample_rate / buffer_size` en `/api/status`.

### Parámetros de timing de referencia (48kHz, buffer 1024)

| Parámetro | Valor |
|-----------|-------|
| Packet interval | 21.3ms |
| DMA frame size | 512 samples |
| DMA descriptors | 16 |
| DMA total capacity | 8192 samples = 170ms |
| Expected pkt/s | 46.9 |
| RTSP_WRITE_TIMEOUT_MS | 500ms |
| i2s_read timeout | 50ms |

---

## Testing

### Battery de tests (v1.6.0-le.1)
- `test_commit_67e0ef2.sh` — 82 tests curl contra el device (82/82 PASS)
- `config_backup.json` — snapshot de configuración (sin MQTT password)
- `restore_config.sh` — restaura config desde cero: `bash restore_config.sh [IP]`

### Notas importantes
- `wifi_tx` manual: acepta `{-1.0, 2.0, 5.0..19.5}` (hardware steps)
- `buffer` / `shift`: requieren `reset_i2s` para reflejarse en la API tras set
- **cpu_freq < 80**: NO usar en tests — WiFi pierde conectividad
- Tests de rotación del log (LOG_CAP=120): sleep 0.2s entre peticiones (evita WDT reset por escrituras NVS masivas)
- Adaptive TX en tests: usar siempre 18.5 para desactivar (no valores bajos — pierde señal)

### Lecciones aprendidas (crashes durante testing)
- 110 peticiones rápidas de `hp_cutoff` sin pausa → WDT reset + corrupción NVS
- NVS corrupto con `cpu_freq=40` → WiFi inestable (mínimo para WiFi: 80MHz)
- Recuperación: `EraseFlash=all` + reconfigura WiFi vía WiFiManager AP
