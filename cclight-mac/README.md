# cclight-mac

MacOS 上的 Python agent:通过 USB 串口连接 cclight-esp32 芯片,
把芯片能力以 HTTP 接口暴露。基于 Flask + pyserial。

## 特性

- **同步接口**:每个 HTTP 请求都等芯片回复后才返回
- **自动发现**:扫描 `/dev/tty.usbmodem*`,用 `PING`/`PONG` 握手识别芯片
- **自动重连**:后台每 5s 心跳;断开(含拔 USB)后每 3s 重扫端口,插回自动恢复
- **全程日志**:连接/断开/重连、每条 HTTP 请求、每条串口命令及回复都打到 stdout

## 启动

前台运行:

```bash
source ../.venv/bin/activate
pip install -r requirements.txt
python agent.py
```

后台运行(日志写入 `agent.log`,PID 记录在 `agent.pid`):

```bash
./start_cclight.sh   # 已在运行则直接提示,不会重复启动
./stop_cclight.sh    # 优雅停止,5s 不退出则强杀
tail -f agent.log    # 实时看芯片状态/连接日志
```

默认监听 `127.0.0.1:8123`。环境变量:

| 变量 | 默认 | 说明 |
|---|---|---|
| `CCLIGHT_PORT` | (自动扫描) | 指定串口设备,跳过扫描 |
| `CCLIGHT_HOST` | `127.0.0.1` | HTTP 监听地址 |
| `CCLIGHT_HTTP_PORT` | `8123` | HTTP 监听端口 |

## HTTP 接口

| 方法 路径 | 动作 | 成功响应 |
|---|---|---|
| `POST /led/on` | 开灯 | `{"ok": true, "reply": "OK ON"}` |
| `POST /led/off` | 关灯 | `{"ok": true, "reply": "OK OFF"}` |
| `GET /led` | 查询 LED 状态 | `{"ok": true, "led": "on"}` |
| `GET /health` | 查询连接状态(不访问芯片) | `{"connected": true, "port": "/dev/tty.usbmodem1101"}` |

错误响应:芯片断开 → `503 {"ok": false, "error": "chip disconnected"}`;
回复超时 → `504`;芯片报错 → `502`。

## 测试

```bash
curl -X POST localhost:8123/led/on
curl -X POST localhost:8123/led/off
curl localhost:8123/led
curl localhost:8123/health
```
