@echo off
setlocal enabledelayedexpansion

REM Check command-line argument
if "%1"=="" (
    echo [!] Please specify --null or --seek
    exit /b 1
)

REM Set user and password based on flag
if "%1"=="--null" (
    set "POSTGRES_USER=!POSTGRES_USER!"
    set "PGPASSWORD=!POSTGRES_PASSWORD!"
) else if "%1"=="--seek" (
    set "POSTGRES_USER=!POSTGRES_SEEKER!"
    set "PGPASSWORD=!POSTGRES__SEEKER_PASSWORD!"
) else (
    echo [!] Invalid option: %1
    exit /b 1
)

REM Other connection variables
set "POSTGRES_DB=!POSTGRES_DB!"
set "POSTGRES_HOST=!POSTGRES_HOST!"
set "POSTGRES_PORT=!POSTGRES_PORT!"

REM Run the test query
psql -h !POSTGRES_HOST! -p !POSTGRES_PORT! -U !POSTGRES_USER! -d !POSTGRES_DB! -c "SELECT now();"
if !errorlevel! neq 0 (
    echo [!] Connection failed for user !POSTGRES_USER!
) else (
    echo [>] Connection successful for user !POSTGRES_USER!
)
