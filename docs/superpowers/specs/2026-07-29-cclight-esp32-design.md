# cclight-esp32 设计文档

日期:2026-07-29

## 目标

在 ESP32-C3(MicroPython)上运行一个固件程序,通过 USB 串口接收 Mac 端
Python agent 发来的命令,控制一个外接 LED 的开关。

## 硬件

- 芯片:ESP32-C3,使用原生 USB CDC 串口(Mac 上显示为 `/dev/tty.usbmodem*`)
- LED:外接,默认 GPIO4,高电平点亮
- 引脚与极性在 `main.py` 顶部配置:`LED_PIN = 4`、`ACTIVE_HIGH = True`

## 通信协议

文本行协议,一行一条命令,大小写不敏感,忽略空行:

| 命令 | 动作 | 回复 |
|---|---|---|
| `LED ON` | 点亮 LED | `OK ON` |
| `LED OFF` | 熄灭 LED | `OK OFF` |
| `STATUS` | 查询状态 | `OK ON` / `OK OFF` |
| `PING` | 探测设备 | `PONG` |
| 其他 | 无 | `ERR unknown command` |

## 实现

- `cclight-esp32/main.py`:上电自动运行。用 `select.poll` 监听 `sys.stdin`
  的非阻塞主循环 + 命令分发。主循环包 try/except,异常时回复 `ERR <原因>`
  而不是崩溃,保证设备始终可响应。
- `cclight-esp32/README.md`:刷 MicroPython 固件、用 mpremote 烧录、
  用 screen/mpremote 手动测试的步骤。

## 不做的事(YAGNI)

- 不做亮度/PWM、不做多灯、不做二进制协议、不做 WiFi。
