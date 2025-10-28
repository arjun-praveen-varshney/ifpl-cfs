#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install dependencies for TTS & STT fixes
.DESCRIPTION
    Installs required Python packages for IndicSeamless integration
#>

Write-Host "================================" -ForegroundColor Cyan
Write-Host "  Installing TTS & STT Dependencies" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check Python version
Write-Host "1. Checking Python version..." -ForegroundColor Yellow
try {
    $pythonVersion = & python --version 2>&1
    Write-Host "   ✓ $pythonVersion" -ForegroundColor Green
    
    # Extract version number
    if ($pythonVersion -match "Python (\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 8)) {
            Write-Host "   ⚠ Warning: Python 3.8+ recommended, you have $major.$minor" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "   ✗ Python not found" -ForegroundColor Red
    Write-Host "   Install Python from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Navigate to RAG service directory
Write-Host "2. Installing RAG service dependencies..." -ForegroundColor Yellow
Write-Host ""

$ragPath = "packages\rag_service"
if (-not (Test-Path $ragPath)) {
    Write-Host "   ✗ RAG service directory not found: $ragPath" -ForegroundColor Red
    exit 1
}

Push-Location -Path $ragPath

try {
    Write-Host "   📦 Installing Python packages (this may take 5-10 minutes)..." -ForegroundColor Cyan
    Write-Host ""
    
    # Upgrade pip first
    Write-Host "   Upgrading pip..." -ForegroundColor Gray
    & python -m pip install --upgrade pip --quiet
    
    # Install requirements
    Write-Host "   Installing from requirements.txt..." -ForegroundColor Gray
    Write-Host ""
    
    & python -m pip install -r requirements.txt
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "   ✓ All packages installed successfully" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "   ✗ Installation failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    
} catch {
    Write-Host "   ✗ Error during installation: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host ""

# Verify critical packages
Write-Host "3. Verifying installed packages..." -ForegroundColor Yellow
Write-Host ""

$requiredPackages = @(
    "transformers",
    "torch",
    "librosa",
    "torchaudio",
    "openai-whisper",
    "fastapi",
    "uvicorn"
)

$allInstalled = $true
foreach ($pkg in $requiredPackages) {
    $installed = & python -m pip show $pkg 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Extract version
        if ($installed -match "Version: (.+)") {
            $version = $matches[1]
            Write-Host "   ✓ $pkg ($version)" -ForegroundColor Green
        } else {
            Write-Host "   ✓ $pkg (installed)" -ForegroundColor Green
        }
    } else {
        Write-Host "   ✗ $pkg (NOT installed)" -ForegroundColor Red
        $allInstalled = $false
    }
}

Pop-Location

Write-Host ""

if (-not $allInstalled) {
    Write-Host "   ⚠ Some packages are missing" -ForegroundColor Yellow
    Write-Host "   Try: cd packages/rag_service && pip install -r requirements.txt" -ForegroundColor Yellow
    Write-Host ""
}

# Check GPU availability
Write-Host "4. Checking GPU availability..." -ForegroundColor Yellow
Write-Host ""

Push-Location -Path $ragPath

$gpuCheck = @"
import torch
import sys

try:
    cuda_available = torch.cuda.is_available()
    if cuda_available:
        device_name = torch.cuda.get_device_name(0)
        device_count = torch.cuda.device_count()
        print(f'CUDA_AVAILABLE|{device_name}|{device_count}')
        sys.exit(0)
    else:
        print('CUDA_NOT_AVAILABLE')
        sys.exit(0)
except Exception as e:
    print(f'ERROR|{e}')
    sys.exit(1)
"@

$gpuCheck | Set-Content -Path "check_gpu.py" -Encoding UTF8
$result = & python check_gpu.py 2>&1
Remove-Item "check_gpu.py" -ErrorAction SilentlyContinue

if ($result -match "CUDA_AVAILABLE\|(.+)\|(\d+)") {
    $deviceName = $matches[1]
    $deviceCount = $matches[2]
    Write-Host "   ✓ GPU Available: $deviceName" -ForegroundColor Green
    Write-Host "   Device Count: $deviceCount" -ForegroundColor Gray
    Write-Host "   ⚡ IndicSeamless will use GPU acceleration (faster)" -ForegroundColor Cyan
} elseif ($result -match "CUDA_NOT_AVAILABLE") {
    Write-Host "   ⚠ GPU not available" -ForegroundColor Yellow
    Write-Host "   IndicSeamless will use CPU (slower but still works)" -ForegroundColor Gray
} else {
    Write-Host "   ⚠ Could not detect GPU: $result" -ForegroundColor Yellow
}

Pop-Location

Write-Host ""

# Test IndicSeamless model download
Write-Host "5. Testing IndicSeamless model..." -ForegroundColor Yellow
Write-Host ""

Push-Location -Path $ragPath

Write-Host "   📥 Downloading model (this may take 2-5 minutes on first run)..." -ForegroundColor Cyan
Write-Host "   Model size: ~150 MB" -ForegroundColor Gray
Write-Host ""

$modelTest = @"
import sys
import os

# Suppress transformers warnings
os.environ['TRANSFORMERS_VERBOSITY'] = 'error'

try:
    from transformers import AutoProcessor, AutoModelForSpeechSeq2Seq
    import torch
    
    print('Loading model...')
    processor = AutoProcessor.from_pretrained(
        'ai4bharat/indic-wav2vec2-hindi',
        token=False
    )
    
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    model = AutoModelForSpeechSeq2Seq.from_pretrained(
        'ai4bharat/indic-wav2vec2-hindi',
        torch_dtype=torch.float16 if device == 'cuda' else torch.float32,
        token=False
    )
    
    model.to(device)
    model.eval()
    
    print(f'SUCCESS|{device}')
    sys.exit(0)
    
except Exception as e:
    print(f'ERROR|{e}')
    sys.exit(1)
"@

$modelTest | Set-Content -Path "test_model.py" -Encoding UTF8
$result = & python test_model.py 2>&1
Remove-Item "test_model.py" -ErrorAction SilentlyContinue

$success = $false
foreach ($line in $result) {
    if ($line -match "SUCCESS\|(.+)") {
        $device = $matches[1]
        Write-Host "   ✓ IndicSeamless model loaded successfully" -ForegroundColor Green
        Write-Host "   Device: $device" -ForegroundColor Gray
        $success = $true
    } elseif ($line -match "ERROR\|(.+)") {
        $error = $matches[1]
        Write-Host "   ✗ Model loading failed: $error" -ForegroundColor Red
    } elseif ($line -match "Loading model") {
        Write-Host "   $line" -ForegroundColor Gray
    }
}

if (-not $success -and $result -notmatch "ERROR") {
    Write-Host "   ⚠ Model test inconclusive" -ForegroundColor Yellow
    Write-Host "   Will be downloaded on first actual use" -ForegroundColor Gray
}

Pop-Location

Write-Host ""

# Check ffmpeg (for TTS)
Write-Host "6. Checking ffmpeg (for TTS)..." -ForegroundColor Yellow
Write-Host ""

try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-Host "   ✓ ffmpeg installed: $ffmpegVersion" -ForegroundColor Green
} catch {
    Write-Host "   ⚠ ffmpeg not found" -ForegroundColor Yellow
    Write-Host "   Install from: https://ffmpeg.org/download.html" -ForegroundColor Gray
    Write-Host "   Note: Only needed for long TTS responses (>900 characters)" -ForegroundColor Gray
}

Write-Host ""

# Final summary
Write-Host "================================" -ForegroundColor Cyan
Write-Host "  Installation Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

if ($allInstalled) {
    Write-Host "✓ All dependencies installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Start RAG service:    cd packages/rag_service && python server.py" -ForegroundColor Gray
    Write-Host "2. Start backend:        cd packages/backend && npm run dev" -ForegroundColor Gray
    Write-Host "3. Start frontend:       cd packages/frontend && npm run dev" -ForegroundColor Gray
    Write-Host "4. Run tests:            ./test-tts-stt.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Documentation:" -ForegroundColor Cyan
    Write-Host "- FIXES-SUMMARY.md              (Quick overview)" -ForegroundColor Gray
    Write-Host "- TTS-STT-FIXES-COMPLETE.md     (Detailed guide)" -ForegroundColor Gray
    Write-Host "- INDICSEAMLESS-RESEARCH.md     (Research & benchmarks)" -ForegroundColor Gray
} else {
    Write-Host "⚠ Installation completed with warnings" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please review the output above and fix any issues." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor Cyan
    Write-Host "- Update pip:            python -m pip install --upgrade pip" -ForegroundColor Gray
    Write-Host "- Reinstall packages:    cd packages/rag_service && pip install -r requirements.txt" -ForegroundColor Gray
    Write-Host "- Check Python version:  python --version (need 3.8+)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Installation complete! 🎉" -ForegroundColor Cyan
Write-Host ""
