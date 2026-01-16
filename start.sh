#!/bin/bash
# Whisper API Startup Script

set -e

# Configuration
MODEL=${MODEL:-base}
MODELS_DIR="./models"

echo "=========================================="
echo "  Whisper.cpp API Server"
echo "=========================================="

# Create models directory
mkdir -p "$MODELS_DIR"

# Check if model exists, download if not
MODEL_FILE="${MODELS_DIR}/ggml-${MODEL}.bin"
if [ ! -f "$MODEL_FILE" ]; then
    echo ""
    echo "Model '$MODEL' not found. Downloading..."
    echo "This may take a few minutes depending on your connection."
    echo ""
    
    BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    wget -O "$MODEL_FILE" "${BASE_URL}/ggml-${MODEL}.bin" || {
        echo "Failed to download model. Please download manually:"
        echo "  wget -O $MODEL_FILE ${BASE_URL}/ggml-${MODEL}.bin"
        exit 1
    }
    echo ""
    echo "Model downloaded successfully!"
fi

echo ""
echo "Using model: $MODEL"
echo "Model file: $MODEL_FILE"
echo ""

# Build and start Docker containers
echo "Building Docker image..."
docker-compose build

echo ""
echo "Starting Whisper API server..."
docker-compose up -d

echo ""
echo "=========================================="
echo "  Server is starting..."
echo "=========================================="
echo ""
echo "API Endpoints:"
echo "  - Health:      http://localhost:8000/health"
echo "  - API Docs:    http://localhost:8000/docs"
echo "  - Transcribe:  POST http://localhost:8000/transcribe"
echo "  - OpenAI API:  POST http://localhost:8000/v1/audio/transcriptions"
echo ""
echo "Usage Examples:"
echo ""
echo "  # Transcribe audio file"
echo "  curl -X POST http://localhost:8000/transcribe \\"
echo "    -F 'file=@audio.wav'"
echo ""
echo "  # With specific model and language"
echo "  curl -X POST http://localhost:8000/transcribe \\"
echo "    -F 'file=@audio.mp3' \\"
echo "    -F 'model=small' \\"
echo "    -F 'language=zh'"
echo ""
echo "  # OpenAI-compatible API"
echo "  curl -X POST http://localhost:8000/v1/audio/transcriptions \\"
echo "    -F 'file=@audio.wav' \\"
echo "    -F 'model=whisper-1'"
echo ""
echo "View logs: docker-compose logs -f"
echo "Stop server: docker-compose down"
echo ""
