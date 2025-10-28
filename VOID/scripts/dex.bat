@echo off
setlocal enabledelayedexpansion

REM [Path to .env file (assumes script is in scripts/)]
set "ENV_FILE=%~dp0.env"

if not exist "%ENV_FILE%" (
    REM [.env file not found, exiting]
    exit /b 1
)

REM [Load variables from .env]
for /f "usebackq tokens=1,2 delims==" %%A in ("%ENV_FILE%") do (
    set "%%A=%%B"
)

REM [Check required first argument]
if "%1"=="" (
    REM [Missing required flag. Must specify --null or --seek]
    echo ! Missing required flag. Use --null or --seek
    exit /b 1
)

REM [Set container name and credentials from .env]
set "CONTAINER_NAME=void-abyss"

if "%1"=="--null" (
    set "USER=%POSTGRES_USER%"
    set "DB=%POSTGRES_DB%"
    set "PASS=%POSTGRES_PASSWORD%"
) else if "%1"=="--seek" (
    set "USER=%POSTGRES_SEEKER%"
    set "DB=%POSTGRES_DB%"
    set "PASS=%POSTGRES__SEEKER_PASSWORD%"
) else (
    REM [Invalid option. Must be --null or --seek]
    echo ! Invalid flag: %1. Use --null or --seek
    exit /b 1
)

REM [Optional second flag for running SQL directly]
if "%2%"=="--sql" (
    REM [Run psql inside docker with credentials]
    docker exec -e PGPASSWORD=%PASS% -it %CONTAINER_NAME% psql -U %USER% -d %DB%
    set "EXITCODE=%ERRORLEVEL%"
    REM [Exit with psql exit code]
    exit /b %EXITCODE%
) else (
    REM [Open bash shell inside docker container with environment set]
    docker exec -e PGPASSWORD=%PASS% -it %CONTAINER_NAME% bash
    set "EXITCODE=%ERRORLEVEL%"
    REM [Exit with bash exit code]
    exit /b %EXITCODE%
)
