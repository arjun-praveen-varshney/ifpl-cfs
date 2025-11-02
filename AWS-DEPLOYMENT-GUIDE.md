# AWS Deployment Guide for CFS (Chatbot From Scratch)

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Deployment Options](#deployment-options)
4. [Option 1: EC2 with Docker Compose (Recommended)](#option-1-ec2-with-docker-compose)
5. [Option 2: AWS ECS (Elastic Container Service)](#option-2-aws-ecs)
6. [Option 3: AWS App Runner (Simplified)](#option-3-aws-app-runner)
7. [Environment Configuration](#environment-configuration)
8. [Domain & SSL Setup](#domain--ssl-setup)
9. [Monitoring & Logging](#monitoring--logging)
10. [Cost Optimization](#cost-optimization)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### 1. AWS Account Setup

- Active AWS account with billing enabled
- IAM user with necessary permissions (EC2, ECS, RDS, S3, CloudWatch)
- AWS CLI installed locally: `pip install awscli`
- AWS credentials configured: `aws configure`

### 2. Local Requirements

- Docker installed and running
- Docker Compose installed
- SSH key pair for EC2 access
- Domain name (optional but recommended)

### 3. API Keys Required

- **Google Gemini API Key** (Primary LLM)
- **DeepSeek API Key** (Fallback LLM)
- OpenAI, Claude, OpenRouter keys (optional)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  AWS Cloud                       │
│                                                  │
│  ┌─────────────────────────────────────────┐   │
│  │         Application Load Balancer        │   │
│  │         (Port 80/443 - SSL/TLS)          │   │
│  └──────────────┬──────────────────────────┘   │
│                 │                                │
│  ┌──────────────▼──────────────────────────┐   │
│  │           EC2 Instance                   │   │
│  │        (t3.medium or t3.large)           │   │
│  │                                           │   │
│  │  ┌─────────────────────────────────┐    │   │
│  │  │  Frontend (React + Vite)        │    │   │
│  │  │  Port 5173 → 80                 │    │   │
│  │  └─────────────────────────────────┘    │   │
│  │                                           │   │
│  │  ┌─────────────────────────────────┐    │   │
│  │  │  Backend (Node.js + Express)    │    │   │
│  │  │  Port 4000                       │    │   │
│  │  └─────────────────────────────────┘    │   │
│  │                                           │   │
│  │  ┌─────────────────────────────────┐    │   │
│  │  │  RAG Service (Python + FastAPI) │    │   │
│  │  │  Port 8000                       │    │   │
│  │  └─────────────────────────────────┘    │   │
│  │                                           │   │
│  │  ┌─────────────────────────────────┐    │   │
│  │  │  EBS Volume (Persistent)        │    │   │
│  │  │  - FAISS Index (3,734 chunks)   │    │   │
│  │  │  - PDF Files (887 pages)        │    │   │
│  │  │  - Audio temp files             │    │   │
│  │  └─────────────────────────────────┘    │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │   CloudWatch (Logs & Metrics)            │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │   AWS Secrets Manager (API Keys)         │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## Deployment Options

### Comparison Table

| Feature              | EC2 + Docker Compose     | AWS ECS             | AWS App Runner   |
| -------------------- | ------------------------ | ------------------- | ---------------- |
| **Setup Complexity** | Medium                   | High                | Low              |
| **Cost**             | $30-60/month             | $50-100/month       | $40-80/month     |
| **Scalability**      | Manual                   | Auto                | Auto             |
| **Management**       | Full control             | Managed             | Fully managed    |
| **Best For**         | Small-medium teams       | Production at scale | Quick deployment |
| **Recommended**      | ✅ Yes (Budget friendly) | For scaling         | For simplicity   |

---

## Option 1: EC2 with Docker Compose (Recommended)

### Step 1: Launch EC2 Instance

1. **Login to AWS Console** → Navigate to EC2

2. **Launch Instance**:

   ```
   Name: cfs-chatbot-server
   AMI: Ubuntu Server 22.04 LTS (Free Tier eligible)
   Instance Type: t3.medium (2 vCPU, 4GB RAM)
                  OR t3.large (2 vCPU, 8GB RAM) for better performance
   Key Pair: Create new or use existing SSH key
   ```

3. **Configure Security Group**:

   ```
   Inbound Rules:
   - SSH (22)         - Source: Your IP only
   - HTTP (80)        - Source: 0.0.0.0/0 (Anywhere)
   - HTTPS (443)      - Source: 0.0.0.0/0 (Anywhere)
   - Custom TCP (5173) - Source: 0.0.0.0/0 (Frontend dev)
   - Custom TCP (4000) - Source: 0.0.0.0/0 (Backend API)
   ```

4. **Configure Storage**:

   ```
   Root Volume: 30 GB gp3 (General Purpose SSD)
   Additional Volume: 20 GB gp3 (For FAISS index & PDFs)
   ```

5. **Launch Instance** and note the Public IP address

### Step 2: Connect to EC2 Instance

```bash
# Windows (PowerShell)
ssh -i "path\to\your-key.pem" ubuntu@your-ec2-public-ip

# Example:
ssh -i "C:\Users\YourName\.ssh\cfs-key.pem" ubuntu@54.123.45.67
```

### Step 3: Install Docker & Docker Compose

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group (avoid sudo)
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installations
docker --version
docker-compose --version
```

### Step 4: Clone Your Project

```bash
# Install Git
sudo apt install -y git

# Clone repository (replace with your repo URL)
cd ~
git clone https://github.com/yourusername/cfs-chatbot.git
cd cfs-chatbot

# OR upload via SCP from local machine:
# scp -i "your-key.pem" -r "d:\Coding\Web development\Production\InfinityPool\CFS (Chatbot From Scratch)" ubuntu@your-ec2-ip:~/cfs-chatbot
```

### Step 5: Configure Environment Variables

```bash
cd ~/cfs-chatbot

# Create production .env file
nano packages/backend/.env
```

**Production `.env` configuration:**

```env
# Server Configuration
NODE_ENV=production
PORT=4000
HOST=0.0.0.0

# CORS - Update with your domain
CORS_ORIGINS=http://your-domain.com,https://your-domain.com,http://your-ec2-ip:5173

# API Keys
GEMINI_API_KEY=your_gemini_api_key_here
GEMINI_MODEL=gemini-2.5-flash
DEEPSEEK_API_KEY=your_deepseek_api_key_here
OPENAI_API_KEY=your_openai_key_optional
ANTHROPIC_API_KEY=your_anthropic_key_optional

# LLM Configuration
LLM_PROVIDER=gemini
LLM_FALLBACK=deepseek

# RAG Service
RAG_SERVICE_URL=http://rag_service:8000

# Feature Flags
ENABLE_STT=true
ENABLE_TTS=true
ENABLE_RAG=true

# Session Management
SESSION_MAX_HISTORY=20
SESSION_TIMEOUT=1800000

# File Upload
MAX_AUDIO_SIZE=10485760
TEMP_DIR=/app/temp

# Rate Limiting
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100
```

**Save and exit**: `Ctrl+X`, `Y`, `Enter`

### Step 6: Update docker-compose.yml for Production

```bash
nano docker-compose.yml
```

**Updated docker-compose.yml:**

```yaml
version: "3.8"

services:
  frontend:
    build: ./packages/frontend
    ports:
      - "5173:80" # Map to port 80 inside container
    environment:
      - VITE_API_URL=http://your-ec2-ip:4000
      - VITE_WS_URL=ws://your-ec2-ip:4000
    depends_on:
      - backend
    restart: unless-stopped
    networks:
      - cfs-network

  backend:
    build: ./packages/backend
    ports:
      - "4000:4000"
    environment:
      - NODE_ENV=production
    env_file:
      - ./packages/backend/.env
    volumes:
      - backend-temp:/app/temp
      - backend-data:/app/data
    depends_on:
      - rag_service
    restart: unless-stopped
    networks:
      - cfs-network
  rag_service:
    build: ./packages/rag_service
    ports:
      - "8000:8000"
    volumes:
      - ./data/pdfs:/app/data/pdfs
      - ./data/faiss_index:/app/data/faiss_index
    environment:
      - PYTHONUNBUFFERED=1
      - INDEX_PATH=/app/data/faiss_index
      - EMBEDDING_MODEL=paraphrase-multilingual-mpnet-base-v2
    restart: unless-stopped
    networks:
      - cfs-network

volumes:
  backend-temp:
  backend-data:

networks:
  cfs-network:
    driver: bridge
```

**Save**: `Ctrl+X`, `Y`, `Enter`

### Step 7: Build and Deploy

```bash
# Navigate to project directory
cd ~/cfs-chatbot

# Build Docker images (first time will take 5-10 minutes)
docker-compose build

# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f

# To view specific service logs:
docker-compose logs -f backend
docker-compose logs -f rag_service
```

### Step 8: Verify Deployment

```bash
# Test backend health
curl http://localhost:4000/health

# Test RAG service
curl http://localhost:8000/health

# Test frontend (from browser)
# Open: http://your-ec2-public-ip:5173
```

### Step 9: Setup Systemd Service (Auto-restart on reboot)

```bash
# Create systemd service file
sudo nano /etc/systemd/system/cfs-chatbot.service
```

**Service configuration:**

```ini
[Unit]
Description=CFS Chatbot Docker Compose Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/ubuntu/cfs-chatbot
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

**Enable and start:**

```bash
sudo systemctl enable cfs-chatbot
sudo systemctl start cfs-chatbot
sudo systemctl status cfs-chatbot
```

---

## Option 2: AWS ECS (Elastic Container Service)

### When to Use ECS

- Need auto-scaling based on traffic
- Production environment with high availability
- Want AWS-managed infrastructure

### Quick Setup Steps

1. **Push Docker Images to ECR (Elastic Container Registry)**

```bash
# Install AWS CLI
pip install awscli

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin your-account-id.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repositories
aws ecr create-repository --repository-name cfs-frontend
aws ecr create-repository --repository-name cfs-backend
aws ecr create-repository --repository-name cfs-rag

# Tag and push images
docker tag cfs-frontend:latest your-account-id.dkr.ecr.us-east-1.amazonaws.com/cfs-frontend:latest
docker push your-account-id.dkr.ecr.us-east-1.amazonaws.com/cfs-frontend:latest

# Repeat for backend and rag_service
```

2. **Create ECS Cluster**

   - Navigate to ECS Console
   - Create Cluster → Choose "EC2 Linux + Networking"
   - Name: `cfs-cluster`
   - Instance type: `t3.medium`

3. **Create Task Definitions**

   - Define CPU, memory, container images
   - Configure environment variables
   - Set port mappings

4. **Create Services**
   - 1 service per container (frontend, backend, rag)
   - Configure load balancer
   - Set auto-scaling rules

**Cost**: ~$50-100/month depending on traffic

---

## Option 3: AWS App Runner (Simplified)

### When to Use App Runner

- Want quickest deployment
- Don't need fine-grained control
- Pay only for what you use

### Quick Setup

1. **Prepare GitHub Repository** with your code

2. **AWS Console** → App Runner → Create Service

3. **Configure**:

   ```
   Source: GitHub repository
   Branch: main
   Build Settings: Use docker-compose.yml
   Instance Configuration: 1 vCPU, 2 GB RAM
   Auto Scaling: Min 1, Max 3 instances
   ```

4. **Deploy** - App Runner automatically builds and deploys

**Cost**: ~$40-80/month with auto-scaling

---

## Environment Configuration

### Production Environment Variables

#### Backend (.env)

```env
NODE_ENV=production
PORT=4000
HOST=0.0.0.0

# CORS
CORS_ORIGINS=https://yourdomain.com,https://www.yourdomain.com

# API Keys (Use AWS Secrets Manager)
GEMINI_API_KEY=${GEMINI_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_KEY}

# Services
RAG_SERVICE_URL=http://rag_service:8000

# Security
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100
```

#### Frontend (vite.config.js)

```javascript
export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": {
        target: process.env.VITE_API_URL || "http://localhost:4000",
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: "dist",
    sourcemap: false, // Disable in production
  },
});
```

### AWS Secrets Manager (Recommended)

```bash
# Install AWS CLI
pip install awscli

# Create secrets
aws secretsmanager create-secret \
  --name cfs-gemini-key \
  --secret-string "your_gemini_api_key"

aws secretsmanager create-secret \
  --name cfs-deepseek-key \
  --secret-string "your_deepseek_api_key"

# Retrieve in application (Node.js example)
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager({region: 'us-east-1'});

async function getSecret(secretName) {
  const data = await secretsManager.getSecretValue({SecretId: secretName}).promise();
  return data.SecretString;
}
```

---

## Domain & SSL Setup

### Step 1: Configure Domain (Route 53)

1. **Register Domain** (or transfer existing)

   - AWS Route 53 → Register Domain
   - Cost: ~$12/year for .com

2. **Create Hosted Zone**

   - Route 53 → Hosted Zones → Create
   - Note the nameservers

3. **Create DNS Records**:

   ```
   Type: A Record
   Name: @ (root domain)
   Value: Your EC2 Elastic IP
   TTL: 300

   Type: A Record
   Name: www
   Value: Your EC2 Elastic IP
   TTL: 300
   ```

### Step 2: Setup SSL Certificate (Let's Encrypt)

**Install Certbot on EC2:**

```bash
sudo apt update
sudo apt install -y certbot python3-certbot-nginx

# Install Nginx
sudo apt install -y nginx

# Configure Nginx reverse proxy
sudo nano /etc/nginx/sites-available/cfs-chatbot
```

**Nginx configuration:**

```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    # Frontend
    location / {
        proxy_pass http://localhost:5173;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Backend API
    location /api {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # WebSocket
    location /socket.io {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Enable site and get SSL:**

```bash
sudo ln -s /etc/nginx/sites-available/cfs-chatbot /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Get SSL certificate
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

**Auto-renewal:**

```bash
sudo certbot renew --dry-run
```

---

## Monitoring & Logging

### CloudWatch Logs

1. **Install CloudWatch Agent on EC2**:

```bash
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
```

2. **Configure agent**:

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

3. **View logs**:
   - AWS Console → CloudWatch → Logs
   - Create log groups for each service

### Application Monitoring

**Docker logs:**

```bash
# View all logs
docker-compose logs -f

# View last 100 lines
docker-compose logs --tail=100

# View specific service
docker-compose logs -f backend

# Export logs to file
docker-compose logs > logs.txt
```

### Performance Monitoring

**Setup CloudWatch metrics:**

```bash
# CPU, Memory, Disk usage
aws cloudwatch put-metric-data \
  --namespace CFS/Chatbot \
  --metric-name CPUUtilization \
  --value 75.0
```

---

## Cost Optimization

### Monthly Cost Breakdown (EC2 Option)

| Resource            | Specification           | Cost/Month     |
| ------------------- | ----------------------- | -------------- |
| **EC2 Instance**    | t3.medium (2 vCPU, 4GB) | $30            |
| **EBS Storage**     | 50 GB gp3 SSD           | $4             |
| **Elastic IP**      | 1 static IP             | $3.60          |
| **Data Transfer**   | 10 GB outbound          | $0.90          |
| **CloudWatch**      | Basic monitoring        | $2             |
| **Route 53**        | Hosted zone + domain    | $1.50          |
| **SSL Certificate** | Let's Encrypt (Free)    | $0             |
| **Total**           |                         | **~$42/month** |

### Cost Saving Tips

1. **Use Reserved Instances** (Save 30-50%)

   - 1-year commitment: $20/month instead of $30
   - 3-year commitment: $13/month

2. **Auto Shutdown** non-production environments

   ```bash
   # Stop instance at night (8 PM - 8 AM)
   # CloudWatch Events + Lambda function
   ```

3. **Use Spot Instances** for development (Save 70%)

4. **Compress data transfer** (Gzip enabled in Nginx)

5. **Clean old logs and temp files**:
   ```bash
   # Add to crontab
   0 2 * * * docker exec cfs-backend rm -f /app/temp/*.mp3
   0 3 * * * docker system prune -f
   ```

---

## Troubleshooting

### Common Issues

#### 1. Containers not starting

```bash
# Check logs
docker-compose logs

# Rebuild images
docker-compose build --no-cache
docker-compose up -d
```

#### 2. Out of memory

```bash
# Check memory usage
docker stats

# Increase swap space
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

#### 3. SSL certificate issues

```bash
# Renew manually
sudo certbot renew

# Check expiry
sudo certbot certificates
```

#### 4. Port conflicts

```bash
# Check what's using port
sudo lsof -i :4000

# Kill process
sudo kill -9 <PID>
```

#### 5. RAG service slow

```bash
# Increase Python workers in Dockerfile
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

#### 6. RAG service fails with "Index directory not found"

This happens when the FAISS index path is misconfigured:

```bash
# Check if index exists on host
ls -la data/faiss_index/

# Verify the files are present
# Expected: faiss_index.bin, metadata.pkl, index_summary.json

# If files are missing, you need to generate them first
docker-compose exec rag_service python ingest.py

# If files exist but RAG service still fails, check docker-compose.yml
# Ensure INDEX_PATH environment variable is set correctly:
# environment:
#   - INDEX_PATH=/app/data/faiss_index

# Restart the RAG service
docker-compose restart rag_service
```

**Note**: The RAG service expects the FAISS index to be pre-generated. If you're deploying for the first time, make sure to:

1. Copy your local `data/faiss_index/` directory to the EC2 instance
2. Or run the ingest script inside the container to generate the index

```bash
# Generate index from PDFs (one-time setup)
docker-compose exec rag_service python ingest.py
```

### Health Checks

```bash
# Backend
curl http://localhost:4000/health

# RAG Service
curl http://localhost:8000/health

# Frontend (from browser)
http://your-domain.com

# Check Docker containers
docker ps -a

# Restart specific service
docker-compose restart backend
```

---

## Deployment Checklist

- [ ] AWS Account setup with billing
- [ ] EC2 instance launched (t3.medium minimum)
- [ ] Security groups configured (ports 80, 443, 4000, 8000)
- [ ] SSH key pair created and saved
- [ ] Docker & Docker Compose installed
- [ ] Project code uploaded to EC2
- [ ] Environment variables configured (.env file)
- [ ] docker-compose.yml updated for production
- [ ] Docker images built successfully
- [ ] All containers running (`docker ps`)
- [ ] Backend health check passing
- [ ] RAG service responding
- [ ] Frontend accessible in browser
- [ ] Domain DNS configured (if using domain)
- [ ] SSL certificate installed (if using HTTPS)
- [ ] Nginx reverse proxy configured
- [ ] CloudWatch logging enabled
- [ ] Systemd service created for auto-restart
- [ ] Backup strategy implemented
- [ ] Monitoring alerts configured
- [ ] Load testing completed
- [ ] Documentation updated with production URLs

---

## Next Steps

1. **Test the deployment**:

   - Ask questions in the chatbot
   - Test voice input/output
   - Verify stock price queries
   - Check RAG citations

2. **Monitor performance**:

   - CloudWatch dashboard
   - Application logs
   - Error tracking

3. **Setup backups**:

   - FAISS index snapshots
   - PDF files backup to S3
   - Database backups (if added later)

4. **Implement CI/CD** (GitHub Actions):
   ```yaml
   # .github/workflows/deploy.yml
   name: Deploy to AWS
   on:
     push:
       branches: [main]
   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - name: Deploy to EC2
           run: |
             ssh ubuntu@${{ secrets.EC2_IP }} "cd ~/cfs-chatbot && git pull && docker-compose up -d --build"
   ```

---

## Support & Resources

- **AWS Documentation**: https://docs.aws.amazon.com/
- **Docker Documentation**: https://docs.docker.com/
- **Nginx Configuration**: https://nginx.org/en/docs/
- **Let's Encrypt**: https://letsencrypt.org/

---

## Estimated Total Setup Time

- EC2 Instance Setup: 30 minutes
- Docker Installation: 15 minutes
- Code Deployment: 20 minutes
- First Build: 10 minutes
- Testing: 15 minutes
- Domain/SSL Setup: 30 minutes (optional)

**Total**: ~2 hours for complete production deployment

---

**🎉 Congratulations!** Your CFS Chatbot is now live on AWS!

Access your chatbot at:

- Development: `http://your-ec2-ip:5173`
- Production: `https://yourdomain.com` (with SSL)
