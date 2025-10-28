@echo off
setlocal

REM --- Determine project root dynamically ---
REM This assumes updateEnv.bat is in VOID/scripts
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"

REM --- Source .env in project root ---
set "SRC_ENV_FILE=%PROJECT_ROOT%\.env"
if not exist "%SRC_ENV_FILE%" (
    echo ! Source .env not found: %SRC_ENV_FILE%
    exit /b 1
)

REM --- Prompt for confirmation if not provided ---
set "CHOICE=%1"
if /I "%CHOICE%"=="" (
    set /p CHOICE=Update existing env scripts [y/n]? 
)

if /I not "%CHOICE%"=="y" (
    echo ! Update cancelled.
    exit /b 0
)

REM --- Recursively update only existing .env files ---
for /r "%PROJECT_ROOT%" %%F in (.env) do (
    REM Skip the source .env in root
    if /I not "%%~fF"=="%SRC_ENV_FILE%" (
        if exist "%%~fF" (
            copy /Y "%SRC_ENV_FILE%" "%%~fF" >nul
            echo [>] Updated: %%~fF
        )
    )
)

echo Done updating existing .env files.
