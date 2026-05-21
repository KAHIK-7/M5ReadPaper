# M5ReadPaper 开发指南

> 本文档面向新加入的开发者，以 **SOP（标准作业流程）** 方式说明如何从零搭建开发环境、使用开发工具，以及项目的整体结构。

---

## 一、项目简介

M5ReadPaper 是运行在 **M5Stack PaperS3** 电子墨水屏阅读器上的固件项目。

| 项目 | 详情 |
|------|------|
| 目标硬件 | M5Stack PaperS3（ESP32-S3，540×960 EPD，16MB Flash，PSRAM） |
| 语言 / 标准 | C++17 |
| 构建系统 | PlatformIO（Arduino + ESP-IDF 双框架） |
| 调度核心 | FreeRTOS 消息驱动状态机 |
| 许可证 | Apache 2.0 |

---

## 二、环境搭建 SOP

### 2.1 前置依赖一览

| 依赖 | 用途 | 必装？ |
|------|------|--------|
| **VSCode** | IDE | 是 |
| **PlatformIO 扩展** | 构建 / 上传 / 库管理 | 是 |
| **Python 3.x** | 字体生成工具（仅重建 GBK/繁简转换表时需要） | 否（大多数情况用 JS 扩展代替） |
| **Chrome / Edge / Firefox** | 调试浏览器扩展 | 否 |

### 2.2 步骤一：安装 VSCode + PlatformIO

1. 下载安装 [VSCode](https://code.visualstudio.com/)
2. 在扩展市场搜索 **PlatformIO IDE**，安装
3. 安装完成后左侧会出现 PlatformIO 图标（蚂蚁头），说明安装成功

> PlatformIO 会自动管理 ESP32 工具链和依赖库，无需手动安装 ESP-IDF 或 Arduino 环境。

### 2.3 步骤二：克隆并打开项目

```powershell
git clone <repo-url> M5ReadPaper
```

在 VSCode 中：**文件 → 打开文件夹 → 选择 M5ReadPaper 目录**。

PlatformIO 会自动识别 `platformio.ini` 并初始化环境。首次打开可能需要几分钟下载工具链和依赖库，请耐心等待。

### 2.4 步骤三：首次构建（验证环境）

按 `Ctrl+Shift+B` 选择 **"PlatformIO: Build"**，或在终端中执行：

```powershell
platformio run
```

**如果构建成功**，说明基础环境正确。如果失败，检查：
- PlatformIO 扩展是否安装正确
- 网络是否能访问 PlatformIO 的包仓库

**大概率会失败** — 因为还需要下面两步一次性配置。

### 2.5 步骤四：配置 TinyUSB（一次性操作）

由于项目使用了 Arduino + ESP-IDF 混合框架，TinyUSB 需要手动打补丁。参考 `docs/TYNIUSB.md`：

1. **打 Kconfig 补丁** — 用项目根目录的 `tinyusb.Kconfig` 覆盖框架中 TinyUSB 目录的对应文件。框架路径通常在：
   ```
   %USERPROFILE%\.platformio\packages\framework-arduinoespressif32\
   ```

2. **修拼写错误** — Arduino 集成的 tinyusb 库有一个拼写 bug，编译报错后按错误提示修改即可。

3. **注册 component** — 编辑 `.platformio\packages\framework-arduinoespressif32\CMakeLists.txt`，在 `set(requires ...)` 和 `set(priv_requires ...)` 两行中都加上 `tinyusb`。

### 2.6 步骤五：覆盖 M5GFX 补丁（一次性操作）

`M5GFX/` 目录下存放了针对 EPD 面板的本地修改（LUT 表、刷新策略、DMA 传输等）。

**操作方式**：将 `M5GFX/src/` 下的全部文件复制到对应位置：
```
.pio\libdeps\PaperS3\M5GFX\src\
```
保持目录结构一致即可覆盖。

> **注意**：每次执行 `platformio run --target clean` 或删除 `.pio` 目录后，需重新覆盖这些文件。当前 M5GFX 版本为 `0.2.20`（见 `platformio.ini` 的 `lib_deps`）。

### 2.7 步骤六：上传固件到设备

1. 用 USB 线连接 PaperS3 到电脑
2. 确认串口号（设备管理器 → 端口，通常为 COM4）
3. 上传：

```powershell
platformio run --target upload --upload-port COM4
```

或使用 VS Code 任务 **"Build and Upload Debug"**（默认 COM4，如不同请修改 `.vscode/tasks.json`）。

### 2.8 步骤七：上传 SPIFFS 文件系统（可选）

`data/` 目录包含 SPIFFS 的预置内容（壁纸、配置、默认页面）。上传方式：

```powershell
platformio run --target uploadfs --upload-port COM4
```

---

## 三、开发工具使用

### 3.1 VSCode 内置任务

项目预置了以下构建任务（`Ctrl+Shift+B` 选择）：

| 任务名 | 作用 |
|--------|------|
| PlatformIO: Build | 编译固件（Debug 模式，保留符号） |
| Build and Upload Debug | 编译并通过 COM4 上传 |

终端配置文件：VSCode 设置中预置了 `ReaderPaper PowerShell` 终端 Profile（自动 source `powershell.ps1`），可在终端下拉菜单中切换。

### 3.2 串口监视器

```powershell
platformio device monitor --baud 115200
```

内置了 `esp32_exception_decoder` 过滤器，发生崩溃时会自动翻译回溯地址为函数名和行号。

**常用技巧**：
- 在代码中使用 `Serial.printf()` 打日志
- `include/readpaper.h` 中有注释掉的 `#define DEBUGON` 宏，取消注释即可启用全局调试输出
- `src/test/per_file_debug.h` 可以按文件粒度开关调试日志

### 3.3 Python 字体工具（仅在重建映射表时使用）

项目后期已将大部分字体工具迁移到浏览器扩展（JS），Python 工具仅用于：

- **GBK→Unicode 映射表重建**：`tools/generate_gbk_table.py`
- **繁简转换表重建**：`tools/gen_zh_table.py`（依赖 `tools/zh_conv_table.csv`）

环境搭建：

```powershell
cd tools
.\setup.bat          # 创建 virtualenv 并安装依赖
venv\Scripts\activate.bat  # 之后手动激活
```

### 3.4 浏览器扩展

扩展代码在 `webapp/extension/`，用于通过 WiFi 热点与设备交互（文件管理、字体上传等）。

- **Chrome/Edge**：加载 `webapp/extension/` 目录作为"未打包的扩展"，使用 `manifest.chrome.json`
- **Firefox**：使用 `manifest.ff.json`

**注意事项**：
- 从 V2.0 起，浏览器扩展不再开源 —— 仓库中保留的是最后开源的 V1.x 版本（Apache 2.0）
- 扩展通过 WiFi HTTP API 与设备通信（接口文档见 `docs/WIFI_HTTP_API.md`），设备热点地址为 `http://192.168.4.1`
- 字体生成推荐使用扩展的隐藏功能：在生成页面控制台输入 `showmethemoney(true)` 来开启 PROGMEM 字体生成选项

### 3.5 调试方式

项目**没有单元测试框架**。调试依赖于：

1. **串口日志**（115200 baud + ESP32 异常解码器）
2. **编译期开关**：`DEBUGON` 宏（全局）、`per_file_debug.h`（按文件）
3. **运行时诊断**：`src/test/test_functions.cpp` 中的函数可按需调用
4. **Debug 构建**：`platformio.ini` 中 `build_type = debug`，保留符号用于崩溃回溯

---

## 四、项目结构

### 4.1 顶层目录

```
M5ReadPaper/
├── platformio.ini          # 构建配置（平台、框架、依赖、分区表）
├── full_16MB.csv            # 16MB Flash 分区表
├── sdkconfig.PaperS3        # ESP-IDF SDK 配置
├── CMakeLists.txt           # ESP-IDF CMake 桥接
├── tinyusb.Kconfig          # TinyUSB Kconfig 补丁
│
├── include/                 # 全局头文件
│   ├── readpaper.h          # ★ 核心配置宏 + GlobalConfig 结构体
│   ├── papers3.h            # PaperS3 平台定义
│   └── current_book.h       # 当前书籍接口
│
├── src/                     # 固件源代码
│   ├── main.cpp             # ★ 入口：app_main() → 创建 FreeRTOS 任务
│   ├── globals.cpp/.h       # 运行时全局变量 + 字体缩放辅助函数
│   ├── init/                # 系统初始化（硬件、SD、SPIFFS、电源、IMU）
│   ├── tasks/               # ★ FreeRTOS 任务 + 状态机处理器
│   ├── device/              # 设备抽象（文件管理、电源、USB MSC、WiFi、显示、内存池）
│   ├── text/                # ★ 文本引擎（书籍解析、分页、字体渲染、GBK/繁简转换）
│   ├── ui/                  # UI 组件（锁屏、目录、截图、terminal）
│   ├── api/                 # HTTP API 路由（WiFi 热点模式）
│   ├── config/              # JSON 配置读写（ArduinoJson）
│   ├── SD/                  # SD 卡抽象层
│   └── test/                # 运行时调试辅助
│
├── M5GFX/src/               # M5GFX 本地补丁（需手动覆盖到 .pio/libdeps/）
├── data/                    # SPIFFS 预置内容（壁纸、配置、起始页）
├── Fonts/                   # 预编译 .bin 字体文件 + 参考 TTF
├── tools/                   # Python 工具（字体生成、映射表生成）
├── webapp/extension/        # 浏览器扩展（Manifest V3）
├── docs/                    # 文档
│   ├── ARCHITECTURE.md      # ★ 状态机架构详解
│   ├── FONTS.md             # 字体格式与缓存机制
│   ├── WIFI_HTTP_API.md     # WiFi HTTP API 接口文档
│   └── TYNIUSB.md           # TinyUSB 集成说明
│
├── design/                  # 设计素材（XCF、PNG、JPG）
├── ref/                     # 参考资料
└── wikipics/                # Wiki 截图
```

### 4.2 核心架构：状态机

系统采用 **单 FreeRTOS 任务 + 消息队列** 的调度方式，是理解整个代码库的关键。

```
┌─────────────────────────────────────────────┐
│                   app_main()                 │
│  setup() → 创建4个FreeRTOS任务 → 主循环轮询  │
└─────────────────────────────────────────────┘
         │
         ├── StateMachineTask      ★ 核心：13个状态的消息驱动状态机
         │    ├── STATE_IDLE           锁屏 / 待机
         │    ├── STATE_READING        阅读主流程
         │    ├── STATE_MAIN_MENU      主菜单（文件选择）
         │    ├── STATE_2ND_LEVEL_MENU 二级菜单
         │    ├── STATE_MENU           通用菜单
         │    ├── STATE_READING_QUICK_MENU  阅读快捷菜单
         │    ├── STATE_TOC_DISPLAY    目录
         │    ├── STATE_INDEX_DISPLAY  书签 / 索引
         │    ├── STATE_HELP          帮助
         │    ├── STATE_WIRE_CONNECT   WiFi 热点交互
         │    ├── STATE_USB_CONNECT    USB MSC 模式
         │    ├── STATE_DEBUG         调试模式
         │    └── STATE_SHUTDOWN      关机流程
         │
         ├── TimerInterruptTask    定时器：1分钟 / 5秒脉冲
         ├── DeviceInterruptTask    设备轮询：触摸 + 电池（10ms间隔）
         ├── DisplayPushTask        异步EPD刷新 + 翻页动画
         └── BackgroundIndexTask    后台索书籍内容
```

**消息驱动流程**：
1. 外部模块（触摸、定时器、设备事件）通过 `sendStateMachineMessage()` 向队列发消息
2. 状态机任务从队列取消息，根据 `currentState_` 分派到对应 state handler
3. State handler 处理完可直接修改 `currentState_` 实现状态切换

**状态代码位置**：所有 State handler 都在 `src/tasks/state_*.cpp` 文件中，例如：
- 锁屏逻辑 → `src/tasks/state_idle.cpp`
- 阅读翻页 → `src/tasks/state_reading.cpp`
- 菜单交互 → `src/tasks/state_menu.cpp` / `state_main_menu.cpp` / `state_2nd_level_menu.cpp`

### 4.3 文本引擎（核心子系统）

`src/text/` 是整个项目最复杂的子系统，负责：

| 模块 | 文件 | 大小 | 职能 |
|------|------|------|------|
| 书籍处理 | `book_handle.cpp/.h` | 149KB / 19KB | 书籍加载、分页、翻页、目录解析 |
| 字体渲染 | `bin_font_print.cpp/.h` | 168KB / ... | 1-bit 字体光栅化、字形查找 |
| 字体解码 | `font_decoder.cpp/.h` | ... | 1-bit / V3 / Huffman 位图解碼 |
| 字体缓冲 | `font_buffer.cpp/.h` | 57KB / ... | 多级缓存管理（5页滑动窗口 + 全局缓存） |
| 文本排版 | `text_handle.cpp/.h` | 63KB / ... | 文字布局、分页计算 |
| GBK 转换 | `gbk_unicode_data.cpp` | 512KB | GBK→Unicode 二分查找表 |
| 繁简转换 | `zh_conv_table_generated.cpp` | 2.8MB | 繁简体转换表 + O(1)单字快速索引 |
| 系统字体 | `lite.cpp` | 48MB | 编译进 PROGMEM 的默认 1-bit 字体 |

**字体缓存架构**（当前 V1.6+ 主流方案）：

```
请求渲染字符
    │
    ├── 1. g_common_char_cache        UI常用字符（~300字，启动时构建）
    ├── 2. g_bookname_char_cache      书名字符缓存
    ├── 3. g_toc_char_cache           目录章节字符缓存
    ├── 4. FontBufferManager          5页滑动窗口（阅读场景）
    │       ├── PageFontCache[center]     当前页
    │       ├── PageFontCache[center±1]   前后页（预构建）
    │       └── PageFontCache[center±2]   更远页（预构建）
    └── 5. g_common_recycle_pool      回收池（上限1000字，跨页复用）
        │
        └── 全部未命中 → 从 SD 卡读取（互斥锁保护）
```

### 4.4 关键技术参数速查

| 宏 / 常量 | 位置 | 值 | 含义 |
|-----------|------|----|------|
| `PAPER_S3_WIDTH/HEIGHT` | `readpaper.h` | 540×960 | 屏幕分辨率 |
| `DEVICE_INTERRUPT_TICK` | `readpaper.h` | 10ms | 触摸/电池轮询间隔 |
| `TOUCH_PRESS_GAP_MS` | `readpaper.h` | 200ms | 触摸消抖间隔 |
| `IDLE_PWR_WAIT_MIN` | `readpaper.h` | 30min | 待机后关机计时 |
| `FONT_SCALE_MIN/MAX_PCT` | `readpaper.h` | 80% / 150% | 字号缩放范围 |
| 消息队列深度 | `state_machine_task.cpp` | 10 | **容易丢消息的瓶颈** |
| Flash 分区 | `full_16MB.csv` | app0: ~13.4MB, spiffs: ~2.5MB | SPIFFS 空间有限 |

---

## 五、常见问题

### Q: 构建报 `tinyusb` 相关错误？
A: 检查步骤四（TinyUSB 配置是否完整），特别是 CMakeLists.txt 中是否添加了 `tinyusb`。

### Q: 上传后屏幕显示异常？
A: 检查 M5GFX 补丁是否覆盖（步骤五），M5GFX 版本是否与 `platformio.ini` 一致。

### Q: 如何确认当前固件版本？
A: 查看 `data/version` 文件。也可通过串口监视器查看启动日志，或通过 WiFi API `/heartbeat` 接口获取。

### Q: SPIFFS 空间不够？
A: SPIFFS 分区约 2.5MB。字体文件（`.bin`）通常较大，可考虑将常用字体编译进 PROGMEM（`lite.cpp`）来释放 SPIFFS 空间。

### Q: 如何在设备端调试而不影响正常使用？
A: 使用 `src/test/per_file_debug.h` 仅对目标文件启用调试输出，避免被全局日志淹没。

---

## 六、参考文档索引

| 文档 | 内容 |
|------|------|
| `CLAUDE.md` | AI 助手的项目上下文（构建命令、架构速览、约束条件） |
| `docs/ARCHITECTURE.md` | 状态机详解：13 个状态、消息类型、状态转换 |
| `docs/FONTS.md` | 字体二进制格式、生成流程、多级缓存架构 |
| `docs/WIFI_HTTP_API.md` | WiFi 热点 HTTP API 完整接口文档 |
| `docs/TYNIUSB.md` | TinyUSB 在混合框架下的补丁步骤 |
| `README.md` | 项目原始 README（项目背景和哲学） |
| `TEMP.md` | EPD 显示优化的技术笔记（M5GFX LUT 调优思路） |