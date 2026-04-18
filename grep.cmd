@echo off
setlocal EnableExtensions

set "pattern="
set "file="

:parse_flags
if "%~1"=="" goto parsed
if /I "%~1"=="-q" (
    shift
    goto parse_flags
)
if /I "%~1"=="-F" (
    shift
    goto parse_flags
)
if /I "%~1"=="-Fq" (
    shift
    goto parse_flags
)
if /I "%~1"=="-qF" (
    shift
    goto parse_flags
)
if "%~1"=="--" (
    shift
)

goto parsed

:parsed
set "pattern=%~1"
shift
set "file=%~1"

if "%pattern%"=="" (
    echo grep.cmd: missing pattern>&2
    exit /b 2
)

if "%file%"=="" (
    echo grep.cmd: missing file path>&2
    exit /b 2
)

set "GREP_PATTERN=%pattern%"
set "GREP_FILE=%file%"

powershell -NoProfile -Command "$pattern = $env:GREP_PATTERN.Trim('\"'''); $file = $env:GREP_FILE.Trim('\"'''); if (-not (Test-Path -LiteralPath $file)) { exit 2 }; if (Select-String -LiteralPath $file -SimpleMatch -Pattern $pattern -Quiet) { exit 0 } else { exit 1 }"
exit /b %ERRORLEVEL%
