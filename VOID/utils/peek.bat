@echo off
setlocal enabledelayedexpansion

REM Path to DB scripts (db folder is a sibling of VOID)
set "DB_SCRIPT_DIR=%~dp0..\db"

REM --- Step 1: Print column titles ---
echo [STEP 1] Printing DB columns...
call "%DB_SCRIPT_DIR%\db.bat" --print
if errorlevel 1 (
    echo [ERROR] Printing DB columns failed.
    exit /b 1
)

REM --- Step 2: Peek at DB rows ---
echo [STEP 2] Peeking at DB data...
call "%DB_SCRIPT_DIR%\db.bat" --peek
if errorlevel 1 (
    echo [ERROR] DB peek failed.
    exit /b 1
)

echo [INFO] Peek completed successfully.
exit /b 0
