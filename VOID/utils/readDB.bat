@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM --- DB path ---
set "DB_PATH=C:\Users\Derek Wingard\Desktop\Work\SAVEMYLIFE\Analytics\data.db"

REM --- Optional table argument ---
set "TABLE=%~1"

echo INFO: Listing tables and columns in "%DB_PATH%"
echo.

if defined TABLE (
    REM --- Peek only specified table ---
    echo Listing columns for table "%TABLE%"
    sqlite3 "%DB_PATH%" "PRAGMA table_info(!TABLE!);" 2>nul
    if !errorlevel! neq 0 (
        echo ERROR: Failed to list columns for table "%TABLE%"
        exit /b !errorlevel!
    )
) else (
    REM --- Peek all tables ---
    for /f "delims=" %%T in ('sqlite3 "%DB_PATH%" ".tables"') do (
        set "CURRENT=%%T"
        if not "!CURRENT!"=="" (
            echo Table !CURRENT!
            sqlite3 "%DB_PATH%" "PRAGMA table_info(!CURRENT!);" 2>nul
            if !errorlevel! neq 0 (
                echo ERROR: Failed to list columns for table "!CURRENT!"
                exit /b !errorlevel!
            )
            echo.
        )
    )
)

echo INFO: Table listing complete.
exit /b 0
