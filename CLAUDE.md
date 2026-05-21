# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**M5ReadPaper** — Embedded C++17 firmware for the M5Stack PaperS3 e-ink reader (ESP32-S3, 540×960 EPD, 16MB flash, PSRAM). Built with **PlatformIO** using the Arduino + ESP-IDF hybrid framework.

Primary language for documentation: **Chinese**. Code identifiers and comments: mixed Chinese/English.

## Build & Upload

```bash
platformio run                          # Build (debug config, keeps symbols)
platformio run --target upload --upload-port COM4  # Build & upload
```

VS Code tasks (`Ctrl+Shift+B`): "Build" and "Build and Upload Debug" are pre-configured in `.vscode/tasks.json`.

Monitor (serial): 115200 baud, esp32_exception_decoder filter active.

## Architecture

### State Machine (Core Scheduler)

The system is a **message-driven state machine** running on a single FreeRTOS task (`StateMachineTask`). A queue (depth 10) receives `SystemMessage_t` messages; the task dispatches to state handlers based on `currentState_`.

**States** (defined in `src/tasks/state_machine_task.h`):
- `STATE_IDLE` — lock screen / standby
- `STATE_DEBUG` — debug mode
- `STATE_READING` — active reading (page turns, auto-read)
- `STATE_READING_QUICK_MENU` — quick menu overlay during reading
- `STATE_HELP` — help screen
- `STATE_INDEX_DISPLAY` / `STATE_TOC_DISPLAY` — bookmarks / table of contents
- `STATE_MENU` / `STATE_MAIN_MENU` / `STATE_2ND_LEVEL_MENU` — menu hierarchy
- `STATE_WIRE_CONNECT` — WiFi hotspot interaction mode
- `STATE_USB_CONNECT` — USB mass storage mode
- `STATE_SHUTDOWN` — shutdown sequence

State handlers live in `src/tasks/state_*.cpp`. States switch by directly setting `currentState_` within a handler.

**Message types**: `MSG_TIMER_MIN_TIMEOUT`, `MSG_TIMER_5S_TIMEOUT`, `MSG_USER_ACTIVITY`, `MSG_TOUCH_PRESSED/RELEASED/EVENT`, `MSG_DOUBLE_TOUCH_PRESSED`, `MSG_BATTERY_STATUS_CHANGED`, etc.

### Other FreeRTOS Tasks

- **`timer_interrupt_task`** — periodic timers (1min / 5s ticks)
- **`device_interrupt_task`** — touch and battery polling at `DEVICE_INTERRUPT_TICK` (10ms)
- **`display_push_task`** — asynchronous EPD refresh with animation effects (~53KB, `src/tasks/display_push_task.cpp`)
- **`background_index_task`** — indexes book content in background (~35KB)

### Source Tree

| Directory | Purpose |
|-----------|---------|
| `src/init/` | System init: hardware, SD, SPIFFS, power, IMU |
| `src/tasks/` | FreeRTOS tasks & all state machine handlers |
| `src/device/` | Device abstraction: file manager, power, USB MSC, WiFi hotspot, display, memory pool |
| `src/text/` | Text engine: book parsing, pagination, font rendering, GBK/Unicode, simplified/traditional conversion |
| `src/ui/` | UI components: lock screen, TOC, screenshot, terminal |
| `src/api/` | HTTP API routing (for WiFi hotspot mode) |
| `src/config/` | JSON config persistence via ArduinoJson |
| `src/SD/` | SD card wrapper |
| `include/` | Global headers: `readpaper.h` (all system macros), `papers3.h`, `current_book.h` |

### Key Global Definitions

`include/readpaper.h` is the central configuration header — screen dimensions, margins, refresh thresholds, font scaling, render quality modes, `GlobalConfig` struct, timing constants. **Always check this file first** when touching system behavior.

`src/globals.cpp/.h` — runtime globals and font-scale/margin helper functions.

### Font System

Fonts are 1-bit bitmap `.bin` files. The system font (`lite.cpp`, 48MB) is compiled into PROGMEM. Custom fonts can be loaded from SPIFFS (`/spiffs/lite.bin`). Font generation tools live in `tools/` (Python, requires `tools/setup.bat` for virtualenv). See `docs/FONTS.md`.

### Render Quality Tiers

Defined in `readpaper.h`:
- `FONT_RENDER_TRADEOFF_FAST` (0) — speed priority, fewer refreshes, no far-page prefetch
- `FONT_RENDER_TRADEOFF_BALANCED` (1) — middle ground, prefetch enabled
- `FONT_RENDER_TRADEOFF_QUALITY` (2) — best visual quality, most refreshes

## Setup Prerequisites (One-Time)

### TinyUSB

The hybrid Arduino+ESP-IDF framework requires manual TinyUSB setup (see `docs/TYNIUSB.md`):
1. Apply `tinyusb.Kconfig` patch to framework's TinyUSB directory
2. Fix a typo bug in the Arduino-bundled tinyusb library
3. Add `tinyusb` to the `requires` and `priv_requires` lists in `.platformio/packages/framework-arduinoespressif32/CMakeLists.txt`

### M5GFX Local Patches

Files in `M5GFX/src/` must be manually copied over the corresponding files in `.pio/libdeps/PaperS3/M5GFX/` after library installation. These patches modify EPD panel behavior (LUTs, refresh timing, DMA). The version must match the `M5GFX` version in `platformio.ini` (currently 0.2.20).

## Important Constraints

- **Flash layout**: 16MB total — `full_16MB.csv` partitions (nvs, app0 @ 0x10000 for ~13.4MB, spiffs @ 0xD88000 for ~2.5MB)
- **Message queue depth is only 10** — high-frequency events can cause message loss (logged as errors)
- **Large source files**: `book_handle.cpp` (149KB), `bin_font_print.cpp` (168KB), `wifi_hotspot_manager.cpp` (160KB) — these grew organically via AI assistance
- **SPIFFS** is the filesystem, not LittleFS — path prefixes are `/spiffs/` and `/sd/`
- `STATE_WIRE_CONNECT` has a known typo ("WIRE" instead of "WIFI") — kept for compatibility, do not rename

## Key Documentation

- `docs/ARCHITECTURE.md` — state machine details, message types, state transitions
- `docs/FONTS.md` — font binary format and generation pipeline
- `docs/WIFI_HTTP_API.md` — HTTP API reference for the browser extension
- `docs/TYNIUSB.md` — TinyUSB integration notes
- `README.md` — project overview (Chinese), toolchain setup

## Debug Approach

No formal test framework. Debug via:
- Serial monitor (115200 baud) with `esp32_exception_decoder`
- Compile-time debug flag `DEBUGON` (commented out in `readpaper.h`)
- `src/test/test_functions.cpp` — runtime diagnostics, enable per compilation
- `src/test/per_file_debug.h` — per-file debug output toggles
- `build_type = debug` in `platformio.ini` keeps symbols for backtraces

## Browser Extension

`webapp/extension/` — Manifest V3 browser extension (Chrome/Firefox) that communicates with the device over WiFi HTTP API. Separate manifests: `manifest.chrome.json`, `manifest.ff.json`. **From v2.0 onward, the extension is closed-source**; this repo contains the last open-source version (Apache 2.0).