@echo off
setlocal EnableExtensions

set "GIT_BASH="

if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "GIT_BASH=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined GIT_BASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GIT_BASH if exist "%ProgramW6432%\Git\usr\bin\bash.exe" set "GIT_BASH=%ProgramW6432%\Git\usr\bin\bash.exe"
if not defined GIT_BASH if exist "%LocalAppData%\Programs\Git\usr\bin\bash.exe" set "GIT_BASH=%LocalAppData%\Programs\Git\usr\bin\bash.exe"
if not defined GIT_BASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "GIT_BASH=%LocalAppData%\Programs\Git\bin\bash.exe"

if not defined GIT_BASH (
    echo bash.cmd: unable to locate Git Bash executable.>&2
    echo Expected one of: ^"%%ProgramFiles%%\Git\usr\bin\bash.exe^", ^"%%ProgramFiles%%\Git\bin\bash.exe^".>&2
    echo This shim exists to avoid accidental resolution to WSL bash.exe without a configured Linux distro.>&2
    exit /b 9009
)

"%GIT_BASH%" %*
set "EXIT_CODE=%ERRORLEVEL%"
exit /b %EXIT_CODE%
