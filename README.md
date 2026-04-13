# Video to Docs

将视频/录屏文件自动转换为带截图和步骤说明的专业图文教程文档。

基于 Claude Code Skill 构建，利用 FFmpeg 提取关键帧、whisper.cpp 转录语音、AI 视觉分析界面操作，最终输出 Markdown 和 PDF。

## 功能特性

- **智能关键帧提取** — 使用 FFmpeg 场景检测自动识别操作步骤，无场景变化时按固定间隔提取
- **AI 视觉分析** — 两阶段分析（逐帧 + 全局），自动生成操作名称、步骤描述、注意事项
- **语音转录**（可选）— 使用本地 whisper.cpp 转录解说语音，结合字幕生成更准确的步骤描述
- **专业排版** — 输出带截图的 Markdown 文档，可转换为排版精美的 PDF（支持中文字体）
- **隐私安全** — 所有处理均在本地完成，视频和截图不会上传到第三方服务

## 系统依赖

| 依赖 | 必需 | 说明 |
|------|------|------|
| [ffmpeg](https://ffmpeg.org/) | 是 | 视频处理和关键帧提取 |
| [python3](https://www.python.org/) | 是 | 时间戳解析和格式转换 |
| [Node.js](https://nodejs.org/) | 是 | md-to-pdf PDF 生成（`npx -y md-to-pdf`） |
| [pandoc](https://pandoc.org/) | 否 | 备选 PDF 方案（更好的中文排版，需 xelatex） |
| [whisper-cpp](https://github.com/ggml-org/whisper.cpp) | 否 | 语音转录（`brew install whisper-cpp`） |

> ffmpeg、pandoc 等依赖会在首次运行时自动检测并提示安装。

## 安装

复制以下 prompt，粘贴到 Claude Code 中，AI 会自动完成安装：

```
npx skills add https://github.com/gaoxiupu/video-to-docs/skills
```

## 使用方法

安装完成后，在 Claude Code 中直接用自然语言触发：

```
把这个录屏转成教程 /Users/me/Downloads/demo.mov
```

或使用关键词：

- 「视频转文档」
- 「录屏转教程」
- 「从视频提取步骤」
- 「视频生成文档」

### 命令行直接调用

也可以跳过 AI 分析，只提取关键帧和转录：

```bash
# 提取关键帧
~/.claude/skills/video-to-docs/scripts/convert.sh /path/to/video.mp4

# 提取关键帧到指定输出目录
~/.claude/skills/video-to-docs/scripts/convert.sh /path/to/video.mp4 /path/to/output
```

## 配置选项

通过环境变量调整参数：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SCENE_THRESHOLD` | 场景检测灵敏度 (0-1)，值越低提取越密集 | `0.1` |
| `MAX_FRAMES` | 最大帧数 | `30` |
| `WHISPER_MODEL` | Whisper 模型文件路径 | `~/.claude/skills/video-to-docs/models/ggml-large-v3-q5_0.bin` |
| `WHISPER_LANGUAGE` | 转录语言 | `zh` |
| `ENABLE_TRANSCRIPTION` | 语音转录：`auto`（自动检测）/ `yes` / `no` | `auto` |

示例：

```bash
SCENE_THRESHOLD=0.05 MAX_FRAMES=50 convert.sh demo.mp4
```

## 输出结构

处理完成后，输出目录包含以下文件：

```
docs/
├── demo.md                # Markdown 文档（含 PDF 配置头）
├── demo.pdf               # 最终 PDF
├── frame_timestamps.json  # 帧时间戳（自动生成）
├── transcript.json        # 语音转录（可选）
└── images/
    ├── frame_001.jpg
    ├── frame_002.jpg
    └── ...
```

## 工作原理

```
视频文件
  │
  ├─→ FFmpeg 场景检测 → 提取关键帧 → frame_timestamps.json
  │
  ├─→ whisper.cpp 语音转录（可选）→ transcript.json
  │
  └─→ AI 两阶段分析
        ├─ 阶段 A：逐帧分析（操作名称、描述、UI要素）
        └─ 阶段 B：全局上下文（标题、概述、前置条件）
              │
              └─→ 生成 Markdown → md-to-pdf → PDF
```

## 注意事项

- 建议视频时长在 **5 分钟以内**，过长会导致处理缓慢
- 所有数据在本地处理，但 AI 分析部分需要联网调用 Claude API
- 输出文档可能包含 AI 推断内容，**建议检查后再分发**
- 如视频包含敏感信息（密码、API Key 等），请注意检查输出

## 许可证

[MIT License](LICENSE)
