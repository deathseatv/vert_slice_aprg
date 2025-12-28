@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =====================================================================
REM Copies all .gml files from "scripts" and "objects" folders (wherever
REM they appear under the current directory), preserving relative paths,
REM then creates scripts.zip in the current directory.
REM Requires PowerShell (built into modern Windows).
REM =====================================================================

set "ROOT=%CD%"
set "STAGE=%TEMP%\gml_stage_%RANDOM%%RANDOM%"
set "ZIP=%ROOT%\scripts.zip"

REM Start clean
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
if exist "%STAGE%" rmdir /s /q "%STAGE%" >nul 2>&1
mkdir "%STAGE%" >nul 2>&1

REM Collect .gml from any "scripts" or "objects" folder under ROOT.
REM /R walks recursively; the IF ensures we only take paths that contain \scripts\ or \objects\
for /R "%ROOT%" %%F in (*.gml) do (
  set "FULL=%%~fF"
  set "REL=!FULL:%ROOT%\=!"

  echo(!REL! | findstr /I /C:"\scripts\" /C:"\objects\" >nul
  if not errorlevel 1 (
    for %%D in ("!REL!") do (
      if not exist "%STAGE%\%%~dpD" mkdir "%STAGE%\%%~dpD" >nul 2>&1
    )
    copy /Y "%%~fF" "%STAGE%\!REL!" >nul
  )
)

REM Create ZIP (scripts.zip)
powershell -NoLogo -NoProfile -Command ^
  "Compress-Archive -Path (Join-Path '%STAGE%' '*') -DestinationPath '%ZIP%' -Force"

REM Cleanup staging folder
rmdir /s /q "%STAGE%" >nul 2>&1

echo Created: "%ZIP%"
exit /b 0
