@echo off
setlocal
cd /d "%~dp0"
set "APPDATA=%~dp0.local\roaming"
set "LOCALAPPDATA=%~dp0.local\local"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%~dp0runtime\Godot.exe" (
 echo The Godot runtime is missing: runtime\Godot.exe
 echo.
 echo Download the pinned engine by running this from the project folder:
 echo   powershell -ExecutionPolicy Bypass -File scripts\get_godot.ps1
 echo.
 pause
 exit /b 1
)
rem A fresh clone has no import cache; build it once before the first run.
if not exist "%~dp0.godot\imported" (
 echo Importing project assets for the first run. This takes a moment...
 start "" /wait "%~dp0runtime\Godot.exe" --headless --path "%~dp0." --import --log-file "%~dp0.local\import.log"
)
start "Project Freedom" "%~dp0runtime\Godot.exe" --path "%~dp0." --audio-driver Dummy --log-file "%~dp0.local\game.log"
endlocal
