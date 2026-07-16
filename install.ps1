# Mission Canvas — Windows Install (PowerShell)
# Usage: irm https://missioncanvas.ai/install.ps1 | iex

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Mission Canvas Installer (Windows)     ║" -ForegroundColor Cyan
Write-Host "  ║   Governed AI for professionals          ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Detect architecture
$arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
Write-Host "  ✓ Detected: windows-$arch" -ForegroundColor Green

$installDir = "$env:USERPROFILE\.mission-canvas"

function Check-Ollama {
    try {
        ollama --version 2>&1 | Out-Null
        Write-Host "  ✓ Ollama detected" -ForegroundColor Green
        Write-Host "  → Suggestion: Run 'ollama pull qwen2.5:7b' to pull the required model." -ForegroundColor Yellow
    } catch {
        Write-Host "  ⚠ Ollama not found. Install from https://ollama.com" -ForegroundColor Yellow
    }
}

# ── Try binary install first ──
$binary = "mc-windows-${arch}.exe"
$url = "https://github.com/pretendhome/mission-canvas/releases/latest/download/$binary"

Write-Host "  → Attempting binary download..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$binarySuccess = $false
try {
    Invoke-WebRequest -Uri $url -OutFile "$installDir\mc.exe" -UseBasicParsing -ErrorAction Stop
    Write-Host "  ✓ Installed mc binary to $installDir\mc.exe" -ForegroundColor Green
    $binarySuccess = $true
} catch {
    Write-Host "  ⚠ Binary download failed or not available. Falling back to source install." -ForegroundColor Yellow
}

if ($binarySuccess) {
    # Add to PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*\.mission-canvas*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
        $env:Path = "$env:Path;$installDir"
        Write-Host "  ✓ Added to PATH" -ForegroundColor Green
    }
    
    # Set UTF-8 permanently
    [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
    
    Check-Ollama

    # Auto-start the web server. Launch `mc serve` directly (a detached, persistent
    # process) rather than `mc start` — a frozen onefile exe spawning ITSELF as a
    # child inherits the parent's PyInstaller temp dir and dies when the parent
    # exits. Start-Process launches an independent process that survives.
    Write-Host "  → Starting web server on http://localhost:7891 ..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath "$installDir\mc.exe" -ArgumentList "serve", "7891" -WindowStyle Hidden -ErrorAction SilentlyContinue
    } catch {}

    # Give the server time to bind. The frozen binary extracts (~3-5s) and loads
    # the ontology/knowledge before binding, so poll up to ~30s.
    $up = $false
    foreach ($i in 1..30) {
        Start-Sleep -Seconds 1
        try {
            Invoke-WebRequest -Uri "http://127.0.0.1:7891/" -UseBasicParsing -TimeoutSec 2 | Out-Null
            $up = $true; break
        } catch {}
    }

    if ($up) {
        Write-Host "  ✓ Web UI is live" -ForegroundColor Green
        Start-Process "http://localhost:7891"            # open the web UI in the browser
    } else {
        Write-Host "  ⚠ Web server didn't come up in time — start it later with 'mc start'" -ForegroundColor Yellow
    }

    # Open the interactive CLI in a NEW window (the current session is the iex pipe)
    Write-Host "  → Opening Mission Canvas shell..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath "powershell" `
            -ArgumentList "-NoExit", "-Command", "& '$installDir\mc.exe' shell" `
            -ErrorAction SilentlyContinue
    } catch {}

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   Installation complete!                 ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║   Web UI:   http://localhost:7891         ║" -ForegroundColor Cyan
    Write-Host "  ║   CLI:      opened in a new window        ║" -ForegroundColor Cyan
    Write-Host "  ║   Status:   mc status                    ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# ── Source fallback ──
Write-Host "  → Installing from source..." -ForegroundColor Cyan

# Check Python
try {
    $pyver = python --version 2>&1
    if ($pyver -match "3\.(1[1-9]|[2-9]\d)") {
        Write-Host "  Python: $pyver ✓" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Python 3.11+ required (found $pyver)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ERROR: Python not found. Install from https://python.org" -ForegroundColor Red
    exit 1
}

# Check Git
try {
    git --version | Out-Null
    Write-Host "  Git: ✓" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Git required. Install from https://git-scm.com" -ForegroundColor Red
    exit 1
}

# Clone or Update
if (-not (Test-Path "$installDir\.git")) {
    Write-Host "  → Cloning Mission Canvas..." -ForegroundColor Cyan
    git clone https://github.com/pretendhome/mission-canvas.git "$installDir"
} else {
    Write-Host "  → Updating existing clone..." -ForegroundColor Cyan
    Push-Location "$installDir"
    try { git pull --quiet } catch {}
    Pop-Location
}

# Install dependencies
Push-Location "$installDir"
Write-Host "Installing Python dependencies..." -ForegroundColor Cyan
pip install --quiet --break-system-packages -e ".[dev]" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install --quiet --break-system-packages pyyaml redis fastapi uvicorn websockets pytest httpx 2>$null
}

# Install Node dependencies (optional)
try {
    $nodever = node --version 2>&1
    Write-Host "  Node.js: $nodever ✓" -ForegroundColor Green
    if (Test-Path "runtime/package.json") {
        Set-Location runtime
        npm install --silent 2>$null
        Set-Location ..
    }
} catch {
    Write-Host "  Node.js: not found (optional)" -ForegroundColor Yellow
}

Check-Ollama

# Health check
Write-Host ""
Write-Host "Running health check..." -ForegroundColor Cyan
try {
    python src/mc_cli.py health
} catch {
    Write-Host "  (Run 'python src/mc_cli.py health' to verify)" -ForegroundColor Yellow
}

# Auto-start server (source mode)
Write-Host "  → Starting API server..." -ForegroundColor Cyan
try {
    Start-Process -FilePath "python" -ArgumentList "src/api_server.py" -WindowStyle Hidden -ErrorAction SilentlyContinue
} catch {}

Pop-Location

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     Installation complete                ║" -ForegroundColor Cyan
Write-Host "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "  ║  Start:  cd $installDir                  ║" -ForegroundColor Cyan
Write-Host "  ║          python src/mc_cli.py shell      ║" -ForegroundColor Cyan
Write-Host "  ║  Web UI: http://localhost:7891            ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
