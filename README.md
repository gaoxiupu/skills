# Skills

这个仓库用于收集和维护 Claude Code / OpenClaw 可用的 skills。当前包含两个 skill，后续可以继续按目录追加更多 skill。

## Skills 列表

| Skill | 目录 | 用途 |
|------|------|------|
| Video to Docs | [`video-to-docs/`](video-to-docs/) | 将视频或录屏转换为带截图、步骤说明的 Markdown / PDF 教程文档 |
| Daily Digest | [`daily-digest/`](daily-digest/) | 采集浏览器、AI 对话、Git 提交、下载文件等数字足迹，生成每日记录和 Day One 日记 |

## 安装

可以直接从本仓库安装需要的 skill：

```bash
npx skills add https://github.com/gaoxiupu/skills
```

如果你的 skill 管理工具支持按目录安装，也可以只安装某一个 skill：

```bash
npx skills add https://github.com/gaoxiupu/skills/tree/main/video-to-docs
npx skills add https://github.com/gaoxiupu/skills/tree/main/daily-digest
```

> 具体安装方式取决于你使用的 skill 管理工具版本；如果整仓库安装失败，请改用单个目录安装。

## 使用

安装后，在 Claude Code / OpenClaw 中直接用自然语言触发即可。

### Video to Docs

适合把录屏、软件演示、操作视频整理成图文教程。

示例：

```text
把这个录屏转成教程 /Users/me/Downloads/demo.mov
```

常见触发词：

- 视频转文档
- 录屏转教程
- 从视频提取步骤
- 视频生成文档

详细说明见 [`video-to-docs/SKILL.md`](video-to-docs/SKILL.md)。

### Daily Digest

适合把一天的数字足迹整理成有上下文的个人记录，而不是简单流水账。

示例：

```text
生成今天日记
```

常见触发词：

- daily digest
- 写日记
- 汇总今天
- 今天看了什么
- 补记昨天
- 更新 memory

详细说明见 [`daily-digest/SKILL.md`](daily-digest/SKILL.md)。

## 仓库结构

每个 skill 使用独立目录，目录名就是 skill 名称：

```text
skills/
├── daily-digest/
│   └── SKILL.md
├── video-to-docs/
│   ├── SKILL.md
│   ├── scripts/
│   └── templates/
├── README.md
└── LICENSE
```

新增 skill 时，建议保持同样结构：

```text
new-skill/
├── SKILL.md
├── scripts/      # 可选
├── templates/    # 可选
└── assets/       # 可选
```

## 依赖说明

不同 skill 的系统依赖不同，请以各自目录中的 `SKILL.md` 为准。

例如：

- `video-to-docs` 依赖 FFmpeg、Python、Node.js，可选 whisper.cpp / pandoc。
- `daily-digest` 会读取本机浏览器历史、OpenClaw 会话、Git 提交、下载目录和 Day One 数据库，运行前需要确保对应应用和权限可用。

## 许可证

[MIT License](LICENSE)
