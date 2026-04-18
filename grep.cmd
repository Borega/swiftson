@echo off
setlocal

if /I "%~1"=="-q" (
    set "pattern=%~2"
    set "file=%~3"
) else (
    set "pattern=%~1"
    set "file=%~2"
)

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
