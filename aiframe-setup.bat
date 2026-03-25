@echo off
setlocal EnableDelayedExpansion

echo ========================================
echo   AIFrame Setup
echo ========================================
echo.

:: ── Check internet ──
echo Checking internet connection...
powershell -Command "try { (Invoke-WebRequest -Uri 'https://www.google.com' -UseBasicParsing -TimeoutSec 10).StatusCode | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo.
    echo   Setup requires an internet connection.
    echo   Please check your connection and try again.
    echo.
    pause
    exit /b 1
)

:: ── Step 1: Check for Python ──
echo [1/7] Checking for Python...

set "PYTHON="
where python >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%p in ('where python 2^>nul') do (
        if not defined PYTHON set "PYTHON=%%p"
    )
)

if defined PYTHON (
    echo       Python found: !PYTHON!
) else (
    echo       Python not found. Installing Python...
    echo       This may take a few minutes...

    :: Download latest Python installer
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile '%TEMP%\python-installer.exe'" >nul 2>&1
    if errorlevel 1 (
        echo.
        echo   Could not download Python installer.
        echo   Please install Python from python.org and run this setup again.
        echo.
        pause
        exit /b 1
    )

    :: Install Python silently (current user, add to PATH)
    "%TEMP%\python-installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1
    if errorlevel 1 (
        echo.
        echo   Could not install Python automatically.
        echo   Please install Python from python.org and run this setup again.
        echo.
        pause
        exit /b 1
    )

    del "%TEMP%\python-installer.exe" >nul 2>&1

    :: Find the newly installed python (PATH not available in current session)
    for /f "delims=" %%p in ('dir /b /s "%LOCALAPPDATA%\Programs\Python\Python3*\python.exe" 2^>nul') do (
        if not defined PYTHON set "PYTHON=%%p"
    )

    if not defined PYTHON (
        echo.
        echo   Python was installed but could not be located.
        echo   Please close this window, open a new one, and run setup again.
        echo.
        pause
        exit /b 1
    )

    echo       Done. Python installed at: !PYTHON!
)
echo.

:: Derive pip from python path
for %%i in ("!PYTHON!") do set "PYTHON_DIR=%%~dpi"
set "PIP=!PYTHON_DIR!Scripts\pip.exe"

:: ── Step 2: Create directory and download backend ──
echo [2/7] Downloading AIFrame backend...

if not exist "C:\AIFrame" mkdir "C:\AIFrame"
if not exist "C:\AIFrame\backend" mkdir "C:\AIFrame\backend"

:: Download backend zip from GitHub Releases
:: NOTE: Update this URL when you create the GitHub release
set "BACKEND_URL=https://github.com/YOUR_ORG/aiframe/releases/latest/download/backend.zip"
powershell -Command "Invoke-WebRequest -Uri '%BACKEND_URL%' -OutFile 'C:\AIFrame\backend.zip'" >nul 2>&1
if errorlevel 1 (
    :: Retry once
    echo       Retrying download...
    powershell -Command "Invoke-WebRequest -Uri '%BACKEND_URL%' -OutFile 'C:\AIFrame\backend.zip'" >nul 2>&1
    if errorlevel 1 (
        echo.
        echo   Download failed. Please check your internet connection and try again.
        echo.
        pause
        exit /b 1
    )
)

:: Extract backend
powershell -Command "Expand-Archive -Force -Path 'C:\AIFrame\backend.zip' -DestinationPath 'C:\AIFrame\backend'" >nul 2>&1
del "C:\AIFrame\backend.zip" >nul 2>&1
echo       Done.
echo.

:: ── Step 3: Install Python dependencies ──
echo [3/7] Installing dependencies...

"!PIP!" install --quiet -r "C:\AIFrame\backend\requirements.txt" >nul 2>&1
if errorlevel 1 (
    echo       Warning: Some dependencies may have failed to install.
    echo       The backend may not start correctly.
)
echo       Done.
echo.

:: ── Step 4: Download Cloudflare Tunnel ──
echo [4/7] Downloading Cloudflare Tunnel...

if not exist "C:\AIFrame\cloudflared" mkdir "C:\AIFrame\cloudflared"

if not exist "C:\AIFrame\cloudflared\cloudflared.exe" (
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile 'C:\AIFrame\cloudflared\cloudflared.exe'" >nul 2>&1
    if errorlevel 1 (
        echo       Retrying download...
        powershell -Command "Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile 'C:\AIFrame\cloudflared\cloudflared.exe'" >nul 2>&1
        if errorlevel 1 (
            echo.
            echo   Could not download Cloudflare Tunnel.
            echo   Please check your internet connection and try again.
            echo.
            pause
            exit /b 1
        )
    )
    echo       Done.
) else (
    echo       Already installed.
)
echo.

:: ── Step 5: Generate configuration ──
echo [5/7] Generating configuration...

:: Generate BACKEND_SECRET if .env doesn't exist
if not exist "C:\AIFrame\backend\.env" (
    for /f "delims=" %%s in ('"!PYTHON!" -c "import secrets; print(secrets.token_hex(32))"') do set "SECRET=%%s"
    echo BACKEND_SECRET=!SECRET!> "C:\AIFrame\backend\.env"
    echo       Generated backend secret.
) else (
    :: Read existing secret from .env
    for /f "tokens=2 delims==" %%s in ('findstr "BACKEND_SECRET" "C:\AIFrame\backend\.env"') do set "SECRET=%%s"
    echo       Using existing configuration.
)

:: Generate vapid_keys.json if it doesn't exist
if not exist "C:\AIFrame\backend\vapid_keys.json" (
    "!PYTHON!" -c "from py_vapid import Vapid; import json; v = Vapid(); v.generate_keys(); keys = v.to_dict(); json.dump({'public': keys['publicKey'], 'private_key': keys['privateKey']}, open('C:\\AIFrame\\backend\\vapid_keys.json', 'w'), indent=2)" >nul 2>&1
    if errorlevel 1 (
        :: Fallback: generate minimal placeholder
        echo {"public": "placeholder", "private_key": "placeholder"}> "C:\AIFrame\backend\vapid_keys.json"
        echo       Warning: Could not generate VAPID keys. Push notifications may not work.
    ) else (
        echo       Generated VAPID keys.
    )
) else (
    echo       Using existing VAPID keys.
)
echo       Done.
echo.

:: ── Step 6: Download Text to Speech model ──
echo [6/7] Downloading Text to Speech model...

if not exist "C:\AIFrame\tts_models\kokoro" mkdir "C:\AIFrame\tts_models\kokoro"

:: Check if model is already extracted
if exist "C:\AIFrame\tts_models\kokoro\model.onnx" (
    echo       Already installed.
) else (
    echo       This may take a few minutes (~98MB)...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2' -OutFile 'C:\AIFrame\tts_models\bundle.tar.bz2'" >nul 2>&1
    if errorlevel 1 (
        echo       Retrying download...
        powershell -Command "Invoke-WebRequest -Uri 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2' -OutFile 'C:\AIFrame\tts_models\bundle.tar.bz2'" >nul 2>&1
        if errorlevel 1 (
            echo.
            echo   Could not download Text to Speech model.
            echo   You can install it later from the app.
            echo.
        )
    )

    if exist "C:\AIFrame\tts_models\bundle.tar.bz2" (
        echo       Extracting...
        "!PYTHON!" -c "import tarfile; t=tarfile.open(r'C:\AIFrame\tts_models\bundle.tar.bz2','r:bz2'); t.extractall(r'C:\AIFrame\tts_models'); t.close()" >nul 2>&1

        :: Move extracted files from subdirectory to kokoro/
        for /d %%d in ("C:\AIFrame\tts_models\kokoro-*") do (
            if exist "C:\AIFrame\tts_models\kokoro" rmdir /s /q "C:\AIFrame\tts_models\kokoro"
            rename "%%d" "kokoro"
        )

        del "C:\AIFrame\tts_models\bundle.tar.bz2" >nul 2>&1
        echo       Done.
    )
)
echo.

:: ── Step 7: Start AIFrame ──
echo [7/7] Starting AIFrame...

:: Kill any existing process on port 8000
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8000 ^| findstr LISTENING') do taskkill /PID %%a /F >nul 2>&1

:: Start backend
cd /d "C:\AIFrame\backend"
start "AIFrame Backend" "!PYTHON!" main.py
echo       Backend started on port 8000.

:: Wait for backend to be ready
timeout /t 3 /nobreak >nul

:: Start Cloudflare tunnel
if exist "C:\AIFrame\cloudflared\tunnel.log" del "C:\AIFrame\cloudflared\tunnel.log"
start "AIFrame Tunnel" cmd /c ""C:\AIFrame\cloudflared\cloudflared.exe" tunnel --url http://localhost:8000 > "C:\AIFrame\cloudflared\tunnel.log" 2>&1"

echo       Waiting for tunnel...

:: Poll for tunnel URL
:WAIT_TUNNEL
timeout /t 2 /nobreak >nul
set "TUNNEL_URL="
for /f "delims=" %%u in ('powershell -Command "$c = if (Test-Path 'C:\AIFrame\cloudflared\tunnel.log') { Get-Content 'C:\AIFrame\cloudflared\tunnel.log' -Raw } else { '' }; if ($c -match 'https://[a-z0-9-]+\.trycloudflare\.com') { Write-Host $matches[0] }"') do set "TUNNEL_URL=%%u"

if not defined TUNNEL_URL goto WAIT_TUNNEL

echo       Tunnel active: !TUNNEL_URL!
echo       Generating QR code...

:: Generate QR code with URL and token
"!PYTHON!" -c "import qrcode,json; data=json.dumps({'url':'!TUNNEL_URL!/','token':'!SECRET!'}); qr=qrcode.make(data); qr.save(r'C:\AIFrame\qr_code.png')"

:: Open QR code image
start "" "C:\AIFrame\qr_code.png"

echo.
echo ========================================
echo   Setup complete!
echo.
echo   Scan this QR code with the AIFrame app:
echo   File saved to: C:\AIFrame\qr_code.png
echo.
echo   To restart AIFrame later, run:
echo   C:\AIFrame\launch.bat
echo ========================================

:: ── Generate launch.bat for subsequent launches ──
(
echo @echo off
echo setlocal EnableDelayedExpansion
echo.
echo echo Starting AIFrame...
echo echo.
echo.
echo :: Find Python
echo set "PYTHON="
echo for /f "delims=" %%%%p in ('where python 2^^^^>nul'^) do (
echo     if not defined PYTHON set "PYTHON=%%%%p"
echo ^)
echo if not defined PYTHON (
echo     for /f "delims=" %%%%p in ('dir /b /s "%%LOCALAPPDATA%%\Programs\Python\Python3*\python.exe" 2^^^^>nul'^) do (
echo         if not defined PYTHON set "PYTHON=%%%%p"
echo     ^)
echo ^)
echo if not defined PYTHON (
echo     echo Python not found. Please run aiframe-setup.bat again.
echo     pause
echo     exit /b 1
echo ^)
echo.
echo :: Kill existing process on port 8000
echo for /f "tokens=5" %%%%a in ('netstat -ano ^^^^^| findstr :8000 ^^^^^| findstr LISTENING'^) do taskkill /PID %%%%a /F ^^^^>nul 2^^^^>^^^^&1
echo.
echo :: Read secret from .env
echo for /f "tokens=2 delims==" %%%%s in ('findstr "BACKEND_SECRET" "C:\AIFrame\backend\.env"'^) do set "SECRET=%%%%s"
echo.
echo :: Start backend
echo cd /d "C:\AIFrame\backend"
echo start "AIFrame Backend" "^^!PYTHON^^!" main.py
echo echo Backend started on port 8000.
echo.
echo :: Start tunnel
echo if exist "C:\AIFrame\cloudflared\tunnel.log" del "C:\AIFrame\cloudflared\tunnel.log"
echo start "AIFrame Tunnel" cmd /c ""C:\AIFrame\cloudflared\cloudflared.exe" tunnel --url http://localhost:8000 ^> "C:\AIFrame\cloudflared\tunnel.log" 2^>^&1"
echo.
echo echo Waiting for tunnel...
echo :WAIT
echo timeout /t 2 /nobreak ^>nul
echo set "TUNNEL_URL="
echo for /f "delims=" %%%%u in ('powershell -Command "$c = if (Test-Path 'C:\AIFrame\cloudflared\tunnel.log'^) { Get-Content 'C:\AIFrame\cloudflared\tunnel.log' -Raw } else { '' }; if ($c -match 'https://[a-z0-9-]+\.trycloudflare\.com'^) { Write-Host $matches[0] }"'^) do set "TUNNEL_URL=%%%%u"
echo if not defined TUNNEL_URL goto WAIT
echo.
echo echo Tunnel active: ^^!TUNNEL_URL^^!
echo echo Generating QR code...
echo.
echo "^^!PYTHON^^!" -c "import qrcode,json; data=json.dumps({'url':'^^!TUNNEL_URL^^!/','token':'^^!SECRET^^!'}); qr=qrcode.make(data); qr.save(r'C:\AIFrame\qr_code.png')"
echo.
echo start "" "C:\AIFrame\qr_code.png"
echo.
echo echo.
echo echo ========================================
echo echo   AIFrame is running!
echo echo.
echo echo   Scan QR code with your phone to connect.
echo echo   File: C:\AIFrame\qr_code.png
echo echo.
echo echo   Close this window to stop AIFrame.
echo echo ========================================
echo echo.
echo pause
) > "C:\AIFrame\launch.bat"

echo.
pause
