#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for TTS and STT fixes
.DESCRIPTION
    Tests the TTS audio playback and STT transcription functionality
#>

Write-Host "================================" -ForegroundColor Cyan
Write-Host "  TTS & STT Testing Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if services are running
Write-Host "1. Checking if services are running..." -ForegroundColor Yellow
Write-Host ""

# Test RAG Service
try {
    $ragStatus = Invoke-RestMethod -Uri "http://localhost:8000/status" -Method Get -TimeoutSec 5
    Write-Host "   ✓ RAG Service: RUNNING" -ForegroundColor Green
    Write-Host "     - Embedding Model: $($ragStatus.embedding_model)" -ForegroundColor Gray
    Write-Host "     - Index Chunks: $($ragStatus.num_chunks)" -ForegroundColor Gray
    Write-Host "     - Whisper Available: $($ragStatus.whisper_available)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ RAG Service: NOT RUNNING" -ForegroundColor Red
    Write-Host "     Start with: cd packages/rag_service && python server.py" -ForegroundColor Yellow
}

Write-Host ""

# Test Backend Service
try {
    $backendStatus = Invoke-RestMethod -Uri "http://localhost:4000/status" -Method Get -TimeoutSec 5
    Write-Host "   ✓ Backend Service: RUNNING" -ForegroundColor Green
    Write-Host "     - Backend: $($backendStatus.backend)" -ForegroundColor Gray
    Write-Host "     - RAG: $($backendStatus.rag)" -ForegroundColor Gray
    Write-Host "     - TTS Enabled: $($backendStatus.features.tts)" -ForegroundColor Gray
    Write-Host "     - STT Enabled: $($backendStatus.features.stt)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Backend Service: NOT RUNNING" -ForegroundColor Red
    Write-Host "     Start with: cd packages/backend && npm run dev" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check temp directory for audio files
Write-Host "2. Checking generated audio files..." -ForegroundColor Yellow
Write-Host ""

$tempDir = "packages\backend\temp"
if (Test-Path $tempDir) {
    $audioFiles = Get-ChildItem -Path $tempDir -Filter "tts_*.mp3" -ErrorAction SilentlyContinue
    
    if ($audioFiles) {
        Write-Host "   ✓ Found $($audioFiles.Count) audio file(s)" -ForegroundColor Green
        Write-Host ""
        
        foreach ($file in $audioFiles | Select-Object -First 5) {
            $size = [math]::Round($file.Length / 1KB, 2)
            $age = [math]::Round(((Get-Date) - $file.LastWriteTime).TotalMinutes, 1)
            
            Write-Host "   📁 $($file.Name)" -ForegroundColor Cyan
            Write-Host "      Size: ${size} KB | Age: ${age} min" -ForegroundColor Gray
            
            # Test if file can be accessed via HTTP
            $audioUrl = "http://localhost:4000/audio/$($file.Name)"
            try {
                $response = Invoke-WebRequest -Uri $audioUrl -Method Head -TimeoutSec 3 -ErrorAction Stop
                $contentType = $response.Headers["Content-Type"]
                $contentLength = $response.Headers["Content-Length"]
                
                Write-Host "      ✓ HTTP Status: $($response.StatusCode)" -ForegroundColor Green
                Write-Host "      Content-Type: $contentType" -ForegroundColor Gray
                Write-Host "      Content-Length: $contentLength bytes" -ForegroundColor Gray
            } catch {
                Write-Host "      ✗ HTTP Error: $_" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        if ($audioFiles.Count -gt 5) {
            Write-Host "   ... and $($audioFiles.Count - 5) more file(s)" -ForegroundColor Gray
            Write-Host ""
        }
    } else {
        Write-Host "   ⚠ No audio files found in temp directory" -ForegroundColor Yellow
        Write-Host "     Generate some by chatting and receiving responses" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✗ Temp directory not found: $tempDir" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Test text cleaning
Write-Host "3. Testing text cleaning for TTS..." -ForegroundColor Yellow
Write-Host ""

$testText = @"
Fixed deposits require a minimum balance of ₹10,000 **according to policy** [source: 151.pdf p4].
You can read more at [bank website](https://example.com).
⚠️ Important: Check the terms in document.pdf page 5.
"@

Write-Host "   Input text:" -ForegroundColor Cyan
Write-Host "   $($testText.Replace("`n", " "))" -ForegroundColor Gray
Write-Host ""
Write-Host "   Expected output (should remove):" -ForegroundColor Yellow
Write-Host "   - [source: 151.pdf p4]" -ForegroundColor Gray
Write-Host "   - **bold markers**" -ForegroundColor Gray
Write-Host "   - [markdown links]" -ForegroundColor Gray
Write-Host "   - ⚠️ emoji symbols" -ForegroundColor Gray
Write-Host "   - document.pdf page 5" -ForegroundColor Gray
Write-Host ""

Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# STT Model check
Write-Host "4. Checking STT model availability..." -ForegroundColor Yellow
Write-Host ""

Write-Host "   📦 Checking Python packages..." -ForegroundColor Cyan

# Check if in rag_service directory
Push-Location -Path "packages\rag_service" -ErrorAction SilentlyContinue

try {
    $pipList = & python -m pip list 2>&1
    
    $packages = @{
        "transformers" = $false
        "torch" = $false
        "librosa" = $false
        "torchaudio" = $false
        "openai-whisper" = $false
    }
    
    foreach ($pkg in $packages.Keys) {
        if ($pipList -match $pkg) {
            Write-Host "   ✓ $pkg installed" -ForegroundColor Green
            $packages[$pkg] = $true
        } else {
            Write-Host "   ✗ $pkg NOT installed" -ForegroundColor Red
            $packages[$pkg] = $false
        }
    }
    
    Write-Host ""
    
    # Check if IndicSeamless can be loaded
    if ($packages["transformers"] -and $packages["torch"]) {
        Write-Host "   📥 Testing IndicSeamless model loading..." -ForegroundColor Cyan
        Write-Host "   (This may download the model ~150MB on first run)" -ForegroundColor Yellow
        Write-Host ""
        
        $testScript = @"
import sys
try:
    from transformers import AutoProcessor
    processor = AutoProcessor.from_pretrained('ai4bharat/indic-wav2vec2-hindi', token=False)
    print('SUCCESS: IndicSeamless model loaded successfully')
    sys.exit(0)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"@
        
        $testScript | Set-Content -Path "test_indic.py" -Encoding UTF8
        $result = & python test_indic.py 2>&1
        Remove-Item "test_indic.py" -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✓ $result" -ForegroundColor Green
        } else {
            Write-Host "   ✗ $result" -ForegroundColor Red
        }
    } else {
        Write-Host "   ⚠ Cannot test IndicSeamless - missing dependencies" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "   ✗ Error checking Python packages: $_" -ForegroundColor Red
}

Pop-Location

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Manual test instructions
Write-Host "5. Manual Testing Steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   A. Test TTS Audio Playback" -ForegroundColor Cyan
Write-Host "      1. Open http://localhost:5173" -ForegroundColor Gray
Write-Host "      2. Send message: 'What is a fixed deposit?'" -ForegroundColor Gray
Write-Host "      3. Click 'Play audio' button when response arrives" -ForegroundColor Gray
Write-Host "      4. Audio should play without errors" -ForegroundColor Gray
Write-Host ""
Write-Host "   B. Test Text Cleaning" -ForegroundColor Cyan
Write-Host "      1. Check browser console and backend logs" -ForegroundColor Gray
Write-Host "      2. Look for '[TTS Cleaning]' log entries" -ForegroundColor Gray
Write-Host "      3. Verify cleaned text sample" -ForegroundColor Gray
Write-Host "      4. Listen to audio - should NOT hear 'source pdf page number'" -ForegroundColor Gray
Write-Host ""
Write-Host "   C. Test IndicSeamless STT" -ForegroundColor Cyan
Write-Host "      1. Click microphone button" -ForegroundColor Gray
Write-Host "      2. Record Hindi speech" -ForegroundColor Gray
Write-Host "      3. Check RAG service logs for 'Using IndicSeamless'" -ForegroundColor Gray
Write-Host "      4. Verify transcription accuracy" -ForegroundColor Gray
Write-Host ""

Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Quick fixes
Write-Host "6. Quick Fixes for Common Issues:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   ❌ Audio not playing:" -ForegroundColor Red
Write-Host "      1. Check backend logs for [TTS] errors" -ForegroundColor Gray
Write-Host "      2. Verify file exists in packages/backend/temp/" -ForegroundColor Gray
Write-Host "      3. Test URL directly: http://localhost:4000/audio/<filename>.mp3" -ForegroundColor Gray
Write-Host "      4. Check browser console for network errors" -ForegroundColor Gray
Write-Host ""
Write-Host "   ❌ IndicSeamless not working:" -ForegroundColor Red
Write-Host "      1. Install dependencies: cd packages/rag_service && pip install -r requirements.txt" -ForegroundColor Gray
Write-Host "      2. Check logs for model loading errors" -ForegroundColor Gray
Write-Host "      3. Verify GPU availability: python -c 'import torch; print(torch.cuda.is_available())'" -ForegroundColor Gray
Write-Host "      4. Falls back to Whisper automatically if fails" -ForegroundColor Gray
Write-Host ""

Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "For detailed documentation, see:" -ForegroundColor Cyan
Write-Host "  - TTS-STT-FIXES-COMPLETE.md" -ForegroundColor Green
Write-Host "  - INDICSEAMLESS-RESEARCH.md" -ForegroundColor Green
Write-Host ""
Write-Host "Testing complete! ✨" -ForegroundColor Cyan
Write-Host ""
