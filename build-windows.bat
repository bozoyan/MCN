@echo off
:: build-windows.bat — 代理到 build-windows.ps1

set "SCRIPT_DIR=%~dp0"
set "ARGS=%*"

powershell -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%build-windows.ps1" %ARGS%

if errorlevel 1 (
  echo.
  echo ^=^=^> 构建失败，详情请见上方输出。
  pause
  exit /b 1
)
