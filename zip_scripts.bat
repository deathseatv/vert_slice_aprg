@echo off
setlocal enabledelayedexpansion

:: Set the root directory based on script location
set "ROOT=%~dp0"
set "ZIP_NAME=scripts.zip"
set "ZIP_PATH=%ROOT%%ZIP_NAME%"

echo Checking for files in .\scripts\ and .\objects\...

:: 1. Cleanup existing zip
if exist "%ZIP_PATH%" (
    echo Deleting existing %ZIP_NAME%...
    del /f /q "%ZIP_PATH%"
)

:: 2. Create a temporary staging area to manage the zip structure
set "STAGE=%TEMP%\gml_zip_stage_%RANDOM%"
if exist "%STAGE%" rd /s /q "%STAGE%"
mkdir "%STAGE%"

:: 3. Copy .gml files while maintaining directory structure
set /a FILE_COUNT=0

for %%D in (scripts objects) do (
    if exist "%ROOT%%%D" (
        echo Scanning %%D...
        xcopy "%ROOT%%%D\*.gml" "%STAGE%\%%D\" /S /Y /I >nul 2>&1
        
        :: Count files found in this directory
        for /f %%F in ('dir /s /b "%ROOT%%%D\*.gml" 2^>nul ^| find /c /v ""') do (
            set /a FILE_COUNT+=%%F
        )
    )
)

:: 4. Error handling if no files found
if %FILE_COUNT% EQU 0 (
    echo [ERROR] No .gml files found in .\scripts\ or .\objects\.
    rd /s /q "%STAGE%"
    pause
    exit /b 1
)

echo Found %FILE_COUNT% .gml files. Creating ZIP...

:: 5. Compress using PowerShell
:: We change directory to the STAGE to ensure the ZIP top-level is scripts/objects
powershell -Command "& { Set-Location '%STAGE%'; Compress-Archive -Path * -DestinationPath '%ZIP_PATH%' -Force }"

:: 6. Final Cleanup and Output
rd /s /q "%STAGE%"

if exist "%ZIP_PATH%" (
    echo Successfully created: %ZIP_PATH%
    echo Total files included: %FILE_COUNT%
) else (
    echo [ERROR] Failed to create ZIP file.
    pause
    exit /b 1
)

pause