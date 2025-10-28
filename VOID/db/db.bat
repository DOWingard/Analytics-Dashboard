@echo off
setlocal enabledelayedexpansion

REM [Check for argument]
if "%1"=="" (
    REM [!] Please provide a flag: --fill, --reset, --setup, --print, or --peek
    exit /b 1
)

REM [Set script path to utils folder]
set "PYTHON_SCRIPT_DIR=%~dp0utils"

REM [Choose Python script based on flag]
if "%1"=="--fill" (
    set "SCRIPT=fillyear.py"
) else if "%1"=="--reset" (
    set "SCRIPT=resetDB.py"
) else if "%1"=="--setup" (
    set "SCRIPT=setupDB.py"
) else if "%1"=="--print" (
    set "SCRIPT=printColumns.py"
) else if "%1"=="--peek" (
    set "SCRIPT=peek.py"
) else (
    REM [!] Invalid option: %1
    exit /b 1
)

REM [Debug: show which script is running]
REM [>] Running %SCRIPT% from %PYTHON_SCRIPT_DIR%...

REM [Run the selected Python script with unbuffered output]
python -u "%PYTHON_SCRIPT_DIR%\%SCRIPT%"
set "PY_EXIT=%ERRORLEVEL%"

REM [Show exit code]
echo Python exit code: %PY_EXIT%

exit /b %PY_EXIT%
