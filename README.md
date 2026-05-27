# Claude Code Watchdog (Windows)

Windows 版 Claude Code 会话监控工具。检测卡住的会话并可自动恢复。

## 安装

将 `watchdog.ps1` 和 `SKILL.md` 复制到 `~/.claude/skills/watchdog/` 目录。

## 使用

```powershell
# 监控指定项目目录
& "$env:USERPROFILE\.claude\skills\watchdog\watchdog.ps1" -ProjectPath "C:\your\project\path"

# 自定义参数
& "$env:USERPROFILE\.claude\skills\watchdog\watchdog.ps1" -ProjectPath "C:\your\project\path" -IdleMinutes 5 -PollSeconds 15
```

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-ProjectPath` | (必填) | 要监控的项目目录路径 |
| `-IdleMinutes` | 10 | 无活动判定卡住的分钟数 |
| `-PollSeconds` | 30 | 检查间隔秒数 |
| `-MaxRetries` | 3 | 自动恢复最大重试次数 |

## 功能

- **三重检测**：进程存活 + JSONL 文件活跃度 + 输出 token 停滞
- **指定项目监控**：只监控指定目录，不会扫描全部会话
- **声音提醒**：卡住时终端 Beep 声
- **自动恢复**：确认卡住后自动启动 `claude --continue`，最多重试 N 次
- **事件日志**：记录到 `~/.claude/watchdog-state/events.log`

## 作为 Claude Code Skill 使用

安装后可在 Claude Code 中直接输入 `/watchdog` 启动。
