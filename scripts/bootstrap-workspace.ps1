# ============================================================================
# 脚本名称: bootstrap-workspace.ps1
# 用途:     M5ReadPaper 首次克隆后的工作空间初始化 (一次性)
# 调用方式: .\scripts\bootstrap-workspace.ps1
#           .\scripts\bootstrap-workspace.ps1 -SkipM5GFX    (跳过 M5GFX 补丁)
#           .\scripts\bootstrap-workspace.ps1 -SkipTinyUSB  (跳过 TinyUSB 检查)
#           .\scripts\bootstrap-workspace.ps1 -DryRun       (预演模式, 只检查不改写)
#
# 执行步骤:
#   1. 检查 PlatformIO 安装
#   2. 安装依赖库 (platformio run 自动触发 lib_deps 下载)
#   3. 覆盖 M5GFX 本地补丁 (EDP 面板 LUT / DMA / 刷新策略)
#   4. 检查 TinyUSB 框架配置 (混合 Arduino + ESP-IDF 框架所需)
#   5. 可选: 执行一次编译验证环境完整性
#
# 设计意图:
#   让新人 clone 之后跑一个命令就能把所有补丁和依赖装好, 不用手动翻文档改框架文件
# ============================================================================

param(
    [switch]$SkipM5GFX,        # 跳过 M5GFX 补丁覆盖步骤
    [switch]$SkipTinyUSB,      # 跳过 TinyUSB 配置检查步骤
    [switch]$SkipBuild,        # 跳过最终编译验证步骤
    [switch]$DryRun            # 预演模式: 只检查不实际修改文件
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  M5ReadPaper 工作空间初始化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  项目路径: $RepoRoot"
if ($DryRun) {
    Write-Host "  模式: 预演 (仅检查, 不修改)" -ForegroundColor Yellow
}
Write-Host ""

# ========================================================================
# 步骤 1: 检查 PlatformIO
# ========================================================================
Write-Host "[1/4] 检查 PlatformIO 安装..." -ForegroundColor Yellow

$PioPath = "$env:USERPROFILE\.platformio\penv\Scripts\platformio.exe"
if (-not (Test-Path $PioPath)) {
    Write-Host "  [失败] 未在默认位置找到 PlatformIO" -ForegroundColor Red
    Write-Host "         预期: $PioPath"
    Write-Host "         请先安装 VSCode 扩展 'PlatformIO IDE'"
    Write-Host "         安装后重启 VSCode, 左侧栏会出现蚂蚁头图标"
    exit 1
}
Write-Host "  [OK] PlatformIO 已安装" -ForegroundColor Green

# ========================================================================
# 步骤 2: 安装依赖库 (首次 platformio run 会自动下载 lib_deps)
# ========================================================================
Write-Host "[2/4] 安装依赖库 (M5Unified, M5GFX, ArduinoJson)..." -ForegroundColor Yellow
Write-Host "  提示: 首次运行会从网络下载, 可能需要几分钟"

if (-not $DryRun) {
    Push-Location $RepoRoot
    try {
        # platformio run 首次运行会自动下载 framework + lib_deps
        # 即使编译报错 (如 TinyUSB 未配置), 库文件也已经就位
        & platformio run 2>&1 | Out-Host
        $BuildResult = $LASTEXITCODE
        if ($BuildResult -eq 0) {
            Write-Host "  [OK] 依赖库安装完成, 编译通过" -ForegroundColor Green
        } else {
            Write-Host "  [提示] 依赖库已下载, 但编译未通过 (可能需配置 TinyUSB, 见步骤 4)" -ForegroundColor Yellow
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  [预演] 跳过实际安装" -ForegroundColor Gray
}

# ========================================================================
# 步骤 3: 覆盖 M5GFX 本地补丁
# ========================================================================
if (-not $SkipM5GFX) {
    Write-Host "[3/4] 应用 M5GFX 本地补丁..." -ForegroundColor Yellow
    Write-Host "  说明: 项目 M5GFX/src/ 下的文件修改了 EPD 面板的 LUT、"
    Write-Host "        刷新时序和 DMA 传输策略, 需要覆盖 PlatformIO 下载的库文件"
    Write-Host "        版本需与 platformio.ini 中 M5GFX 版本一致 (当前: 0.2.20)"

    # 在 .pio/libdeps 中搜索 M5GFX 目录
    $M5GFXTargets = Get-ChildItem -Path "$RepoRoot\.pio\libdeps" -Recurse -Directory -Filter "M5GFX" -ErrorAction SilentlyContinue

    if (-not $M5GFXTargets) {
        Write-Host "  [错误] 未找到 M5GFX 库目录" -ForegroundColor Red
        Write-Host "         可能原因: 步骤 2 未完成, .pio/libdeps 尚未生成"
        Write-Host "         请先确保步骤 2 已执行 (依赖库已下载)"
    } else {
        $SourceDir = "$RepoRoot\M5GFX\src"
        if (-not (Test-Path $SourceDir)) {
            Write-Host "  [错误] 补丁源目录不存在: $SourceDir" -ForegroundColor Red
        } else {
            foreach ($target in $M5GFXTargets) {
                $DestDir = Join-Path $target.FullName "src"
                if (-not (Test-Path $DestDir)) {
                    Write-Host "  [错误] 目标目录不存在: $DestDir" -ForegroundColor Red
                    continue
                }
                if ($DryRun) {
                    Write-Host "  [预演] 将覆盖: $SourceDir -> $DestDir" -ForegroundColor Gray
                } else {
                    Copy-Item -Path "$SourceDir\*" -Destination $DestDir -Recurse -Force
                    Write-Host "  [OK] 已覆盖: $DestDir" -ForegroundColor Green
                }
            }
        }
    }
} else {
    Write-Host "[3/4] M5GFX 补丁: 已跳过 (-SkipM5GFX)" -ForegroundColor Gray
}

# ========================================================================
# 步骤 4: 检查 TinyUSB 框架配置
# ========================================================================
if (-not $SkipTinyUSB) {
    Write-Host "[4/4] 检查 TinyUSB 配置..." -ForegroundColor Yellow
    Write-Host "  说明: 混合 Arduino + ESP-IDF 框架需要手动注册 tinyusb 组件"

    $ArduinoFramework = "$env:USERPROFILE\.platformio\packages\framework-arduinoespressif32"
    $CMakeFile = Join-Path $ArduinoFramework "CMakeLists.txt"
    $KconfigFile = Join-Path $ArduinoFramework "tools" "sdk" "tinyusb" "Kconfig"
    $KconfigSource = "$RepoRoot\tinyusb.Kconfig"

    # 4a: 检查 CMakeLists.txt 是否注册了 tinyusb
    if (-not (Test-Path $CMakeFile)) {
        Write-Host "  [错误] Arduino 框架未找到: $CMakeFile" -ForegroundColor Red
        Write-Host "         请确认步骤 2 已完成 (platformio run 会下载 framework)"
    } else {
        $cmakeContent = Get-Content $CMakeFile -Raw
        if ($cmakeContent -match "tinyusb") {
            Write-Host "  [OK] CMakeLists.txt 已注册 tinyusb" -ForegroundColor Green
        } else {
            Write-Host "  [待处理] CMakeLists.txt 中未注册 tinyusb 组件" -ForegroundColor Yellow
            Write-Host "           需要在该文件中添加 'tinyusb' 到两行:"
            Write-Host "             set(requires ... tinyusb)"
            Write-Host "             set(priv_requires ... tinyusb)"
            Write-Host "           文件位置: $CMakeFile"
            if (-not $DryRun) {
                Write-Host "           是否要自动添加? (功能预留, 目前请手动编辑)" -ForegroundColor Yellow
            }
        }
    }

    # 4b: 提示 Kconfig 补丁
    if (Test-Path $KconfigSource) {
        Write-Host "  [提示] tinyusb.Kconfig 补丁文件存在于项目根目录" -ForegroundColor Gray
        Write-Host "         需复制到框架的 TinyUSB Kconfig 位置进行合并"
        Write-Host "         详见 docs/TYNIUSB.md"
    }
} else {
    Write-Host "[4/4] TinyUSB 检查: 已跳过 (-SkipTinyUSB)" -ForegroundColor Gray
}

# ========================================================================
# 收尾
# ========================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  初始化完成" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
if (-not $SkipBuild -and -not $DryRun) {
    Write-Host "  已验证编译流程, 详情见上方输出"
}
Write-Host "  下一步: 按需运行以下命令" -ForegroundColor White
Write-Host "    .\scripts\load-build-env.ps1          加载构建环境到当前终端"
Write-Host "    .\scripts\setup-python-tools.ps1      初始化 Python 字体工具链"
Write-Host "    platformio run                        编译固件"
Write-Host "    platformio run -t upload              编译并上传到设备"
Write-Host ""