#!/bin/bash
# Verify RAG service data is properly set up

echo "======================================================================"
echo "  RAG Service Data Verification Script"
echo "======================================================================"
echo ""

# Check if data directory exists
if [ ! -d "data" ]; then
    echo "❌ Error: 'data' directory not found in current location"
    echo "   Current directory: $(pwd)"
    echo "   Please run this script from the project root"
    exit 1
fi

echo "✓ Found 'data' directory"
echo ""

# Check PDF directory
echo "Checking PDF files..."
if [ ! -d "data/pdfs" ]; then
    echo "❌ Error: data/pdfs directory not found"
    exit 1
fi

pdf_count=$(find data/pdfs -name "*.pdf" | wc -l)
echo "✓ Found $pdf_count PDF files in data/pdfs/"
echo ""

# Check FAISS index directory
echo "Checking FAISS index..."
if [ ! -d "data/faiss_index" ]; then
    echo "❌ Error: data/faiss_index directory not found"
    echo "   You need to generate the FAISS index first!"
    echo ""
    echo "   Options:"
    echo "   1. Copy the index from your local machine:"
    echo "      scp -i your-key.pem -r data/faiss_index ubuntu@your-ec2-ip:~/ifpl-cfs/data/"
    echo ""
    echo "   2. Generate index on EC2 (requires PDFs to be present):"
    echo "      docker-compose run --rm rag_service python ingest.py"
    exit 1
fi

echo "✓ Found data/faiss_index directory"

# Check required files
required_files=("faiss_index.bin" "metadata.pkl" "index_summary.json")
all_present=true

for file in "${required_files[@]}"; do
    if [ -f "data/faiss_index/$file" ]; then
        size=$(du -h "data/faiss_index/$file" | cut -f1)
        echo "  ✓ $file ($size)"
    else
        echo "  ❌ Missing: $file"
        all_present=false
    fi
done

echo ""

if [ "$all_present" = false ]; then
    echo "❌ Some required index files are missing"
    echo "   Run: docker-compose run --rm rag_service python ingest.py"
    exit 1
fi

# Check index summary for statistics
if [ -f "data/faiss_index/index_summary.json" ]; then
    echo "Index Statistics:"
    cat data/faiss_index/index_summary.json | python3 -m json.tool 2>/dev/null || cat data/faiss_index/index_summary.json
    echo ""
fi

echo "======================================================================"
echo "✅ All RAG service data is properly configured!"
echo "======================================================================"
echo ""
echo "You can now start the services:"
echo "  docker-compose up -d"
echo ""
echo "To verify RAG service is running:"
echo "  curl http://localhost:8000/status"
