#!/bin/bash
#
# video-to-docs 语音转录脚本
# 用法: transcribe.sh <video_path> [output_dir]
#
# 从视频中提取音频并使用 whisper.cpp 进行语音转录。
# 如果 whisper-cpp 未安装，跳过转录（不阻塞主流程）。
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_skip() { echo -e "${BLUE}[SKIP]${NC} $1"; }

# 跨平台获取文件修改时间（unix timestamp）
get_mod_time() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# 参数检查
if [ -z "$1" ]; then
    echo "用法: transcribe.sh <video_path> [output_dir]"
    exit 1
fi

VIDEO_PATH="$1"
OUTPUT_DIR="${2:-$(dirname "$VIDEO_PATH")/docs}"

# 默认配置
SKILLS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-zh}"
WHISPER_MODEL="${WHISPER_MODEL:-$SKILLS_DIR/models/ggml-large-v3-q5_0.bin}"
ENABLE_TRANSCRIPTION="${ENABLE_TRANSCRIPTION:-auto}" # auto/yes/no

# 临时文件路径（用于 trap 清理）
WAV_FILE="$OUTPUT_DIR/.audio_temp.wav"
RAW_JSON="$OUTPUT_DIR/.transcript_raw.json"

# 确保退出时清理临时文件
cleanup() {
    rm -f "$WAV_FILE" "$RAW_JSON" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- 检查是否启用转录 ---

if [ "$ENABLE_TRANSCRIPTION" = "no" ]; then
    log_skip "语音转录已禁用 (ENABLE_TRANSCRIPTION=no)"
    exit 0
fi

# 检查 whisper-cpp（支持多种命令名）
WHISPER_CMD=""
for cmd in whisper-cpp whisper-cli whisper; do
    if command -v "$cmd" &> /dev/null; then
        WHISPER_CMD="$cmd"
        break
    fi
done

if [ -z "$WHISPER_CMD" ]; then
    if [ "$ENABLE_TRANSCRIPTION" = "yes" ]; then
        log_error "已启用转录但未找到 whisper-cpp。请运行: brew install whisper-cpp"
        exit 1
    fi
    log_skip "未安装 whisper-cpp，跳过语音转录。安装: brew install whisper-cpp"
    exit 0
fi

# 检查视频是否有音轨
AUDIO_INFO=$(ffprobe -v quiet -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO_PATH" 2>/dev/null || echo "")
if [ -z "$AUDIO_INFO" ]; then
    log_skip "视频无音轨，跳过语音转录"
    exit 0
fi

log_info "语音转录已启用"
log_info "视频路径: $VIDEO_PATH"
log_info "输出目录: $OUTPUT_DIR"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# --- 检查并下载模型 ---

download_model() {
    local model_path="$1"
    local model_dir="$(dirname "$model_path")"
    local model_name="$(basename "$model_path")"

    mkdir -p "$model_dir"

    log_info "首次使用，下载 Whisper 模型: $model_name"
    log_info "模型大小约 1GB，请耐心等待..."

    curl -L -o "$model_path" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model_name}?download=true" \
        --progress-bar 2>&1 || {
        log_error "模型下载失败，请手动下载: https://huggingface.co/ggerganov/whisper.cpp"
        rm -f "$model_path"
        exit 1
    }

    if [ ! -s "$model_path" ]; then
        log_error "模型文件为空，下载可能失败"
        rm -f "$model_path"
        exit 1
    fi

    log_info "模型下载完成: $model_path"
}

if [ ! -f "$WHISPER_MODEL" ]; then
    log_warn "Whisper 模型不存在: $WHISPER_MODEL"
    download_model "$WHISPER_MODEL"
fi

# --- 检查是否已有有效的转录 ---

TRANSCRIPT_FILE="$OUTPUT_DIR/transcript.json"
if [ -f "$TRANSCRIPT_FILE" ]; then
    VIDEO_MOD=$(get_mod_time "$VIDEO_PATH")
    TRANSCRIPT_MOD=$(get_mod_time "$TRANSCRIPT_FILE")

    if [ -n "$TRANSCRIPT_MOD" ] && [ -n "$VIDEO_MOD" ] && [ "$TRANSCRIPT_MOD" -gt "$VIDEO_MOD" ]; then
        log_info "已有转录文件且比视频新，跳过转录"
        echo ""
        log_info "转录文件: $TRANSCRIPT_FILE"
        exit 0
    else
        log_warn "转录文件比视频旧，将重新转录..."
        rm -f "$TRANSCRIPT_FILE" 2>/dev/null || true
    fi
fi

# --- Step 1: 提取音频 ---

log_info "Step 1: 提取音频..."

ffmpeg -i "$VIDEO_PATH" \
    -ar 16000 \
    -ac 1 \
    -c:a pcm_s16le \
    -y \
    "$WAV_FILE" 2>/dev/null || {
    log_warn "音频提取失败，跳过转录"
    rm -f "$WAV_FILE" 2>/dev/null || true
    exit 0
}

# 检查 WAV 文件大小（太小说明可能是静音）
WAV_SIZE=$(stat -f %z "$WAV_FILE" 2>/dev/null || stat -c %s "$WAV_FILE" 2>/dev/null)
if [ -z "$WAV_SIZE" ] || [ "$WAV_SIZE" -lt 10000 ]; then
    log_skip "音频文件过小（可能是静音），跳过转录"
    rm -f "$WAV_FILE"
    exit 0
fi

# --- Step 2: 运行转录 ---

log_info "Step 2: 运行 Whisper 转录 (语言: $WHISPER_LANGUAGE)..."

# 设置 Metal GPU 路径（Apple Silicon 优化）
export GGML_METAL_PATH_RESOURCES="$(brew --prefix whisper-cpp 2>/dev/null || echo '')/share/whisper-cpp"
if [ ! -d "$GGML_METAL_PATH_RESOURCES" ]; then
    unset GGML_METAL_PATH_RESOURCES
fi

# 使用 JSON 输出格式（带时间戳）
"$WHISPER_CMD" \
    -m "$WHISPER_MODEL" \
    -l "$WHISPER_LANGUAGE" \
    --output-json \
    --output-file "$OUTPUT_DIR/.transcript_raw" \
    -f "$WAV_FILE" 2>&1 | tail -5 || {
    log_warn "转录过程出错"
    rm -f "$WAV_FILE" "$RAW_JSON" 2>/dev/null || true
    exit 0
}

# 清理临时 WAV（转录完成不再需要）
rm -f "$WAV_FILE"

# --- Step 3: 转换输出格式 ---

if [ ! -f "$RAW_JSON" ]; then
    log_warn "转录输出文件不存在"
    exit 0
fi

log_info "Step 3: 处理转录结果..."

# 使用 python3 将 whisper.cpp JSON 转换为简化格式
RAW_JSON_PATH="$RAW_JSON" TRANSCRIPT_PATH="$TRANSCRIPT_FILE" WHISPER_LANG="$WHISPER_LANGUAGE" python3 - <<'PYEOF'
import json, os, sys

def parse_timestamp(val):
    """解析时间戳，支持浮点数和 HH:MM:SS.mmm 格式"""
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        val = val.strip()
        # 尝试直接解析为浮点数
        try:
            return float(val)
        except ValueError:
            pass
        # 解析 HH:MM:SS.mmm 或 MM:SS.mmm 格式
        val = val.replace(',', '.')
        parts = val.split(':')
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        elif len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
        else:
            return 0.0
    return 0.0

raw_path = os.environ['RAW_JSON_PATH']
output_path = os.environ['TRANSCRIPT_PATH']
lang = os.environ.get('WHISPER_LANG', 'zh')

try:
    data = json.load(open(raw_path))
except Exception:
    sys.exit(0)

segments = []
for item in data.get('transcription', []):
    ts = item.get('timestamps', {})
    text = item.get('text', '').strip()
    if not text:
        continue
    segments.append({
        'start': parse_timestamp(ts.get('from', 0)),
        'end': parse_timestamp(ts.get('to', 0)),
        'text': text
    })

output = {
    'language': lang,
    'segments': segments
}

with open(output_path, 'w') as f:
    json.dump(output, f, ensure_ascii=False, indent=2)
print(f'转录完成: {len(segments)} 个段落')
PYEOF

if [ $? -ne 0 ]; then
    log_warn "转录结果处理失败"
    rm -f "$RAW_JSON" 2>/dev/null || true
    exit 0
fi

# 清理原始 JSON（trap 也会在退出时清理，但这里显式删除更干净）
rm -f "$RAW_JSON" 2>/dev/null || true

# --- 完成 ---

SEGMENT_COUNT=$(SEGMENT_COUNT_FILE="$TRANSCRIPT_FILE" python3 - <<'PYEOF'
import json, os
try:
    data = json.load(open(os.environ['SEGMENT_COUNT_FILE']))
    print(len(data.get('segments', [])))
except Exception:
    print(0)
PYEOF
)

if [ "$SEGMENT_COUNT" -eq 0 ]; then
    log_skip "未识别到语音内容"
    rm -f "$TRANSCRIPT_FILE" 2>/dev/null || true
else
    log_info "转录完成: $SEGMENT_COUNT 个段落"
    log_info "输出文件: $TRANSCRIPT_FILE"
fi

echo ""
log_info "=== 语音转录完成 ==="
echo ""
