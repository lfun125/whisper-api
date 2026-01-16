# Multi-stage build for whisper.cpp API server
# Stage 1: Build whisper.cpp
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone and build whisper.cpp
WORKDIR /build
RUN git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git

WORKDIR /build/whisper.cpp
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF && \
    cmake --build build -j$(nproc) --config Release

# Stage 2: Runtime image with Python API
FROM python:3.11-slim-bookworm

# Install only essential runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy whisper-cli binary (statically linked)
COPY --from=builder /build/whisper.cpp/build/bin/whisper-cli /usr/local/bin/

# Create non-root user for security
RUN useradd -m -u 1000 whisper
WORKDIR /app
RUN mkdir -p /app/models /app/uploads /app/temp && \
    chown -R whisper:whisper /app

# Install Python dependencies
COPY --chown=whisper:whisper requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=whisper:whisper app.py .

USER whisper

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Start the API server
CMD ["python", "app.py"]
