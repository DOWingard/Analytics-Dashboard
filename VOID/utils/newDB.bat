@echo off
setlocal enabledelayedexpansion

REM Path to DB scripts (db folder is a sibling of VOID)
set "DB_SCRIPT_DIR=%~dp0..\db"

REM --- Determine if DB has been setup ---
set "DB_SETUP_FLAG=%DB_SCRIPT_DIR%\"

REM --- Step 1: Setup DB if not done yet ---
if not exist "!DB_SETUP_FLAG!" (
    echo [STEP 1] Initial DB setup...
    call "%DB_SCRIPT_DIR%\db.bat" --setup
    if errorlevel 1 (
        echo [ERROR] DB setup failed.
        exit /b 1
    )
    REM Mark setup done
    echo 1> "!DB_SETUP_FLAG!"
) else (
    echo [INFO] DB already set up, skipping --setup
)

REM --- Step 2: Reset DB ---
echo [STEP 2] Resetting DB...
call "%DB_SCRIPT_DIR%\db.bat" --reset
if errorlevel 1 (
    echo [ERROR] DB reset failed.
    exit /b 1
)

REM --- Step 3: Fill DB ---
echo [STEP 3] Filling DB with test data...
call "%DB_SCRIPT_DIR%\db.bat" --fill
if errorlevel 1 (
    echo [ERROR] DB fill failed.
    exit /b 1
)

REM --- Step 4: Print column titles ---
echo [STEP 4] Printing DB columns...
call "%DB_SCRIPT_DIR%\db.bat" --print
if errorlevel 1 (
    echo [ERROR] Printing DB columns failed.
    exit /b 1
)

REM --- Step 5: Peek at DB rows ---
echo [STEP 5] Peeking at DB data...
call "%DB_SCRIPT_DIR%\db.bat" --peek
if errorlevel 1 (
    echo [ERROR] DB peek failed.
    exit /b 1
)

echo [SUCCESS] Test DB is built and ready.
exit /b 0
