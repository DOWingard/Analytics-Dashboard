@echo off
setlocal enabledelayedexpansion

REM [Path to .env file (script folder)]
set "ENV_FILE=%~dp0.env"

if not exist "%ENV_FILE%" (
    echo .env file not found at %ENV_FILE%
    exit /b 1
)

REM [Load variables from .env]
for /f "usebackq tokens=1* delims==" %%A in ("%ENV_FILE%") do (
    set "%%A=%%B"
)

REM [Check command-line argument]
if "%1"=="" (
    echo Missing argument. Please specify one of the following flags:
    echo     --null   connect as main user
    echo     --seek   connect as seeker user
    exit /b 1
)

REM [Set user and password based on flag]
if "%1"=="--null" (
    set "USER=!POSTGRES_USER!"
    set "PASS=!POSTGRES_PASSWORD!"
) else if "%1"=="--seek" (
    set "USER=!POSTGRES_SEEKER!"
    set "PASS=!POSTGRES__SEEKER_PASSWORD!"
) else (
    echo Invalid flag: %1
    echo Valid flags are:
    echo     --null
    echo     --seek
    exit /b 1
)

REM [Other connection variables]
set "DB=!POSTGRES_DB!"
set "HOST=!POSTGRES_HOST!"
set "PORT=!POSTGRES_PORT!"

REM [Attempt connection]
echo Connecting as user: %USER% ...
set "PGPASSWORD=%PASS%"
psql -h %HOST% -p %PORT% -U %USER% -d %DB% -c "SELECT now();"

if %errorlevel% neq 0 (
    echo Connection failed for user %USER%
    exit /b 1
) else (
    echo Connection successful for user %USER%
)

endlocal
