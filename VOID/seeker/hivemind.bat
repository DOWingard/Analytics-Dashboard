@echo off
REM =========================================================
REM hivemind.bat - CLI for SEEKR
REM Usage:
REM   hivemind.bat --ping
REM   hivemind.bat --metrics funds costs
REM   hivemind.bat --runway
REM =========================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM --- Determine Python executable ---
SET PY=python

REM --- Check if SEEKR script exists ---
IF NOT EXIST "seekr/seekr.py" (
    REM [!] seekr/seekr.py not found!
    EXIT /B 1
)

REM --- Parse command-line flags ---
SET FLAG=
SET ARGS=

:parse_args
IF "%~1"=="" GOTO end_parse
IF "%~1"=="--ping" SET FLAG=ping
IF "%~1"=="--metrics" SET FLAG=metrics
IF "%~1"=="--runway" SET FLAG=runway

REM If flag is metrics, accumulate column names
IF DEFINED FLAG (
    IF "%FLAG%"=="metrics" (
        SHIFT
        :collect_metrics
        IF "%~1"=="" GOTO end_parse
        IF "%~1:~0,2%"=="--" GOTO end_parse
        SET ARGS=!ARGS! "%~1"
        SHIFT
        GOTO collect_metrics
    )
)
SHIFT
GOTO parse_args

:end_parse

REM --- Run Python with SEEKR ---
IF "%FLAG%"=="ping" (
    %PY% - <<END
from seekr.seekr import SEEKR
s = SEEKR()
s.ping()
END
)

IF "%FLAG%"=="metrics" (
    %PY% - <<END
from seekr.seekr import SEEKR
s = SEEKR()
data = s.metrics_as_dict(*[%ARGS%])
for date, vals in data.items():
    print(date, vals)
END
)

IF "%FLAG%"=="runway" (
    %PY% - <<END
from seekr.seekr import SEEKR
s = SEEKR()
data = s.metrics_as_dict()
print("Runway (months):", s.compute_runway(data))
END
)

IF NOT DEFINED FLAG (
    REM [!] No valid flag provided. Use --ping, --metrics, or --runway.
)
