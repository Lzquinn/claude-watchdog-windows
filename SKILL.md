---
name: watchdog
description: 监控 Claude Code 会话是否卡住，支持声音提醒和自动恢复
---

# Claude Code Watchdog

Windows 版 Claude Code 会话监控工具。检测卡住的会话并可自动恢复。

## 使用方式

当用户说"启动 watchdog"、"监控会话"、"/watchdog"时，使用 **PowerShell 工具**（不是 Bash）执行以下命令：

### 启动

使用 PowerShell 工具运行：
```
& "$env:USERPROFILE\.claude\skills\watchdog\watchdog.ps1" -ProjectPath "C:\Users\刘志强\.claude\projects\jiankong"
```

**重要：必须使用 PowerShell 工具，不要用 Bash 工具调用 powershell.exe，否则中文路径会编码错误。**

### 参数说明

- `-ProjectPath` — 要监控的项目目录路径（必填，只监控该目录下的会话）
- `-IdleMinutes` — 无活动判定卡住的分钟数，默认 10
- `-PollSeconds` — 检查间隔秒数，默认 30
- `-MaxRetries` — 自动恢复最大重试次数，默认 3

### 自定义参数示例

```
& "$env:USERPROFILE\.claude\skills\watchdog\watchdog.ps1" -ProjectPath "C:\Users\刘志强\.claude\projects\jiankong" -IdleMinutes 5 -PollSeconds 15
```

## 功能

- **三重检测**：进程存活 + JSONL 文件活跃度 + 输出 token 停滞
- **自动定位项目**：根据当前目录自动监控对应项目的会话
- **声音提醒**：卡住时终端 Beep 声
- **自动恢复**：确认卡住后自动启动 `claude --continue`，最多重试 3 次
- **事件日志**：记录到 `~/.claude/watchdog-state/events.log`

## 状态文件

- `~/.claude/watchdog-state/events.log` — 事件日志
- `~/.claude/watchdog-state/sessions.json` — 当前会话状态
