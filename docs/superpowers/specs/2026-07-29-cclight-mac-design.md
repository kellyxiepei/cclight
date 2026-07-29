# cclight-mac 设计文档

日期:2026-07-29

## 目标

MacOS 上的 Python agent:通过 USB 串口连接 cclight-esp32 芯片,
把芯片能力(LED 开关/状态)以 HTTP 接口暴露。

## 要求

1. 每个操作打印日志,能随时从日志看到芯片状态、连接状态
2. HTTP 接口同步:等芯片回复后再响应客户端
3. 自动重连,保证长时间稳定运行

## 技术栈

Python + Flask(同步 WSGI,代码可读性好)+ pyserial,复用项目根 `.venv`。

## 结构

- `cclight-mac/agent.py` — Flask app + `ChipConnection` 串口管理器
- `cclight-mac/requirements.txt` — flask, pyserial
- `cclight-mac/README.md` — 启动方法与接口文档

## ChipConnection(核心)

- **自动发现**:优先用 `CCLIGHT_PORT` 环境变量;否则扫描
  `/dev/tty.usbmodem*`,逐个发 `PING`,回 `PONG` 即为目标芯片。
- **同步命令**:`send_command(cmd)` 持线程锁写一行、超时(2s)读一行回复;
  Flask 多线程下串口不被并发访问。
- **自动重连**:后台线程,已连接时每 5s 心跳 `PING`;心跳或任何读写异常 →
  标记断开、关串口 → 每 3s 重扫端口直到恢复。拔插 USB 可自动恢复。
- **断开期间**:HTTP 请求立即返回 503,不阻塞。

## HTTP 接口(JSON,均同步等芯片回复)

| 方法 路径 | 动作 | 成功响应 |
|---|---|---|
| `POST /led/on` | 开灯 | `{"ok": true, "reply": "OK ON"}` |
| `POST /led/off` | 关灯 | `{"ok": true, "reply": "OK OFF"}` |
| `GET /led` | 查询 LED 状态 | `{"ok": true, "led": "on"}` |
| `GET /health` | 查询连接状态(不访问芯片) | `{"connected": true, "port": "..."}` |

错误:断开 → 503 `{"error": "chip disconnected"}`;超时 → 504。

## 日志

`logging` → stdout,含时间戳。覆盖:启动、端口扫描/发现、连接建立/断开/
重连尝试、每条 HTTP 请求、每条串口命令及回复、心跳失败原因。
