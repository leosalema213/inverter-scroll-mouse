@echo off
if exist "%~dp0dist\Mouse Scroll.exe" (
  start "" "%~dp0dist\Mouse Scroll.exe"
  exit /b
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0MouseScroll.ps1"
