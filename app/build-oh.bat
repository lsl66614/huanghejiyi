@echo off
rem Huanghe Memory OpenHarmony API26 command-line build.
rem ASCII-only on purpose: cmd parses .bat in the console codepage, and Chinese
rem comments written as UTF-8 get split into bogus "commands" (observed 2026-10-26).
rem
rem Gates run BEFORE assembleHap; any non-zero exit blocks packaging.
rem Set SKIP_GATES=1 only for troubleshooting, never for a release artifact.
cd /d "%~dp0"
rem Toolchain overrides: set these before invoking if your install lives elsewhere.
rem Defaults below are this machine's paths, kept only so the original setup still builds.
if not defined DEVECO_SDK_HOME set "DEVECO_SDK_HOME=E:\ .stepclaw\DevEco Studio\sdk"
if not defined OHOS_BASE_SDK_HOME set "OHOS_BASE_SDK_HOME=E:\OpenHarmony\Sdk"
if not defined HUANGHE_NODE set "HUANGHE_NODE=E:\ .stepclaw\DevEco Studio\tools\node\node.exe"
if not defined HUANGHE_HVIGOR set "HUANGHE_HVIGOR=E:\hvigor_shim\bin\hvigorw.js"

if not exist "%HUANGHE_NODE%" (
  echo [build-oh] node not found: %HUANGHE_NODE%
  echo [build-oh] set HUANGHE_NODE to DevEco's node.exe
  exit /b 1
)
if not exist "%HUANGHE_HVIGOR%" (
  echo [build-oh] hvigor not found: %HUANGHE_HVIGOR%
  echo [build-oh] set HUANGHE_HVIGOR to hvigorw.js
  exit /b 1
)
if "%1"=="" (
  set "TASK=assembleHap"
) else (
  set "TASK=%1"
  shift
)

if "%SKIP_GATES%"=="1" (
  echo [build-oh] SKIP_GATES=1, gates skipped
) else (
  echo [build-oh] running gates ...
  chcp 65001 >nul
  python "%~dp0..\tools\run_gates.py"
  if errorlevel 1 (
    echo [build-oh] GATES FAILED, packaging blocked
    exit /b 1
  )
)

"%HUANGHE_NODE%" "%HUANGHE_HVIGOR%" %TASK% --mode module -p "product=default" -p "buildMode=debug" --parallel --incremental %*
