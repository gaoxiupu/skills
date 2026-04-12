#!/bin/bash
#
# video-to-docs 转换脚本
# 用法: convert.sh <video_path> [output_dir]
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 跨平台获取文件修改时间（unix timestamp）
get_mod_time() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# 生成等间隔时间戳 JSON
# 使用方式: generate_equal_spaced_timestamps <frames_dir> <output_file> [interval]
generate_equal_spaced_timestamps() {
    local frames_dir="$1"
    local output_file="$2"
    local interval="${3:-3.0}"

    FRAMES_DIR="$frames_dir" OUTPUT_FILE="$output_file" INTERVAL="$interval" python3 - <<'PYEOF'
import json, os

frames_dir = os.environ['FRAMES_DIR']
output_file = os.environ['OUTPUT_FILE']
interval = float(os.environ['INTERVAL'])

frames = sorted([f for f in os.listdir(frames_dir) if f.startswith('frame_') and f.endswith('.jpg')])
result = {'frames': [{'file': f, 'time': round(i * interval, 3)} for i, f in enumerate(frames)]}
with open(output_file, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(f'生成等间隔时间戳: {len(frames)} 帧, 间隔 {interval}s')
PYEOF
}

# 检测包管理器
detect_package_manager() {
    if command -v brew &> /dev/null; then
        echo "brew"
    elif command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    else
        echo "unknown"
    fi
}

# 安装依赖
install_dependency() {
    local dep="$1"
    local pkg_manager=$(detect_package_manager)

    log_info "正在安装 $dep..."

    case "$pkg_manager" in
        brew)
            brew install "$dep" 2>&1 || {
                log_error "安装失败，请手动执行: brew install $dep"
                return 1
            }
            ;;
        apt)
            sudo apt-get update && sudo apt-get install -y "$dep" 2>&1 || {
                log_error "安装失败，请手动执行: sudo apt-get install $dep"
                return 1
            }
            ;;
        yum)
            sudo yum install -y "$dep" 2>&1 || {
                log_error "安装失败，请手动执行: sudo yum install $dep"
                return 1
            }
            ;;
        *)
            log_error "未检测到包管理器，请手动安装 $dep"
            return 1
            ;;
    esac

    log_info "$dep 安装完成"
    return 0
}

# 检查并安装依赖
check_dependencies() {
    local deps=("ffmpeg" "pandoc")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_info "检测到缺失依赖: ${missing[*]}"
        for dep in "${missing[@]}"; do
            install_dependency "$dep" || exit 1
        done
    fi
}

# 检查依赖
check_dependencies

# 参数检查
if [ -z "$1" ]; then
    echo "用法: convert.sh <video_path> [output_dir]"
    exit 1
fi

VIDEO_PATH="$1"
OUTPUT_DIR="${2:-$(dirname "$VIDEO_PATH")/docs}"
SCRIPTS_DIR="$(dirname "$0")"
TIMESTAMPS_FILE="$OUTPUT_DIR/frame_timestamps.json"
PARAMS_FILE="$OUTPUT_DIR/.extraction_params"

# 检查视频文件
if [ ! -f "$VIDEO_PATH" ]; then
    log_error "视频文件不存在: $VIDEO_PATH"
    exit 1
fi

log_info "视频路径: $VIDEO_PATH"
log_info "输出目录: $OUTPUT_DIR"

# 创建输出目录
mkdir -p "$OUTPUT_DIR/images"

# 默认配置
SCENE_THRESHOLD="${SCENE_THRESHOLD:-0.1}"
MAX_FRAMES="${MAX_FRAMES:-30}"

# Step 1: 提取关键帧
log_info "Step 1: 提取关键帧 (scene threshold: $SCENE_THRESHOLD)..."

# 使用 bash 数组替代 ls + glob（处理含空格的路径）
shopt -s nullglob

# 检查是否已有有效的截图（图片存在且比视频新，且参数未变）
frames=("$OUTPUT_DIR/images/frame_"*.jpg)
FRAME_COUNT=${#frames[@]}
CACHE_VALID=false

if [ "$FRAME_COUNT" -gt 0 ]; then
    VIDEO_MOD=$(get_mod_time "$VIDEO_PATH")
    OLDEST_FRAME="${frames[0]}"
    FRAME_MOD=$(get_mod_time "$OLDEST_FRAME")

    # 检查参数是否变化
    PARAMS_MATCH=false
    if [ -f "$PARAMS_FILE" ]; then
        CURRENT_PARAMS="SCENE_THRESHOLD=$SCENE_THRESHOLD\nMAX_FRAMES=$MAX_FRAMES"
        STORED_PARAMS=$(cat "$PARAMS_FILE" 2>/dev/null || echo "")
        if [ "$CURRENT_PARAMS" = "$STORED_PARAMS" ]; then
            PARAMS_MATCH=true
        fi
    fi

    if [ -n "$FRAME_MOD" ] && [ -n "$VIDEO_MOD" ] && [ "$FRAME_MOD" -gt "$VIDEO_MOD" ] && $PARAMS_MATCH; then
        CACHE_VALID=true
    fi

    if $CACHE_VALID; then
        log_info "已有 $FRAME_COUNT 个截图且比视频新，参数未变，跳过提取"
        echo ""
        log_info "关键帧列表："
        for frame in "${frames[@]}"; do
            echo "  $frame"
        done

        # 即使帧已缓存，也需要生成时间戳（如果不存在）
        if [ ! -f "$TIMESTAMPS_FILE" ]; then
            log_info "帧时间戳文件不存在，使用等间隔估算..."
            generate_equal_spaced_timestamps "$OUTPUT_DIR/images" "$TIMESTAMPS_FILE"
            log_info "时间戳文件: $TIMESTAMPS_FILE"
        fi

        # 调用转录（可选）
        echo ""
        bash "$SCRIPTS_DIR/transcribe.sh" "$VIDEO_PATH" "$OUTPUT_DIR" || true

        echo ""
        log_info "=== 关键帧提取完成 ==="
        exit 0
    else
        if ! $PARAMS_MATCH; then
            log_warn "提取参数已变化，将重新提取..."
        else
            log_warn "截图比视频旧，将重新提取..."
        fi
        rm -f "$OUTPUT_DIR/images/frame_"*.jpg 2>/dev/null || true
    fi
fi

# 先尝试 scene detection（同时捕获帧时间戳）
SHOWINFO_LOG="$OUTPUT_DIR/.showinfo.log"
ffmpeg -i "$VIDEO_PATH" \
    -vf "select='gt(scene,$SCENE_THRESHOLD)',showinfo,scale=1280:-2" \
    -vsync vfr \
    -q:v 2 \
    "$OUTPUT_DIR/images/frame_%03d.jpg" \
    -y 2>"$SHOWINFO_LOG" || true

# 重新读取帧数
frames=("$OUTPUT_DIR/images/frame_"*.jpg)
FRAME_COUNT=${#frames[@]}

# 如果没有检测到场景变化，按固定间隔提取
if [ "$FRAME_COUNT" -eq 0 ]; then
    log_warn "未检测到场景变化，按固定间隔提取..."
    ffmpeg -i "$VIDEO_PATH" \
        -vf "fps=1/3,showinfo,scale=1280:-2" \
        -q:v 2 \
        "$OUTPUT_DIR/images/frame_%03d.jpg" \
        -y 2>"$SHOWINFO_LOG" || true
    frames=("$OUTPUT_DIR/images/frame_"*.jpg)
    FRAME_COUNT=${#frames[@]}
fi

# 限制最大帧数（按文件名排序，保留视频前段的帧）
if [ "$FRAME_COUNT" -gt "$MAX_FRAMES" ]; then
    log_info "帧数过多 ($FRAME_COUNT)，限制为 $MAX_FRAMES..."
    cd "$OUTPUT_DIR/images"
    # 按文件名排序（反映视频时序），删除超出的帧
    printf '%s\n' frame_*.jpg | sort | tail -n +$((MAX_FRAMES + 1)) | xargs rm -f 2>/dev/null || true
    frames=("$OUTPUT_DIR/images/frame_"*.jpg)
    FRAME_COUNT=${#frames[@]}
fi

log_info "提取到 $FRAME_COUNT 个关键帧"

if [ "$FRAME_COUNT" -eq 0 ]; then
    log_error "未能提取任何帧"
    exit 1
fi

# 输出帧列表供 Claude 分析
echo ""
log_info "关键帧已提取，请分析以下图片："
# 按文件名排序输出
IFS=$'\n' sorted_frames=($(printf '%s\n' "${frames[@]}" | sort)); unset IFS
for frame in "${sorted_frames[@]}"; do
    echo "  $frame"
done

# Step 1.5: 提取帧时间戳
log_info "提取帧时间戳..."
if [ -f "$SHOWINFO_LOG" ]; then
    FRAMES_DIR="$OUTPUT_DIR/images" TIMESTAMPS_FILE="$TIMESTAMPS_FILE" SHOWINFO_LOG="$SHOWINFO_LOG" python3 - <<'PYEOF'
import re, json, os

log_file = os.environ['SHOWINFO_LOG']
frames_dir = os.environ['FRAMES_DIR']
output_file = os.environ['TIMESTAMPS_FILE']

try:
    with open(log_file, 'r') as f:
        log_content = f.read()
except Exception:
    # 没有日志文件，生成默认时间戳
    frames = sorted([f for f in os.listdir(frames_dir) if f.startswith('frame_') and f.endswith('.jpg')])
    result = {'frames': [{'file': f, 'time': round(i * 3.0, 3)} for i, f in enumerate(frames)]}
    with open(output_file, 'w') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f'生成默认时间戳: {len(frames)} 帧')
    exit(0)

# 从 showinfo 日志中解析 pts_time
# 格式: [Parsed_showinfo_1 @ ...] n:0 pts:1234 pts_time:5.234 ...
timestamps = []
for line in log_content.split('\n'):
    match = re.search(r'n:(\d+).*?pts_time:([\d.]+)', line)
    if match:
        idx = int(match.group(1))
        pts = float(match.group(2))
        timestamps.append((idx, pts))

# 获取实际帧文件列表
frames = sorted([f for f in os.listdir(frames_dir) if f.startswith('frame_') and f.endswith('.jpg')])

if len(timestamps) == len(frames):
    # 完美匹配
    result = {'frames': [{'file': frames[i], 'time': timestamps[i][1]} for i in range(len(frames))]}
elif len(timestamps) > 0:
    # 时间戳数量和帧数量不一致，按序号对齐
    result = {'frames': []}
    for i, fname in enumerate(frames):
        t = timestamps[i][1] if i < len(timestamps) else timestamps[-1][1] + (i - len(timestamps) + 1) * 3.0
        result['frames'].append({'file': fname, 'time': round(t, 3)})
else:
    # 没有解析到时间戳，使用等间隔
    result = {'frames': [{'file': f, 'time': round(i * 3.0, 3)} for i, f in enumerate(frames)]}

with open(output_file, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(f'时间戳提取完成: {len(result["frames"])} 帧')
PYEOF
    if [ $? -ne 0 ]; then
        log_warn "时间戳提取失败，使用等间隔估算"
        generate_equal_spaced_timestamps "$OUTPUT_DIR/images" "$TIMESTAMPS_FILE"
    fi
    rm -f "$SHOWINFO_LOG" 2>/dev/null || true
else
    log_warn "无 showinfo 日志，使用等间隔估算"
    generate_equal_spaced_timestamps "$OUTPUT_DIR/images" "$TIMESTAMPS_FILE"
fi

log_info "时间戳文件: $TIMESTAMPS_FILE"

# 保存提取参数（用于缓存校验）
echo -e "SCENE_THRESHOLD=$SCENE_THRESHOLD\nMAX_FRAMES=$MAX_FRAMES" > "$PARAMS_FILE"

# Step 2: 语音转录（可选）
echo ""
bash "$SCRIPTS_DIR/transcribe.sh" "$VIDEO_PATH" "$OUTPUT_DIR" || true

# 完成
echo ""
log_info "=== 关键帧提取完成 ==="
echo ""
echo "下一步: 请分析每张图片并生成描述，然后创建 Markdown 文档"
echo ""
