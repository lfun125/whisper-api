#!/bin/bash
# Download whisper models from Hugging Face

set -e

MODEL=${1:-base}
MODELS_DIR=${MODELS_DIR:-/app/models}

# Available models
MODELS="tiny tiny.en base base.en small small.en medium medium.en large-v1 large-v2 large-v3 large-v3-turbo"

# Check if model is valid
if ! echo "$MODELS" | grep -qw "$MODEL"; then
    echo "Invalid model: $MODEL"
    echo "Available models: $MODELS"
    exit 1
fi

# Create models directory
mkdir -p "$MODELS_DIR"

# Download model
MODEL_FILE="ggml-${MODEL}.bin"
MODEL_PATH="${MODELS_DIR}/${MODEL_FILE}"

if [ -f "$MODEL_PATH" ]; then
    echo "Model $MODEL already exists at $MODEL_PATH"
    exit 0
fi

echo "Downloading model: $MODEL"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
wget -O "$MODEL_PATH" "${BASE_URL}/${MODEL_FILE}"

echo "Model downloaded successfully to $MODEL_PATH"
ls -lh "$MODEL_PATH"
