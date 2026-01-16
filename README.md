# Whisper.cpp API Server

基于 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 的 Docker 语音转文字 API 服务。

## 功能特性

- 基于 whisper.cpp 的高性能语音识别
- **开箱即用** - 模型已内置于 Docker 镜像
- RESTful API 接口
- 兼容 OpenAI Whisper API 格式
- 支持多种音频格式 (wav, mp3, m4a, ogg, flac, webm, mp4)
- 支持多语言识别和翻译
- 支持跨平台构建 (Apple Silicon -> x86)

## 快速开始

### 方式一：使用 Makefile（推荐）

```bash
# 构建镜像（模型自动下载并打包）
make build

# 运行服务
make start

# 查看日志
make logs
```

### 方式二：手动构建

```bash
# 构建镜像（默认使用 base 模型）
docker build -t whisper-api:latest .

# 运行
docker run -d -p 8000:8000 --name whisper-api whisper-api:latest

# 或使用 docker-compose
docker-compose up -d
```

### 测试 API

```bash
# 健康检查
curl http://localhost:8000/health

# 查看 API 文档
open http://localhost:8000/docs

# 转录音频
curl -X POST http://localhost:8000/transcribe -F "file=@audio.m4a"
```

## 构建选项

### 选择不同模型

构建时可以选择内置的模型：

```bash
# 使用 tiny 模型（最小最快）
make build MODEL=tiny

# 使用 base 模型（默认，推荐）
make build MODEL=base

# 使用 small 模型（更准确）
make build MODEL=small

# 使用 medium 模型（高准确度）
make build MODEL=medium
```

### 可用模型

| 模型 | 大小 | 内存需求 | 准确度 | 适用场景 |
|------|------|----------|--------|----------|
| tiny | 75 MB | ~273 MB | 低 | 快速测试 |
| base | 142 MB | ~388 MB | 中 | **推荐入门** |
| small | 466 MB | ~852 MB | 较高 | 日常使用 |
| medium | 1.5 GB | ~2.1 GB | 高 | 专业场景 |
| large-v3 | 2.9 GB | ~3.9 GB | 最高 | 最佳效果 |

### 跨平台构建（Apple Silicon -> x86）

在 Mac M1/M2 上构建 x86 镜像：

```bash
# 首次运行，设置 buildx
make buildx-setup

# 构建 x86_64 镜像
make build-amd64 MODEL=base

# 构建并导出为 tar.gz（用于离线部署）
make build-amd64-export MODEL=base
# 生成 whisper-api-amd64.tar.gz
```

### 部署到服务器

```bash
# 1. 在本地构建并导出
make build-amd64-export MODEL=small

# 2. 上传到服务器
scp whisper-api-amd64.tar.gz user@server:/path/

# 3. 在服务器导入并运行
ssh user@server
gunzip -c whisper-api-amd64.tar.gz | docker load
docker run -d -p 8000:8000 whisper-api:latest
```

## API 接口

### 转录音频 - `POST /transcribe`

```bash
# 基本用法
curl -X POST http://localhost:8000/transcribe \
  -F "file=@audio.m4a"

# 指定语言（提高准确度）
curl -X POST http://localhost:8000/transcribe \
  -F "file=@audio.mp3" \
  -F "language=zh"

# 翻译成英文
curl -X POST http://localhost:8000/transcribe \
  -F "file=@chinese.wav" \
  -F "task=translate"

# 获取 SRT 字幕
curl -X POST http://localhost:8000/transcribe \
  -F "file=@video.mp3" \
  -F "output_format=srt"
```

**参数说明:**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| file | file | 必需 | 音频文件 |
| language | string | auto | 语言代码 (zh, en, ja 等) |
| task | string | transcribe | transcribe 或 translate |
| output_format | string | text | text, json, srt, vtt |

### OpenAI 兼容接口 - `POST /v1/audio/transcriptions`

兼容 OpenAI Whisper API，可直接替换：

```bash
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F "file=@audio.wav" \
  -F "model=whisper-1"
```

### 翻译接口 - `POST /v1/audio/translations`

将任意语言音频翻译成英文：

```bash
curl -X POST http://localhost:8000/v1/audio/translations \
  -F "file=@chinese.wav"
```

### 查看模型 - `GET /models`

```bash
curl http://localhost:8000/models
```

### 支持的音频格式

| 格式 | 扩展名 |
|------|--------|
| WAV | `.wav` |
| MP3 | `.mp3` |
| M4A | `.m4a` |
| OGG | `.ogg` |
| FLAC | `.flac` |
| WebM | `.webm` |
| MP4 | `.mp4` |

## Makefile 命令

```bash
make help              # 查看所有命令

# 构建
make build             # 构建镜像（含 base 模型）
make build MODEL=small # 构建镜像（含 small 模型）
make build-alpine      # 构建 Alpine 版本（更小）
make build-amd64       # 构建 x86 镜像
make build-amd64-export # 构建并导出 x86 镜像

# 运行
make start             # 启动服务
make stop              # 停止服务
make logs              # 查看日志

# 部署
make export            # 导出镜像为 tar.gz
make import            # 导入镜像
make size              # 查看镜像大小
```

## Python 客户端

```python
import requests

def transcribe(file_path, language=None):
    url = "http://localhost:8000/transcribe"
    
    with open(file_path, "rb") as f:
        files = {"file": f}
        data = {}
        if language:
            data["language"] = language
        
        response = requests.post(url, files=files, data=data)
        return response.json()

# 使用
result = transcribe("audio.m4a", language="zh")
print(result["text"])
```

## 支持的语言

Whisper 支持 99 种语言，常用的包括：

| 语言 | 代码 |
|------|------|
| 中文 | zh |
| 英语 | en |
| 日语 | ja |
| 韩语 | ko |
| 法语 | fr |
| 德语 | de |
| 西班牙语 | es |

完整列表: https://github.com/openai/whisper#available-models-and-languages

## 常见问题

### Q: 为什么第一次请求较慢？

首次请求需要加载模型到内存，之后会很快。

### Q: 如何提高识别准确度？

1. 使用更大的模型：`make build MODEL=small`
2. 指定正确的语言：`-F "language=zh"`
3. 确保音频质量良好

### Q: 中文识别效果不好？

建议使用 small 或 medium 模型，并指定 `language=zh`：

```bash
# 构建时使用 small 模型
make build MODEL=small

# 请求时指定中文
curl -X POST http://localhost:8000/transcribe \
  -F "file=@audio.m4a" \
  -F "language=zh"
```

### Q: 镜像太大怎么办？

使用 Alpine 版本或更小的模型：

```bash
make build-alpine MODEL=tiny
```

## 停止服务

```bash
make stop
# 或
docker-compose down
```

## License

MIT License
