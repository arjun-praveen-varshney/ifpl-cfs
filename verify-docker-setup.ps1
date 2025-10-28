# Docker Setup Verification Script for CFS Chatbot
# Run this before AWS deployment to ensure everything is ready

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  CFS Chatbot - Docker Setup Verification" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Function to print status
function Print-Status {
    param($message, $status)
    if ($status) {
        Write-Host "[✓] $message" -ForegroundColor Green
    } else {
        Write-Host "[✗] $message" -ForegroundColor Red
    }
}

# 1. Check Docker installation
Write-Host "1. Checking Docker installation..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Print-Status "Docker installed: $dockerVersion" $true
} catch {
    Print-Status "Docker not installed or not in PATH" $false
    Write-Host "   Install from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit 1
}

# 2. Check Docker Compose
Write-Host "`n2. Checking Docker Compose..." -ForegroundColor Yellow
try {
    $composeVersion = docker-compose --version
    Print-Status "Docker Compose installed: $composeVersion" $true
} catch {
    Print-Status "Docker Compose not installed" $false
    exit 1
}

# 3. Check if Docker is running
Write-Host "`n3. Checking Docker daemon..." -ForegroundColor Yellow
try {
    docker ps > $null 2>&1
    Print-Status "Docker daemon is running" $true
} catch {
    Print-Status "Docker daemon not running - Please start Docker Desktop" $false
    exit 1
}

# 4. Check docker-compose.yml exists
Write-Host "`n4. Checking docker-compose.yml..." -ForegroundColor Yellow
if (Test-Path "docker-compose.yml") {
    Print-Status "docker-compose.yml found" $true
} else {
    Print-Status "docker-compose.yml not found in current directory" $false
    exit 1
}

# 5. Check Dockerfiles
Write-Host "`n5. Checking Dockerfiles..." -ForegroundColor Yellow
$frontendDockerfile = Test-Path "packages/frontend/Dockerfile"
$backendDockerfile = Test-Path "packages/backend/Dockerfile"
$ragDockerfile = Test-Path "packages/rag_service/Dockerfile"

Print-Status "Frontend Dockerfile exists" $frontendDockerfile
Print-Status "Backend Dockerfile exists" $backendDockerfile
Print-Status "RAG Service Dockerfile exists" $ragDockerfile

if (-not ($frontendDockerfile -and $backendDockerfile -and $ragDockerfile)) {
    Write-Host "   Missing Dockerfiles - Cannot proceed" -ForegroundColor Red
    exit 1
}

# 6. Check environment files
Write-Host "`n6. Checking environment configuration..." -ForegroundColor Yellow
$backendEnv = Test-Path "packages/backend/.env"
Print-Status "Backend .env file exists" $backendEnv

if ($backendEnv) {
    $envContent = Get-Content "packages/backend/.env" -Raw
    
    # Check critical environment variables
    $hasGemini = $envContent -match "GEMINI_API_KEY=.+"
    $hasDeepSeek = $envContent -match "DEEPSEEK_API_KEY=.+"
    $hasLLMProvider = $envContent -match "LLM_PROVIDER=gemini"
    
    Print-Status "Gemini API key configured" $hasGemini
    Print-Status "DeepSeek API key configured" $hasDeepSeek
    Print-Status "LLM provider set to Gemini" $hasLLMProvider
    
    if (-not ($hasGemini -and $hasLLMProvider)) {
        Write-Host "   WARNING: Critical API keys missing!" -ForegroundColor Red
    }
}

# 7. Check data directory
Write-Host "`n7. Checking data directory..." -ForegroundColor Yellow
$dataDir = Test-Path "data"
Print-Status "data directory exists" $dataDir

if ($dataDir) {
    $faissIndex = Test-Path "data/faiss_index"
    $pdfsDir = Test-Path "data/pdfs"
    Print-Status "FAISS index directory exists" $faissIndex
    Print-Status "PDFs directory exists" $pdfsDir
}

# 8. Test Docker build (dry-run)
Write-Host "`n8. Testing Docker Compose configuration..." -ForegroundColor Yellow
try {
    docker-compose config > $null 2>&1
    Print-Status "docker-compose.yml syntax is valid" $true
} catch {
    Print-Status "docker-compose.yml has syntax errors" $false
    Write-Host "   Run 'docker-compose config' to see details" -ForegroundColor Yellow
}

# 9. Check disk space
Write-Host "`n9. Checking disk space..." -ForegroundColor Yellow
$drive = Get-PSDrive -Name (Get-Location).Drive.Name
$freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
$hasEnoughSpace = $freeSpaceGB -gt 5

Print-Status "Free disk space: $freeSpaceGB GB" $hasEnoughSpace

if (-not $hasEnoughSpace) {
    Write-Host "   WARNING: Low disk space. Docker images need ~5GB" -ForegroundColor Yellow
}

# 10. Check port availability
Write-Host "`n10. Checking port availability..." -ForegroundColor Yellow

function Test-Port {
    param($port)
    try {
        $connection = Test-NetConnection -ComputerName localhost -Port $port -WarningAction SilentlyContinue
        return -not $connection.TcpTestSucceeded
    } catch {
        return $true
    }
}

$port5173 = Test-Port 5173
$port4000 = Test-Port 4000
$port8000 = Test-Port 8000

Print-Status "Port 5173 (Frontend) available" $port5173
Print-Status "Port 4000 (Backend) available" $port4000
Print-Status "Port 8000 (RAG Service) available" $port8000

if (-not ($port5173 -and $port4000 -and $port8000)) {
    Write-Host "   Some ports are in use. Stop conflicting services or change ports in docker-compose.yml" -ForegroundColor Yellow
}

# Summary
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "  Verification Summary" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$allChecks = $true

if ($dockerVersion -and $composeVersion -and $frontendDockerfile -and $backendDockerfile -and $ragDockerfile -and $backendEnv) {
    Write-Host "`n✓ All critical checks passed!" -ForegroundColor Green
    Write-Host "`nReady for Docker deployment!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Build images:  docker-compose build" -ForegroundColor White
    Write-Host "  2. Start services: docker-compose up -d" -ForegroundColor White
    Write-Host "  3. View logs:     docker-compose logs -f" -ForegroundColor White
    Write-Host "  4. Check status:  docker-compose ps" -ForegroundColor White
    Write-Host "`nFor AWS deployment, see: AWS-DEPLOYMENT-GUIDE.md" -ForegroundColor Cyan
} else {
    Write-Host "`n✗ Some checks failed. Please fix issues before deployment." -ForegroundColor Red
    exit 1
}

Write-Host ""
