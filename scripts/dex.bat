@echo off
setlocal enabledelayedexpansion

REM Check command-line argument
if "%1"=="" (
    echo [!] Please specify --null or --seek
    exit /b 1
)

REM Set container and credentials
set "CONTAINER_NAME=void-abyss"

if "%1"=="--null" (
    set "USER=nullandvoid"
    set "DB=nullANDdb"
) else if "%1"=="--seek" (
    set "USER=void-seeker"
    set "DB=nullANDdb"
) else (
    echo [!] Invalid option: %1
    exit /b 1
)

REM Execute inside container
docker exec -it %CONTAINER_NAME% psql -U %USER% -d %DB%
if %errorlevel% neq 0 (
    echo [!] Connection failed for user %USER%
) else (
    echo [>] Connection successful for user %USER%
)
