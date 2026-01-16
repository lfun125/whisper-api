#!/usr/bin/env python3
"""
Whisper.cpp API Server
A FastAPI-based REST API for speech-to-text transcription using whisper.cpp
"""

import os
import uuid
import subprocess
import tempfile
import json
import asyncio
from pathlib import Path
from typing import Optional
from datetime import datetime

from fastapi import FastAPI, File, UploadFile, HTTPException, Form, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI(
    title="Whisper.cpp API",
    description="Speech-to-text API powered by whisper.cpp",
    version="1.0.0"
)

# Configuration
MODELS_DIR = Path(os.getenv("MODELS_DIR", "/app/models"))
UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
TEMP_DIR = Path(os.getenv("TEMP_DIR", "/app/temp"))
DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "base")
WHISPER_CLI = os.getenv("WHISPER_CLI", "/usr/local/bin/whisper-cli")
WHISPER_THREADS = int(os.getenv("WHISPER_THREADS", "4"))  # CPU threads

# Ensure directories exist
MODELS_DIR.mkdir(parents=True, exist_ok=True)
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
TEMP_DIR.mkdir(parents=True, exist_ok=True)

# Supported audio formats
SUPPORTED_FORMATS = {".wav", ".mp3", ".m4a", ".ogg", ".flac", ".webm", ".mp4", ".mpeg", ".mpga"}

# Available models
AVAILABLE_MODELS = [
    "tiny", "tiny.en",
    "base", "base.en",
    "small", "small.en",
    "medium", "medium.en",
    "large-v1", "large-v2", "large-v3", "large-v3-turbo"
]


class TranscriptionResponse(BaseModel):
    """Response model for transcription"""
    text: str
    language: Optional[str] = None
    duration: Optional[float] = None
    segments: Optional[list] = None


class ModelInfo(BaseModel):
    """Model information"""
    name: str
    path: str
    size_mb: float
    available: bool


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}


@app.get("/models")
async def list_models():
    """List available models"""
    models = []
    for model_name in AVAILABLE_MODELS:
        model_path = MODELS_DIR / f"ggml-{model_name}.bin"
        if model_path.exists():
            size_mb = model_path.stat().st_size / (1024 * 1024)
            models.append(ModelInfo(
                name=model_name,
                path=str(model_path),
                size_mb=round(size_mb, 2),
                available=True
            ))
        else:
            models.append(ModelInfo(
                name=model_name,
                path=str(model_path),
                size_mb=0,
                available=False
            ))
    return {"models": models}


@app.post("/transcribe", response_model=TranscriptionResponse)
async def transcribe_audio(
    file: UploadFile = File(..., description="Audio file to transcribe"),
    model: Optional[str] = Form(default=None, description="Model name (e.g., base, small, medium)"),
    language: Optional[str] = Form(default=None, description="Language code (e.g., en, zh, ja) or 'auto' for detection"),
    task: str = Form(default="transcribe", description="Task: 'transcribe' or 'translate'"),
    output_format: str = Form(default="text", description="Output format: text, json, srt, vtt"),
    word_timestamps: bool = Form(default=False, description="Include word-level timestamps"),
):
    """
    Transcribe audio file to text
    
    Supports: wav, mp3, m4a, ogg, flac, webm, mp4
    """
    # Validate file extension
    filename = file.filename or "audio.wav"
    file_ext = Path(filename).suffix.lower()
    if file_ext not in SUPPORTED_FORMATS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format: {file_ext}. Supported: {', '.join(SUPPORTED_FORMATS)}"
        )
    
    # Use default model if not specified
    if model is None:
        model = DEFAULT_MODEL
    
    # Validate model
    model_path = MODELS_DIR / f"ggml-{model}.bin"
    if not model_path.exists():
        available = [m.name for m in (await list_models())["models"] if m.available]
        raise HTTPException(
            status_code=400,
            detail=f"Model '{model}' not found. Available models: {available}"
        )
    
    # Create temporary files
    request_id = str(uuid.uuid4())
    input_path = TEMP_DIR / f"{request_id}_input{file_ext}"
    wav_path = TEMP_DIR / f"{request_id}.wav"
    output_path = TEMP_DIR / f"{request_id}_output"
    
    try:
        # Save uploaded file
        content = await file.read()
        with open(input_path, "wb") as f:
            f.write(content)
        
        # Convert to 16kHz mono WAV (required by whisper.cpp)
        ffmpeg_cmd = [
            "ffmpeg", "-y", "-i", str(input_path),
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            str(wav_path)
        ]
        
        process = await asyncio.create_subprocess_exec(
            *ffmpeg_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        _, stderr = await process.communicate()
        
        if process.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"Failed to convert audio: {stderr.decode()}"
            )
        
        # Build whisper command
        whisper_cmd = [
            WHISPER_CLI,
            "-m", str(model_path),
            "-f", str(wav_path),
            "-t", str(WHISPER_THREADS),  # CPU threads for faster processing
            "-nt",  # No timestamps in plain text output
        ]
        
        # Add language option (improves accuracy and speed)
        if language and language != "auto":
            whisper_cmd.extend(["-l", language])
        
        # Add task option (translate to English)
        if task == "translate":
            whisper_cmd.append("-tr")
        
        # Add word timestamps
        if word_timestamps:
            whisper_cmd.extend(["-ml", "1"])
        
        # Output format options
        if output_format == "json":
            whisper_cmd.extend(["-oj", "-of", str(output_path)])
        elif output_format == "srt":
            whisper_cmd.extend(["-osrt", "-of", str(output_path)])
        elif output_format == "vtt":
            whisper_cmd.extend(["-ovtt", "-of", str(output_path)])
        
        # Run whisper
        process = await asyncio.create_subprocess_exec(
            *whisper_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"Whisper transcription failed: {stderr.decode()}"
            )
        
        # Parse output
        text = stdout.decode().strip()
        
        # Handle different output formats
        if output_format == "json" and Path(f"{output_path}.json").exists():
            with open(f"{output_path}.json", "r") as f:
                json_output = json.load(f)
            return TranscriptionResponse(
                text=json_output.get("transcription", [{}])[0].get("text", text),
                segments=json_output.get("transcription", []),
                language=language
            )
        elif output_format == "srt" and Path(f"{output_path}.srt").exists():
            with open(f"{output_path}.srt", "r") as f:
                text = f.read()
        elif output_format == "vtt" and Path(f"{output_path}.vtt").exists():
            with open(f"{output_path}.vtt", "r") as f:
                text = f.read()
        
        return TranscriptionResponse(
            text=text,
            language=language
        )
        
    finally:
        # Cleanup temporary files
        for path in [input_path, wav_path]:
            if path.exists():
                path.unlink()
        for ext in [".json", ".srt", ".vtt", ".txt"]:
            output_file = Path(f"{output_path}{ext}")
            if output_file.exists():
                output_file.unlink()


@app.post("/v1/audio/transcriptions")
async def openai_compatible_transcribe(
    file: UploadFile = File(...),
    model: str = Form(default="whisper-1"),
    language: Optional[str] = Form(default=None),
    prompt: Optional[str] = Form(default=None),
    response_format: str = Form(default="json"),
    temperature: float = Form(default=0),
):
    """
    OpenAI-compatible transcription endpoint
    
    Compatible with OpenAI's /v1/audio/transcriptions API
    """
    # Map OpenAI model name to local model
    local_model = DEFAULT_MODEL
    if model and model != "whisper-1":
        local_model = model
    
    # Map response format
    output_format = "text"
    if response_format in ["json", "verbose_json"]:
        output_format = "json"
    elif response_format == "srt":
        output_format = "srt"
    elif response_format == "vtt":
        output_format = "vtt"
    
    result = await transcribe_audio(
        file=file,
        model=local_model,
        language=language,
        task="transcribe",
        output_format=output_format,
        word_timestamps=(response_format == "verbose_json")
    )
    
    if response_format == "text":
        return result.text
    
    return {
        "text": result.text,
        "language": result.language,
        "segments": result.segments
    }


@app.post("/v1/audio/translations")
async def openai_compatible_translate(
    file: UploadFile = File(...),
    model: str = Form(default="whisper-1"),
    prompt: Optional[str] = Form(default=None),
    response_format: str = Form(default="json"),
    temperature: float = Form(default=0),
):
    """
    OpenAI-compatible translation endpoint
    
    Translates audio to English text
    """
    local_model = DEFAULT_MODEL
    if model and model != "whisper-1":
        local_model = model
    
    output_format = "text"
    if response_format in ["json", "verbose_json"]:
        output_format = "json"
    
    result = await transcribe_audio(
        file=file,
        model=local_model,
        language=None,
        task="translate",
        output_format=output_format,
        word_timestamps=False
    )
    
    if response_format == "text":
        return result.text
    
    return {"text": result.text}


if __name__ == "__main__":
    import uvicorn
    
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    
    print(f"Starting Whisper API server on {host}:{port}")
    print(f"Models directory: {MODELS_DIR}")
    print(f"Default model: {DEFAULT_MODEL}")
    
    uvicorn.run(app, host=host, port=port)
