# RAG Service Index Error - Quick Fix Guide

## Problem

The RAG service is failing with the error:

```
RuntimeError: Index directory not found: index
Run 'python ingest.py' first to create the index.
```

## Root Cause

The RAG service is looking for the FAISS index in the wrong directory. The `INDEX_PATH` environment variable was not set in `docker-compose.yml`, causing it to default to `./index` instead of `/app/data/faiss_index`.

## Solution

### Step 1: Update docker-compose.yml (Already Fixed)

The `docker-compose.yml` has been updated to include the `INDEX_PATH` environment variable:

```yaml
rag_service:
  environment:
    - INDEX_PATH=/app/data/faiss_index
```

### Step 2: Verify Data Exists on EC2

**On your local machine**, check if you have the index files:

```bash
ls -la data/faiss_index/
# Expected files:
# - faiss_index.bin
# - metadata.pkl
# - index_summary.json
```

### Step 3: Copy Index to EC2 (If Missing)

**Option A: Copy from Local Machine**

```bash
# From your local machine (Windows PowerShell or Linux terminal)
scp -i "your-key.pem" -r "d:\Coding\Web development\Production\InfinityPool\CFS (Chatbot From Scratch)\data\faiss_index" ubuntu@your-ec2-ip:~/ifpl-cfs/data/

# Linux/Mac example:
scp -i ~/your-key.pem -r ./data/faiss_index ubuntu@your-ec2-ip:~/ifpl-cfs/data/
```

**Option B: Generate Index on EC2**

```bash
# SSH into EC2
ssh -i "your-key.pem" ubuntu@your-ec2-ip

# Navigate to project
cd ~/ifpl-cfs

# Make sure PDFs are present
ls data/pdfs/

# Generate the index (this will take 5-10 minutes)
docker-compose run --rm rag_service python ingest.py
```

### Step 4: Deploy the Fix

**On EC2 instance:**

```bash
cd ~/ifpl-cfs

# Pull the updated docker-compose.yml
git pull

# Or manually edit docker-compose.yml and add:
# Under rag_service -> environment, add:
#   - INDEX_PATH=/app/data/faiss_index

# Stop current containers
docker-compose down

# Start services with the fix
docker-compose up -d

# Monitor logs
docker-compose logs -f rag_service
```

### Step 5: Verify Fix

```bash
# Check RAG service status
curl http://localhost:8000/status

# Expected response:
# {
#   "status": "ok",
#   "service": "Shankh.ai RAG Service",
#   "index_loaded": true,
#   "num_chunks": 3734
# }

# Test retrieval
curl -X POST http://localhost:8000/retrieve \
  -H "Content-Type: application/json" \
  -d '{"query": "loan eligibility", "k": 3}'
```

## Verification Checklist

- [ ] `data/faiss_index/faiss_index.bin` exists and is > 0 bytes
- [ ] `data/faiss_index/metadata.pkl` exists
- [ ] `data/faiss_index/index_summary.json` exists
- [ ] `docker-compose.yml` has `INDEX_PATH=/app/data/faiss_index`
- [ ] RAG service container starts without errors
- [ ] `/status` endpoint returns `"index_loaded": true`
- [ ] `/retrieve` endpoint returns search results

## Alternative: Use Verification Script

We've created a script to check everything automatically:

```bash
# On EC2 instance
cd ~/ifpl-cfs
./verify-rag-data.sh
```

This script will:

- Check if all required directories exist
- Verify FAISS index files are present
- Display index statistics
- Provide helpful error messages if anything is missing

## Expected Timeline

- **With existing index**: 2-3 minutes (copy + restart)
- **Generate new index**: 10-15 minutes (depends on PDF count)

## Common Issues

### Issue 1: "Permission denied" when copying files

```bash
# Fix permissions on EC2
sudo chown -R ubuntu:ubuntu ~/ifpl-cfs/data
```

### Issue 2: Container keeps restarting

```bash
# Check detailed logs
docker-compose logs --tail=100 rag_service

# Inspect container
docker-compose exec rag_service ls -la /app/data/faiss_index/
```

### Issue 3: Index files are corrupted

```bash
# Regenerate the index
docker-compose run --rm rag_service python ingest.py
```

## Production Checklist

After fixing, ensure:

- [ ] Backend can connect to RAG service
- [ ] Frontend can retrieve search results
- [ ] Chatbot can answer questions using RAG
- [ ] Citations are displayed correctly
- [ ] No errors in logs for 5 minutes

## Need Help?

If the issue persists:

1. Share the output of: `docker-compose logs rag_service`
2. Share the output of: `ls -lah data/faiss_index/`
3. Share the output of: `docker-compose exec rag_service env | grep INDEX`

---

**Last Updated**: October 31, 2025
**Status**: Tested on EC2 Ubuntu 22.04 LTS
