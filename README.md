# Whisper.cpp API Server

基于 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 的 Docker 语音转文字 API 服务。

## 功能特性

- 基于 whisper.cpp 的高性能语音识别
- RESTful API 接口
- 兼容 OpenAI Whisper API 格式
- 支持多种音频格式 (wav, mp3, m4a, ogg, flac, webm, mp4)
- 支持多语言识别和翻译
- Docker 容器化部署

## 快速开始

### 1. 启动服务

```bash
# 使用启动脚本 (推荐)
chmod +x start.sh
./start.sh

# 或者手动启动
# 先下载模型
mkdir -p models
wget -O models/ggml-base.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

# 启动 Docker 服务
docker-compose up -d
```

### 2. 测试 API

```bash
# 健康检查
curl http://localhost:8000/health

# 查看 API 文档
# 打开浏览器访问: http://localhost:8000/docs
```

## API 接口

### 转录音频 - `/transcribe`

将音频文件转换为文字。

```bash
# 基本用法
curl -X POST http://localhost:8000/transcribe \
  -F "file=@audio.wav"

# 指定模型和语言
curl -X POST http://localhost:8000/transcribe \
  -F "file=@audio.mp3" \
  -F "model=small" \
  -F "language=zh"

# 翻译成英文
curl -X POST http://localhost:8000/transcribe \
  -F "file=@chinese_audio.wav" \
  -F "task=translate"

# 获取 SRT 字幕格式
curl -X POST http://localhost:8000/transcribe \
  -F "file=@video.mp3" \
  -F "output_format=srt"
```

**参数说明:**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| file | file | 必需 | 音频文件 |
| model | string | base | 模型名称 |
| language | string | auto | 语言代码 (en, zh, ja 等) |
| task | string | transcribe | transcribe 或 translate |
| output_format | string | text | text, json, srt, vtt |
| word_timestamps | bool | false | 是否包含词级时间戳 |

### OpenAI 兼容接口 - `/v1/audio/transcriptions`

兼容 OpenAI Whisper API 格式。

```bash
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F "file=@audio.wav" \
  -F "model=whisper-1"
```

### 翻译接口 - `/v1/audio/translations`

将任意语言音频翻译成英文。

```bash
curl -X POST http://localhost:8000/v1/audio/translations \
  -F "file=@chinese_audio.wav" \
  -F "model=whisper-1"
```

### 查看可用模型 - `/models`

```bash
curl http://localhost:8000/models
```

## 可用模型

| 模型 | 大小 | 内存需求 | 说明 |
|------|------|----------|------|
| tiny | 75 MB | ~273 MB | 最快，准确度较低 |
| tiny.en | 75 MB | ~273 MB | 仅英文，更快 |
| base | 142 MB | ~388 MB | 推荐入门使用 |
| base.en | 142 MB | ~388 MB | 仅英文版 base |
| small | 466 MB | ~852 MB | 平衡速度和准确度 |
| small.en | 466 MB | ~852 MB | 仅英文版 small |
| medium | 1.5 GB | ~2.1 GB | 高准确度 |
| medium.en | 1.5 GB | ~2.1 GB | 仅英文版 medium |
| large-v3 | 2.9 GB | ~3.9 GB | 最高准确度 |
| large-v3-turbo | 1.5 GB | ~2.1 GB | large 的快速版本 |

### 下载模型

```bash
# 下载 base 模型 (默认)
wget -O models/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

# 下载 small 模型 (更准确)
wget -O models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin

# 下载中文优化的 medium 模型
wget -O models/ggml-medium.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
```

## 配置

### 环境变量

在 `docker-compose.yml` 中配置:

```yaml
environment:
  - DEFAULT_MODEL=base      # 默认使用的模型
  - HOST=0.0.0.0           # 监听地址
  - PORT=8000              # 监听端口
```

### 资源限制

根据使用的模型调整内存限制:

```yaml
deploy:
  resources:
    limits:
      memory: 4G    # large 模型需要更多内存
    reservations:
      memory: 1G
```

## Python 客户端示例

```python
import requests

# 转录音频文件
def transcribe(file_path, model="base", language=None):
    url = "http://localhost:8000/transcribe"
    
    with open(file_path, "rb") as f:
        files = {"file": f}
        data = {"model": model}
        if language:
            data["language"] = language
        
        response = requests.post(url, files=files, data=data)
        return response.json()

# 使用示例
result = transcribe("audio.wav", model="small", language="zh")
print(result["text"])
```

## 支持的语言

Whisper 支持以下语言:

- 中文 (zh)
- 英语 (en)
- 日语 (ja)
- 韩语 (ko)
- 法语 (fr)
- 德语 (de)
- 西班牙语 (es)
- ... 以及更多 (共 99 种语言)

完整列表请参考: https://github.com/openai/whisper#available-models-and-languages

## 常见问题

### Q: 如何提高识别准确度?

1. 使用更大的模型 (small, medium, large)
2. 指定正确的语言参数
3. 确保音频质量良好

### Q: 为什么第一次请求很慢?

首次启动时需要加载模型到内存，之后的请求会快很多。

### Q: 支持实时语音识别吗?

目前只支持文件上传方式，不支持实时流式识别。

## 停止服务

```bash
docker-compose down
```

## License

MIT License
