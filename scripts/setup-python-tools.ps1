# ============================================================================
# 脚本名称: setup-python-tools.ps1
# 用途:     M5ReadPaper Python 工具链初始化 (字体生成 / 映射表生成)
# 调用方式: .\scripts\setup-python-tools.ps1
#           .\scripts\setup-python-tools.ps1 -SkipVenv   (不创建新 venv, 直接用系统 Python)
#           .\scripts\setup-python-tools.ps1 -SkipGUI    (跳过 PySide6 GUI 依赖, 仅装核心)
#
# 行为:
#   1. 检查 Python 3 是否可用
#   2. 在 tools/venv 下创建虚拟环境 (隔离依赖, 不污染系统 Python)
#   3. 安装 tools/requirements.txt 中的依赖包
#   4. 校验关键依赖是否可 import
#   5. 输出各工具脚本的用法
#
# 工具脚本速查:
#   generate_1bit_font_bin.py    字体 -> .bin 1-bit 字体文件 (核心)
#   generate_gbk_table.py        GBK -> Unicode 映射表源码生成
#   gen_zh_table.py              繁简转换表源码生成 (依赖 zh_conv_table.csv)
#   bin_to_progmem.py            .bin -> C 数组 (编译进 PROGMEM)
#
# 关联文件:
#   tools/setup.bat              旧版 CMD 环境初始化脚本 (本脚本的 PowerShell 替代)
#   tools/requirements.txt       pip 依赖清单
# ============================================================================

param(
    [switch]$SkipVenv,          # 跳过虚拟环境创建, 直接在当前 Python 环境安装
    [switch]$SkipGUI,           # 跳过 PySide6 (GUI), 仅装命令行核心依赖
    [switch]$UpgradeOnly        # 仅升级已有环境中的依赖包, 不创建
)

$ErrorActionPreference = "Stop"
$ToolsDir  = Resolve-Path "$PSScriptRoot\..\tools"
$VenvDir   = Join-Path $ToolsDir "venv"
$ReqFile   = Join-Path $ToolsDir "requirements.txt"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  M5ReadPaper Python 工具链初始化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  工具目录: $ToolsDir"
Write-Host ""

# ========================================================================
# 步骤 1: 检查 Python
# ========================================================================
Write-Host "[1/3] 检查 Python 环境..." -ForegroundColor Yellow

$PythonExe = $null
# 尝试多种方式定位 Python
$Candidates = @(
    (Get-Command python -ErrorAction SilentlyContinue).Source,
    (Get-Command python3 -ErrorAction SilentlyContinue).Source,
    (Get-Command py -ErrorAction SilentlyContinue).Source
)
foreach ($c in $Candidates) {
    if ($c) {
        $PythonExe = $c
        break
    }
}

if (-not $PythonExe) {
    Write-Host "  [失败] 未找到 Python" -ForegroundColor Red
    Write-Host "         字体工具需要 Python 3.8+, 请从 https://python.org 下载安装"
    Write-Host "         安装时请勾选 'Add Python to PATH'"
    exit 1
}

# 校验版本 >= 3.8
$pyVersion = & $PythonExe --version 2>&1
Write-Host "  [OK] Python: $pyVersion  路径: $PythonExe" -ForegroundColor Green

$versionMatch = [regex]::Match($pyVersion, '(\d+)\.(\d+)')
if ($versionMatch.Success) {
    $major = [int]$versionMatch.Groups[1].Value
    $minor = [int]$versionMatch.Groups[2].Value
    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 8)) {
        Write-Host "  [错误] 需要 Python 3.8+, 当前为 $pyVersion" -ForegroundColor Red
        Write-Host "         请升级 Python: https://python.org"
        exit 1
    }
}

# ========================================================================
# 步骤 2: 准备虚拟环境
# ========================================================================
Write-Host "[2/3] 准备 Python 虚拟环境..." -ForegroundColor Yellow

if ($SkipVenv) {
    Write-Host "  [跳过] 使用系统 Python 直接安装 (-SkipVenv)" -ForegroundColor Gray
    $PipExe = "$PythonExe -m pip"
    $VenvActive = $false
} elseif ($UpgradeOnly -and (Test-Path $VenvDir)) {
    Write-Host "  [升级] 虚拟环境已存在, 仅升级包" -ForegroundColor Gray
    $Activate = Join-Path $VenvDir "Scripts" "Activate.ps1"
    . $Activate
    $VenvActive = $true
} elseif (Test-Path $VenvDir) {
    Write-Host "  [OK] 虚拟环境已存在: $VenvDir" -ForegroundColor Green
    Write-Host "       如需重建, 请手动删除该目录后重跑本脚本"
    $Activate = Join-Path $VenvDir "Scripts" "Activate.ps1"
    . $Activate
    $VenvActive = $true
} else {
    Write-Host "  创建虚拟环境: $VenvDir"
    & $PythonExe -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [失败] 虚拟环境创建失败" -ForegroundColor Red
        Write-Host "         请确认 Python 安装完整, 或使用 -SkipVenv 参数跳过"
        exit 1
    }
    $Activate = Join-Path $VenvDir "Scripts" "Activate.ps1"
    . $Activate
    $VenvActive = $true
    Write-Host "  [OK] 虚拟环境已创建并激活" -ForegroundColor Green
}

# ========================================================================
# 步骤 3: 安装依赖
# ========================================================================
Write-Host "[3/3] 安装 Python 依赖包..." -ForegroundColor Yellow

if (-not (Test-Path $ReqFile)) {
    Write-Host "  [错误] requirements.txt 不存在: $ReqFile" -ForegroundColor Red
    exit 1
}

Write-Host "  依赖清单: $ReqFile"

# 列出核心依赖供用户确认
Write-Host "  核心依赖: numpy, freetype-py (必需 - 字体解析)"
Write-Host "  可选依赖: scipy (边缘平滑), PySide6 (GUI界面), pyinstaller (打包exe)"

# 安装
if ($SkipGUI) {
    Write-Host "  模式: 仅核心 (跳过 PySide6 GUI 依赖)" -ForegroundColor Gray
    # 单独安装核心依赖, 跳过 GUI 相关
    & pip install numpy freetype-py scipy pillow fonttools 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [警告] 部分核心依赖安装失败, 检查网络连接" -ForegroundColor Yellow
    }
} else {
    & pip install -r $ReqFile 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [警告] 部分依赖安装失败" -ForegroundColor Yellow
        Write-Host "         核心工具可能仍可使用, 但 GUI 和打包功能不可用"
        Write-Host "         重试: 检查网络连接, 或使用 -SkipGUI 仅装核心依赖"
    }
}

# 校验关键依赖
Write-Host ""
Write-Host "  校验关键依赖导入..." -ForegroundColor Gray
$criticalOk = $true
@("numpy", "freetype", "PIL") | ForEach-Object {
    $result = & python -c "import $_; print($_.__version__)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] $_ $result" -ForegroundColor Green
    } else {
        Write-Host "    [缺失] $_ 不可用, 字体生成将失败" -ForegroundColor Red
        $criticalOk = $false
    }
}

# 校验可选依赖
@("scipy", "PySide6") | ForEach-Object {
    $result = & python -c "import $_" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] $_ (可选)" -ForegroundColor Green
    } else {
        Write-Host "    [未装] $_ (可选, 不影响命令行使用)" -ForegroundColor Gray
    }
}

# ========================================================================
# 收尾: 打印工具用法
# ========================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Python 工具链初始化完成" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if (-not $criticalOk) {
    Write-Host "  [警告] 部分核心依赖缺失, 字体工具不可用!" -ForegroundColor Red
    Write-Host "         请检查 pip 安装报错, 确保网络可访问 PyPI"
}

Write-Host ""
Write-Host "  工具用法速查:" -ForegroundColor White
Write-Host "    # 激活环境 (如果尚未激活)" -ForegroundColor Gray
Write-Host "    tools\venv\Scripts\Activate.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "    # 生成 1bit 字体文件 (TTF/OTF -> .bin)" -ForegroundColor Gray
Write-Host "    python tools\generate_1bit_font_bin.py --size 32 --white 80 字体文件.otf 输出.bin" -ForegroundColor Gray
Write-Host ""
Write-Host "    # 生成 GBK -> Unicode 映射表源码" -ForegroundColor Gray
Write-Host "    python tools\generate_gbk_table.py --full > src\text\gbk_unicode_data.cpp" -ForegroundColor Gray
Write-Host ""
Write-Host "    # 生成繁简转换表源码" -ForegroundColor Gray
Write-Host "    python tools\gen_zh_table.py" -ForegroundColor Gray
Write-Host ""
Write-Host "    # 退出虚拟环境" -ForegroundColor Gray
Write-Host "    deactivate" -ForegroundColor Gray
Write-Host ""