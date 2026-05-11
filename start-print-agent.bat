@echo off
cd /d "%~dp0"
title Queue Print Agent

where node >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Node.js not found.
  echo กรุณาติดตั้ง Node.js จาก https://nodejs.org
  pause
  exit /b 1
)

REM Kill any existing agent on port 3001
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":3001 "') do (
  taskkill /f /pid %%a >nul 2>&1
)

echo.
echo ========================================
echo   Queue Print Agent
echo ========================================
echo   Port: 3001
echo   พร้อมรับคำสั่งปริ้นแล้ว
echo ========================================
echo.

node print-agent.js
pause
