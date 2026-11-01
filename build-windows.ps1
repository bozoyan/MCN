<#
.SYNOPSIS
  本地构建 Reveric Windows 安装包（EXE）
.DESCRIPTION
  镜像 CI (.github/workflows/build.yaml) 的 Windows 打包流程：
  1. 安装 Inno Setup + 中文语言文件
  2. 下载 VC++ 可再发行组件
  3. 禁用 pubspec.yaml 中的 sqlite3 hooks
  4. flutter pub get
  5. fastforge 构建 exe 安装包
  6. 还原 pubspec.yaml
.PARAMETER Version
  版本号 (例如 1.2.3+42)。省略则使用 pubspec.yaml 现有版本。
.PARAMETER SkipInstallTools
  跳过工具安装（Inno Setup、语言文件、VC++ Redist）。
.PARAMETER OutputDir
  产物输出目录，默认 dist/
.EXAMPLE
  .\build-windows.ps1
  .\build-windows.ps1 -Version 1.2.3+42
  .\build-windows.ps1 -SkipInstallTools
#>

param(
  [string]$Version,
  [switch]$SkipInstallTools,
  [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupFile = Join-Path $ProjectRoot "pubspec.yaml.bak"

function Write-Step($msg) {
  Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Write-Success($msg) {
  Write-Host "==> $msg" -ForegroundColor Green
}

function Write-Warning($msg) {
  Write-Host "==> $msg" -ForegroundColor Yellow
}

# ----- 前置检查 -----
Write-Step "检查前置依赖..."

$hasFlutter = Get-Command "flutter" -ErrorAction SilentlyContinue
if (-not $hasFlutter) {
  Write-Error "未找到 flutter，请先安装 Flutter SDK。"
  exit 1
}

$hasPython = Get-Command "python3" -ErrorAction SilentlyContinue
if (-not $hasPython) {
  $hasPython = Get-Command "python" -ErrorAction SilentlyContinue
}
if (-not $hasPython) {
  Write-Error "未找到 python3/python，请先安装 Python。"
  exit 1
}

$hasDart = Get-Command "dart" -ErrorAction SilentlyContinue
if (-not $hasDart) {
  Write-Error "未找到 dart，请确保 Flutter SDK 已正确安装。"
  exit 1
}

# 检查 fastforge
$hasFastforge = Get-Command "fastforge" -ErrorAction SilentlyContinue
if (-not $hasFastforge) {
  Write-Step "安装 fastforge..."
  dart pub global activate fastforge
}

# 确保 pubspec.yaml 存在
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
  Write-Error "未找到 pubspec.yaml，请在项目根目录运行此脚本。"
  exit 1
}

# ----- 安装打包工具 -----
if (-not $SkipInstallTools) {
  Write-Step "安装/检查打包工具..."

  # Inno Setup — 确认已安装
  $innoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
  if (-not (Test-Path $innoPath)) {
    Write-Error "未找到 Inno Setup。请手动安装 (https://jrsoftware.org/isdl.php)，然后重新运行。`n  或用 -SkipInstallTools 跳过此检查（如果已安装在其他路径）。"
    exit 1
  }
  Write-Success "Inno Setup 已安装"

  # 中文语言文件
  $langDir = "C:\Program Files (x86)\Inno Setup 6\Languages"
  $langFile = Join-Path $langDir "ChineseSimplified.isl"
  if (-not (Test-Path $langFile)) {
    Write-Step "下载 Inno Setup 中文语言文件..."
    if (-not (Test-Path $langDir)) {
      New-Item -ItemType Directory -Path $langDir -Force | Out-Null
    }
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/ChineseSimplified.isl" `
      -OutFile $langFile
    Write-Success "中文语言文件已下载"
  }
  else {
    Write-Success "中文语言文件已存在"
  }

  # VC++ Redistributable
  $vcRedistPath = Join-Path $ProjectRoot "windows\packaging\exe\vc_redist.x64.exe"
  if (-not (Test-Path $vcRedistPath)) {
    Write-Step "下载 VC++ 可再发行组件..."
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
      -OutFile $vcRedistPath
    Write-Success "VC++ Redist 已下载"
  }
  else {
    Write-Success "VC++ Redist 已存在"
  }
}
else {
  Write-Warning "跳过工具安装"
}

# ----- 备份 pubspec.yaml -----
Write-Step "备份 pubspec.yaml..."
Copy-Item $PubspecPath $BackupFile -Force

try {
  # ----- 设置版本号 -----
  if ($Version) {
    Write-Step "设置版本号为 $Version ..."
    & $hasPython -c @"
import re
with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    content = f.read()
content = re.sub(r'^version:.*', 'version: $Version', content, flags=re.MULTILINE)
with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    f.write(content)
print(f'Version set to $Version')
"@
  }

  # ----- 禁用 sqlite3 system source hook -----
  Write-Step "禁用 pubspec.yaml 中的 sqlite3 hooks..."
  $lines = Get-Content $PubspecPath -Encoding utf8
  $inHooks = $false
  $result = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $lines) {
    if ($line.StartsWith('hooks:')) {
      $inHooks = $true
      $result.Add("# $line")
    } elseif ($inHooks) {
      if ($line.Length -gt 0 -and $line[0] -eq ' ') {
        $result.Add("# $line")
      } else {
        $inHooks = $false
        $result.Add($line)
      }
    } else {
      $result.Add($line)
    }
  }
  $result | Set-Content $PubspecPath -Encoding utf8
  Write-Success "sqlite3 hooks disabled"

  # ----- 清除 sqlite3 hook 缓存，强制重新执行 -----
  Write-Step "清除 sqlite3 hook 缓存..."
  $hookCache = Join-Path $ProjectRoot ".dart_tool/hooks_runner/sqlite3"
  if (Test-Path $hookCache) {
    Remove-Item -Recurse -Force $hookCache
    Write-Success "sqlite3 hook 缓存已清除"
  }

  # ----- flutter pub get -----
  Write-Step "flutter pub get..."
  Push-Location $ProjectRoot
  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get 失败"
  }

  # ----- 清理旧产物 -----
  Write-Step "清理旧 EXE 产物..."
  $distPath = Join-Path $ProjectRoot $OutputDir
  if (Test-Path $distPath) {
    Get-ChildItem $distPath -Recurse -Include "*.exe" | Remove-Item -Force
  }

  # ----- 构建 EXE 安装包 -----
  Write-Step "构建 Windows EXE 安装包 (fastforge windows-exe)..."
  & "$ProjectRoot/third/depth-native/prepare-product-windows.ps1"
  fastforge release --name release --jobs windows-exe --skip-clean
  if ($LASTEXITCODE -ne 0) {
    throw "fastforge windows-exe 构建失败"
  }

  Pop-Location

  # ----- 输出 -----
  Write-Success "Windows 安装包构建完成！"
  Write-Host ""
  Write-Host "产物目录: $OutputDir" -ForegroundColor Green
  $distPath = Join-Path $ProjectRoot $OutputDir
  if (Test-Path $distPath) {
     Get-ChildItem $distPath -Recurse -Include "*.exe" | ForEach-Object {
      Write-Host "  $($_.FullName)" -ForegroundColor Yellow
    }
  }
}
catch {
  Write-Error "构建失败: $_"
  Pop-Location
  exit 1
}
finally {
  # ----- 还原 pubspec.yaml -----
  if (Test-Path $BackupFile) {
    Write-Step "还原 pubspec.yaml..."
    Move-Item $BackupFile $PubspecPath -Force
    Write-Success "pubspec.yaml 已还原"
  }
}
