@echo off
cd /d "%~dp0"
title Queue System Server

REM Check if node is available
where node >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Node.js not found. Please reinstall Queue System.
  pause
  exit /b 1
)

REM Kill any existing instance on port 3000
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":3000 "') do (
  taskkill /f /pid %%a >nul 2>&1
)

REM Start server (minimized in background)
start "Queue System" /MIN cmd /c "node server.js >> data\server.log 2>&1"

REM Wait for server to start
timeout /t 2 /nobreak >nul

REM Detect LAN IP
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /R /C:"IPv4.*192\." /C:"IPv4.*10\." /C:"IPv4.*172\."') do (
  set LAN_IP=%%a
  goto :found_ip
)
:found_ip
if defined LAN_IP (
  set LAN_IP=%LAN_IP: =%
  echo.
  echo ========================================
  echo   Queue System Server Started
  echo ========================================
  echo   Local:  http://localhost:3000
  echo   LAN:    http://%LAN_IP%:3000
  echo   (เครื่องอื่นใน LAN ใช้ที่อยู่ LAN)
  echo ========================================
  echo.
)

REM Open browser
start http://localhost:3000
