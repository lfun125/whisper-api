.PHONY: build build-alpine build-amd64 build-multi start stop logs download-model clean test export import

# Default model
MODEL ?= base
IMAGE_NAME ?= whisper-api
VERSION ?= latest
PLATFORM ?= linux/amd64

# Build Docker image (native platform)
build:
	docker build -t $(IMAGE_NAME):$(VERSION) .

# Build Alpine version (smaller)
build-alpine:
	docker build -f Dockerfile.alpine -t $(IMAGE_NAME):alpine .

# Build for x86_64/amd64 (cross-platform from Apple Silicon)
build-amd64:
	docker buildx build --platform linux/amd64 \
		-t $(IMAGE_NAME):$(VERSION)-amd64 \
		--load .

# Build and export amd64 image to tar file
build-amd64-export:
	docker buildx build --platform linux/amd64 \
		-t $(IMAGE_NAME):$(VERSION) \
		-o type=docker,dest=$(IMAGE_NAME)-amd64.tar .
	gzip $(IMAGE_NAME)-amd64.tar
	@ls -lh $(IMAGE_NAME)-amd64.tar.gz

# Build multi-platform and push to registry
build-multi:
	@if [ -z "$(REGISTRY)" ]; then \
		echo "Usage: make build-multi REGISTRY=docker.io/yourname"; \
		exit 1; \
	fi
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(REGISTRY)/$(IMAGE_NAME):$(VERSION) \
		--push .

# Setup buildx builder (run once)
buildx-setup:
	docker buildx create --name multiarch --use || true
	docker buildx inspect --bootstrap

# Build with docker-compose
build-compose:
	docker-compose build

# Start the service
start: download-model
	docker-compose up -d
	@echo ""
	@echo "Whisper API is starting..."
	@echo "API Docs: http://localhost:8000/docs"
	@echo "Health: http://localhost:8000/health"

# Stop the service
stop:
	docker-compose down

# View logs
logs:
	docker-compose logs -f

# Download model
download-model:
	@mkdir -p models
	@if [ ! -f "models/ggml-$(MODEL).bin" ]; then \
		echo "Downloading model: $(MODEL)"; \
		wget -O "models/ggml-$(MODEL).bin" \
			"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$(MODEL).bin"; \
	else \
		echo "Model $(MODEL) already exists"; \
	fi

# Download all common models
download-all-models:
	@mkdir -p models
	@for m in tiny base small; do \
		if [ ! -f "models/ggml-$$m.bin" ]; then \
			echo "Downloading model: $$m"; \
			wget -O "models/ggml-$$m.bin" \
				"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$$m.bin"; \
		fi; \
	done

# Clean up
clean:
	docker-compose down -v
	rm -rf uploads/* temp/*

# Test the API
test:
	@echo "Testing health endpoint..."
	@curl -s http://localhost:8000/health | python3 -m json.tool
	@echo ""
	@echo "Testing models endpoint..."
	@curl -s http://localhost:8000/models | python3 -m json.tool

# Test transcription with sample file
test-transcribe:
	@echo "Testing transcription..."
	@if [ -f "test.wav" ]; then \
		curl -X POST http://localhost:8000/transcribe -F "file=@test.wav"; \
	else \
		echo "Please provide a test.wav file"; \
	fi

# Export image to tar file (for offline deployment)
export:
	@echo "Exporting $(IMAGE_NAME):$(VERSION) to $(IMAGE_NAME).tar.gz"
	docker save $(IMAGE_NAME):$(VERSION) | gzip > $(IMAGE_NAME).tar.gz
	@ls -lh $(IMAGE_NAME).tar.gz

# Import image from tar file
import:
	@echo "Importing from $(IMAGE_NAME).tar.gz"
	gunzip -c $(IMAGE_NAME).tar.gz | docker load

# Tag and push to registry
push:
	@if [ -z "$(REGISTRY)" ]; then \
		echo "Usage: make push REGISTRY=your-registry.com/username"; \
		exit 1; \
	fi
	docker tag $(IMAGE_NAME):$(VERSION) $(REGISTRY)/$(IMAGE_NAME):$(VERSION)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(VERSION)

# Show image size
size:
	@docker images $(IMAGE_NAME) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Help
help:
	@echo "Whisper API Makefile"
	@echo ""
	@echo "Build (native):"
	@echo "  make build          - Build for current platform"
	@echo "  make build-alpine   - Build Alpine version (smaller)"
	@echo ""
	@echo "Build (cross-platform, Apple Silicon -> x86):"
	@echo "  make buildx-setup      - Setup buildx (run once)"
	@echo "  make build-amd64       - Build x86_64 image"
	@echo "  make build-amd64-export - Build & export x86_64 to tar.gz"
	@echo "  make build-multi REGISTRY=xxx - Build multi-arch & push"
	@echo ""
	@echo "Run:"
	@echo "  make start          - Start the service"
	@echo "  make stop           - Stop the service"
	@echo "  make logs           - View container logs"
	@echo ""
	@echo "Deploy:"
	@echo "  make export         - Export image to tar.gz"
	@echo "  make import         - Import image from tar.gz"
	@echo "  make push REGISTRY=xxx - Push to registry"
	@echo "  make size           - Show image sizes"
	@echo ""
	@echo "Models:"
	@echo "  make download-model          - Download base model"
	@echo "  make download-model MODEL=small"
	@echo ""
	@echo "Examples:"
	@echo "  make build-amd64 VERSION=1.0"
	@echo "  make build-amd64-export"
	@echo "  make build-multi REGISTRY=docker.io/myuser"
