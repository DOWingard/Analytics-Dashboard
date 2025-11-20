@echo off
setlocal enabledelayedexpansion

REM --- Paths ---
cd "C:\Users\Derek Wingard\Desktop\Work\SAVEMYLIFE\Analytics" as root
set "UTILS_DIR=%~dp0VOID\utils"
set "SCRIPTS_DIR=%~dp0VOID\scripts"

REM --- Check argument ---
if "%1"=="" (
    echo Usage: x ^<command^>
    echo Commands:
    echo   new     - Setup a new DB
    echo   peek    - Peek at DB contents
    echo   ping    - Ping the database
    echo   dex     - Run dex.bat with --null --sql
    echo   env     - Run updateEnv.bat with flags
    echo   help    - Show this help message
    echo   view    - Launch FastAPI server
    exit /b 1
)

REM --- NEW ---
if /i "%1"=="new" (
    echo Running new DB setup...
    call "%UTILS_DIR%\newDB.bat"
    if errorlevel 1 (
        echo newDB.bat failed.
        exit /b 1
    )
    goto :eof
)

REM --- PEEK ---
if /i "%1"=="peek" (
    echo Peeking at DB...
    call "%UTILS_DIR%\peek.bat"
    if errorlevel 1 (
        echo peek.bat failed.
        exit /b 1
    )
    goto :eof
)

REM --- PING ---
if /i "%1"=="ping" (
    echo [INFO] Pinging the database with default flag: --null
    call "%SCRIPTS_DIR%\pingDB.bat" --null
    if errorlevel 1 (
        echo pingDB.bat failed.
        exit /b 1
    )
    goto :eof
)

REM --- DEX (always --null --sql) ---
if /i "%1"=="dex" (
    echo [INFO] Running dex.bat with default args: --null --sql
    call "%SCRIPTS_DIR%\dex.bat" --null --sql
    if errorlevel 1 (
        echo dex.bat failed.
        exit /b 1
    )
    exit /b 0
)


REM --- ENV ---
if /i "%1"=="env" (
    pushd "%SCRIPTS_DIR%"
    call "updateEnv.bat"
    if errorlevel 1 (
        echo updateEnv.bat failed.
        popd
        exit /b 1
    )
    popd
    echo .env files updated.
    goto :eof
)

REM --- VIEW ---
if /i "%1"=="view" (
    echo Launching Interface...
    "C:\Python313\python.exe" -m uvicorn main:app --reload
    goto :eof
)

REM --- DUMP ---
if /i "%1"=="dump" (
    echo [INFO] Dumping database to backup file...
    set "BACKUP_DIR=C:\Users\Derek Wingard\Desktop\Work\SAVEMYLIFE\VOID-backend"
    set "BACKUP_FILE=!BACKUP_DIR!\void_backup_%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%.sql"
    
    REM Escape special characters in password for pg_dump
    set "PGPASSWORD=Timecube420"
    
    "C:\Program Files\PostgreSQL\15\bin\pg_dump.exe" ^
        -U nullandvoid ^
        -h 192.9.141.3 ^
        -p 5432 ^
        -d void ^
        -f "!BACKUP_FILE!"
    
    if errorlevel 1 (
        echo [ERROR] pg_dump failed.
        exit /b 1
    )
    echo [SUCCESS] Database dumped to: !BACKUP_FILE!
    goto :eof
)



REM --- HELP ---
if /i "%1"=="help" (
    echo Usage: x ^<command^>
    echo Commands:
    echo   new     - Setup a new DB
    echo   peek    - Peek at DB contents
    echo   ping    - Ping the database for timestamp
    echo   dex     - Run dex.bat with --null --sql
    echo   dump    - Dump the database to a local backend repo
    echo   env     - Update the .env files from root
    echo   view    - Launch Front End FastAPI server
    echo   help    - Show this help message
    goto :eof
)

REM --- Unknown command ---
echo Unknown command: %1
exit /b 1
