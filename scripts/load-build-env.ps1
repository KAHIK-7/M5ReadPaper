# ============================================================================
# 脚本名称: load-build-env.ps1
# 用途:     加载 M5ReadPaper 项目的构建环境到当前 PowerShell 会话
# 调用方式: . .\scripts\load-build-env.ps1   (前面必须有点号, dot-source 方式)
#
# 行为:
#   1. 探测用户目录下 PlatformIO 的安装位置
#   2. 临时追加到当前会话 PATH (不写注册表, 不污染用户 Profile, 关终端即失效)
#   3. 设置项目环境变量
#   4. 校验 platformio 命令可用性, 打印版本
#   5. 输出常用命令速查
#
# VSCode 终端已配置为开启时自动 dot-source 本脚本, 无需每次手动加载
# ============================================================================

Write-Host "[M5ReadPaper] 正在加载构建环境..." -ForegroundColor Cyan

# --- 1. 探测 PlatformIO 安装 ---
# PlatformIO VSCode 扩展默认安装在 %USERPROFILE%\.platformio\
# 命令行入口: .platformio\penv\Scripts\platformio.exe
$PioBinDir   = "$env:USERPROFILE\.platformio\penv\Scripts"
$PioExePath  = "$PioBinDir\platformio.exe"

if (Test-Path $PioExePath) {
    # 避免重复 dot-source 导致 PATH 不断膨胀
    if ($env:PATH -notlike "*$PioBinDir*") {
        $env:PATH = "$PioBinDir;$env:PATH"
    }
    Write-Host "  [OK] PlatformIO 已发现: $PioExePath" -ForegroundColor Green
} else {
    Write-Host "  [警告] 未在默认位置找到 PlatformIO" -ForegroundColor Yellow
    Write-Host "         预期路径: $PioExePath"
    Write-Host "         请在 VSCode 中安装 'PlatformIO IDE' 扩展后重试"
    Write-Host "         若已手动安装 CLI 版, 请确认 platformio 在系统 PATH 中"
}

# --- 2. 项目相关环境变量 ---
$env:M5READPAPER_ROOT = (Resolve-Path "$PSScriptRoot\..").Path

# --- 3. 校验 platformio 命令 ---
$pioVersion = $null
try {
    $pioVersion = (& platformio --version 2>&1) -join ''
} catch {
    # 静默捕获, 下面统一处理
}

if ($pioVersion -and $LASTEXITCODE -eq 0) {
    Write-Host "  [OK] $pioVersion" -ForegroundColor Green
} else {
    Write-Host "  [错误] platformio 命令不可用, 构建将失败" -ForegroundColor Red
    Write-Host "         请检查: 1) PlatformIO IDE 扩展已安装 2) 终端已重启"
}

# --- 4. 常用命令速查 ---
Write-Host ""
Write-Host "[M5ReadPaper] 环境加载完毕. 常用命令:" -ForegroundColor Cyan
Write-Host "  platformio run                         编译固件"
Write-Host "  platformio run -t upload                编译并上传到设备"
Write-Host "  platformio run -t uploadfs              上传 SPIFFS 数据到设备"
Write-Host "  platformio device monitor               串口监视 (115200 baud)"
Write-Host "  .\scripts\bootstrap-workspace.ps1       首次安装后的完整配置脚本"
Write-Host "  .\scripts\setup-python-tools.ps1        字体生成 Python 工具链初始化"
Write-Host ""