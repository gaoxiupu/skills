---
name: daily-digest
description: >
  每日数字生活全景采集 & Day One 日记生成。从浏览器、OpenClaw 对话、Git 提交、下载文件等数据源
  采集当天的数字足迹，智能归纳后写入 memory 和 Day One。
  当用户说"生成今天日记"、"记录浏览记录"、"daily digest"、"写日记"、"更新 memory"、
  "今天看了什么"、"汇总今天"、"补记昨天"等类似意图时使用。
  也适用于定时任务（cron）自动触发每日执行。
---

# Daily Digest — 每日数字生活采集 & Day One 日记

## 概述

采集当天的数字足迹，智能归纳成一篇有温度的日记，而不是流水账。

**核心理念：不是记录「访问了什么 URL」，而是还原「今天这个人在关注什么、做了什么、在想什么」。**

四步走：
1. 采集原始数据（浏览记录、OpenClaw 对话、Git 提交、下载文件）
2. 智能归纳（按主题和兴趣聚类，而非按来源罗列）
3. 写入 memory
4. 写入 Day One

## Step 1：确定目标日期

- 默认：今天
- 用户说"昨天"、"补记前天"等按意图调整
- 日期格式：`YYYY-MM-DD`（后续用 `TARGET_DATE` 代指）

## Step 2：采集原始数据

**⚠️ 所有数据库必须先 cp 到 /tmp/ 再读取，读完后删除。临时文件统一 `_digest_` 前缀。**

### 2a：Dia 浏览器

```
路径：~/Library/Application Support/Dia/User Data/Default/History
（注意：根目录的 History.db 和 History.sqlite 是空文件，别用）
SQL：同 Chromium 标准结构，visits + urls 表
时间戳：WebKit 微秒（visit_time/1000000-11644473600）
```

### 2b：Chrome 浏览器

```
路径：~/Library/Application Support/Google/Chrome/Default/History
SQL：同 Chromium 标准结构
```

### 2c：Safari

```
路径：~/Library/Safari/History.db
SQL：history_visits + history_items 表
时间戳：Core Data 秒（visit_time + 978307200）
⚠️ 需要完全磁盘访问权限，否则 Operation not permitted
```

### 2d：OpenClaw 对话

Session 列表：`~/.openclaw/agents/main/sessions/sessions.json`

从 sessions.json 中找到 `updatedAt` 在目标日期范围内的所有 session，读取其 `sessionFile`（jsonl 格式）。

提取当天 user 和 assistant 消息，过滤掉系统注入的元数据：
- `Conversation info (untrusted metadata):` JSON 块
- `[media attached:...]`
- `To send an image back`
- `<<<EXTERNAL_UNTRUSTED_CONTENT...>>>`
- `NO_REPLY`、`HEARTBEAT_OK`

保留有意义的对话内容，归纳出「今天用 AI 做了什么」。

### 2e：Git 提交

扫描常用代码仓库，提取当天的 commit：

```bash
# 从 gitconfig 获取用户信息，或使用通用扫描
# 扫描 ~/Projects, ~/Code, ~/Developer, workspace 等
find ~ -maxdepth 4 -name ".git" -type d 2>/dev/null | while read gitdir; do
  repo=$(dirname "$gitdir")
  commits=$(git -C "$repo" log --author="$(git -C "$repo" config user.name)" \
    --since="TARGET_DATE 00:00:00" --until="TARGET_DATE 23:59:59" \
    --oneline --no-merges 2>/dev/null)
  if [ -n "$commits" ]; then
    echo "=== $repo ==="
    echo "$commits"
  fi
done
```

### 2f：下载文件

```bash
find ~/Downloads -maxdepth 1 -newer /dev/null \
  -Btime "TARGET_DATE*" -exec ls -lhT {} \; 2>/dev/null

# 或者用 stat 按日期筛选
find ~/Downloads -maxdepth 1 -type f -exec stat -f "%SB %N" -t "%Y-%m-%d %H:%M %N" {} \; 2>/dev/null | grep "TARGET_DATE"
```

### 2g：清理

```bash
rm -f /tmp/_digest_*.db
```

## Step 3：智能归纳

**这是最关键的一步。不要按来源罗列，要按主题和兴趣聚类。**

### 归纳原则

1. **主题聚类**：把来自不同来源的相关内容归到同一个主题下
   - 例如：在 X 看到某 AI 工具 → 在小红书搜了同类工具 → 用 ChatGPT 分析可行性 → 这是一条完整的「AI 工具探索」线索

2. **提取行为模式**：不只是「看了什么」，而是「在做什么」
   - ❌ "访问了 youtube.com，看了 3 个视频"
   - ✅ "看了亚洲室内田径锦标赛的回放，对女子短跑比较关注"

3. **保留趣味和个性**：日记是给自己看的，不是给机器看的
   - 加入观察和感悟（基于数据推断）
   - 比如"今天消费欲望比较强，买了运动装备"

4. **区分深度和浅度**：
   - 深度行为：在多个平台围绕同一主题搜索/阅读 → 说明真正感兴趣
   - 浅度行为：随手刷了刷 → 一笔带过

### 归纳维度

从原始数据中提取以下维度：

#### 🎯 今日重点（1-3 件）
今天花时间最多、跨越多个平台、反复出现的事。用一两句话说清楚。

#### 💡 兴趣方向
从浏览和对话中提炼出今天关注的主题。每个主题一段话，把来自不同来源的信息串起来。

#### 🛠️ 生产力 & 创造
- 用 AI 做了什么（OpenClaw 对话归纳）
- 写了什么代码（Git commits）
- 下载了什么文件（可能反映正在做的事）

#### 📱 消费 & 娱乐
- 购物/消费行为（从浏览记录推断）
- 刷了什么内容（短视频、社交媒体、视频平台）
- 用一个轻松的语气概括

#### 📌 待关注
- 看起来重要但还没深入的事
- 留意到但没行动的线索

## Step 4：写入 memory

将归纳结果写入 `memory/YYYY-MM-DD.md`，格式：

```markdown
# YYYY-MM-DD

## 今日重点
- 最重要的 1-3 件事

## 兴趣方向
- **主题A**：跨平台的完整描述
- **主题B**：...

## 生产力
- AI 助手使用：...
- 代码提交：...
- 下载文件：...

## 消费 & 娱乐
- ...

## 待关注
- ...

## 原始数据备注
- 浏览记录来源：Dia/Chrome/Safari 各多少条
- OpenClaw 对话：多少轮
- Git 提交：多少个 commit
```

## Step 5：Day One 日记

### 5a：检查已有 entry（含重复清理）

```bash
cp "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" /tmp/_digest_dayone.db

# 查询目标日期的所有 entry
EXISTING=$(sqlite3 /tmp/_digest_dayone.db "
SELECT e.Z_PK
FROM ZENTRY e
LEFT JOIN ZJOURNAL j ON e.ZJOURNAL = j.Z_PK
WHERE j.ZNAME = 'Digital'
  AND date(e.ZCREATIONDATE + 978307200, 'unixepoch', 'localtime') = 'TARGET_DATE'
ORDER BY e.Z_PK DESC;
")

COUNT=$(echo "$EXISTING" | grep -c .)
LATEST_PK=$(echo "$EXISTING" | head -1)

if [ "$COUNT" -gt 1 ]; then
  echo "⚠️ 发现 $COUNT 个重复 entry，保留最新 (PK=$LATEST_PK)，删除其余"
  DUPES=$(echo "$EXISTING" | tail -n +2 | tr '\n' ',')
  # 备份后删除重复
  cp "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" \
     "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite.bak"
  for pk in $(echo "$EXISTING" | tail -n +2); do
    sqlite3 "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" \
      "DELETE FROM ZENTRY WHERE Z_PK = $pk;"
  done
fi

if [ -n "$LATEST_PK" ]; then
  echo "UPDATE_MODE=true ENTRY_PK=$LATEST_PK"
else
  echo "UPDATE_MODE=false ENTRY_PK="
fi
```

### 5b：生成日记内容

先写入 `/tmp/_digest_entry.md`。

**日记格式（写给人看的，不是写给机器看的）：**

```markdown
# TARGET_DATE

一段轻松的开头，像朋友聊天一样概括今天的状态。（2-3 句话）

---

## 🎯 今天最重要的事

用叙述的方式，把今天花最多精力的事写出来。不是列表，是一段话。
如果有多个重点，用分段区分。

## 💡 关注了什么

**主题A**
把围绕这个主题的所有行为串成一段故事。比如"下午在小红书看到 openclaw 的讨论，然后去 X 搜了一圈，晚上还用 ChatGPT 研究了一下可行性——看起来是真的想搞。"

**主题B**
同上。

## 🛠️ 做了什么

- 和豆沙包聊了 XXX，主要干了 XXX
- 提交了 N 个 commit，主要改了 XXX
- 下载了 XXX 文件（可能在做 XXX）

## 📱 随手刷的

轻松概括今天在社交媒体、视频平台上的消遣内容。
不需要每条都列出，挑有意思的说。

## 📌 值得留意

- 看到但还没深入的事
- 可能会跟进的线索

---

*数据来源：Dia XX 条 | Chrome XX 条 | Safari XX 条 | AI 对话 XX 轮 | Git N commits*
```

### 5c：写入 Day One

**已有 entry → 更新 ZMARKDOWNTEXT：**
```bash
cp "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" \
   "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite.bak"

sqlite3 "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" "
UPDATE ZENTRY SET ZMARKDOWNTEXT = readfile('/tmp/_digest_entry.md') WHERE Z_PK = ENTRY_PK;
"

# 重启 Day One 刷新界面
osascript -e 'tell application "Day One" to quit'
sleep 2
open -a "Day One"
```

**没有 entry → 新建（含二次防重）：**

```bash
# 二次确认：再查一次，防止并发导致重复
sleep 2
cp "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" /tmp/_digest_dayone_recheck.db
RECHECK=$(sqlite3 /tmp/_digest_dayone_recheck.db "
SELECT e.Z_PK FROM ZENTRY e
LEFT JOIN ZJOURNAL j ON e.ZJOURNAL = j.Z_PK
WHERE j.ZNAME = 'Digital'
  AND date(e.ZCREATIONDATE + 978307200, 'unixepoch', 'localtime') = 'TARGET_DATE'
ORDER BY e.Z_PK DESC LIMIT 1;
")

if [ -n "$RECHECK" ]; then
  echo "⚠️ 二次检查发现已有 entry (PK=$RECHECK)，改为更新模式"
  # 走更新逻辑
  sqlite3 "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" \
    "UPDATE ZENTRY SET ZMARKDOWNTEXT = readfile('/tmp/_digest_entry.md') WHERE Z_PK = $RECHECK;"
else
  DAYONE_CLI="/Applications/Day One.app/Contents/MacOS/dayone"
  cat /tmp/_digest_entry.md | "$DAYONE_CLI" new --journal Digital --date 'TARGET_DATE' --tags '工作日志'
fi
```

⚠️ **不要用 heredoc 传内容给 Day One CLI，会丢失文本。必须先写文件再 cat 管道传入。**

### 5d：验证

```bash
cp "$HOME/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite" /tmp/_digest_verify.db
sqlite3 /tmp/_digest_verify.db "SELECT substr(ZMARKDOWNTEXT, 1, 100) FROM ZENTRY WHERE Z_PK = TARGET_PK;"
```

内容为空则重试。

## Step 6：清理 & 汇报

```bash
rm -f /tmp/_digest_*.db /tmp/_digest_entry.md /tmp/_digest_verify.db
```

汇报：
- 采集了多少条原始数据（各来源）
- memory 文件路径
- Day One entry 状态和 UUID

## 常见问题

### Dia 数据库路径
- ✅ `~/Library/Application Support/Dia/User Data/Default/History`
- ❌ `~/Library/Application Support/Dia/History.db`（空文件）
- ❌ `~/Library/Application Support/Dia/History.sqlite`（空文件）

### Safari 权限
需要 **系统设置 → 隐私与安全性 → 完全磁盘访问权限** 添加终端/OpenClaw。

### Day One CLI 内容丢失
不用 heredoc，用 `cat file | dayone new` 管道传入。

### 浏览器数据库锁定
cp 时如果报 "database is locked"，等几秒重试。

### OpenClaw 对话噪音
user 消息含大量系统元数据，提取时必须过滤（见 2d 节过滤规则）。

## 归纳示例

**❌ 流水账风格（不要这样写）：**
```
- 访问了 youtube.com，看了亚洲田径锦标赛
- 访问了 x.com，刷了推
- 访问了 notion.so，看了 Writing 页面
- 和 AI 聊了信用卡账单
```

**✅ 有温度的日记风格（要这样写）：**
```
今天比较宅，大部分时间在电脑前。下午突然对 AI Agent 协作产生了兴趣，
从小红书刷到 Bloome 的多 Agent 群聊功能开始，一路追到 X 上的讨论，
晚上甚至用 ChatGPT 和 Gemini 分别做了个 iOS 健康助手的可行性分析——
看起来是真的想搞点什么出来。

运动方面，看了亚洲室内田径锦标赛的回放，女子 60 米中国包揽前三，
挺提气的。不过自己今天没动，连续第三天没跑步了。
```
