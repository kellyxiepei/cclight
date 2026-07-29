# cclight-esp32

ESP32-C3 + MicroPython 固件:通过 USB 串口接收命令,控制外接 LED 开关。

## 硬件接线

- LED 正极(长脚)→ 330Ω 电阻 → **GPIO4**
- LED 负极(短脚)→ **GND**

如接到其他引脚或低电平点亮,改 `main.py` 顶部的 `LED_PIN` / `ACTIVE_HIGH`。

## 一次性准备:刷 MicroPython 固件

1. 下载 ESP32-C3 固件(.bin):https://micropython.org/download/ESP32_GENERIC_C3/
2. 安装工具(在项目 venv 里):

   ```bash
   source ../.venv/bin/activate
   pip install esptool mpremote
   ```

3. USB 连接开发板,找到串口设备(类似 `/dev/tty.usbmodem1101`):

   ```bash
   ls /dev/tty.usbmodem*
   ```

4. 擦除并刷入(把端口和 bin 文件名替换成你的):

   ```bash
   esptool.py --chip esp32c3 --port /dev/tty.usbmodem1101 erase_flash
   esptool.py --chip esp32c3 --port /dev/tty.usbmodem1101 write_flash -z 0 ESP32_GENERIC_C3-*.bin
   ```

## 烧录本程序

```bash
./burn.sh
```

脚本会自动探测 `/dev/tty.usbmodem*` 串口(多个设备或要指定时:`./burn.sh <port>`),
必要时把 mpremote 装进项目 venv,把 `main.py` 拷到板上并复位,复位后自动运行。
注意:烧录前要先停掉 cclight-mac agent(它占用串口),脚本检测到端口被占用会提示。

手动等价操作:

```bash
mpremote connect /dev/tty.usbmodem1101 cp main.py :main.py
mpremote connect /dev/tty.usbmodem1101 reset
```

## 手动测试

用 screen 直连串口(退出:`Ctrl-A` 然后 `K`):

```bash
screen /dev/tty.usbmodem1101 115200
```

输入命令并回车:

| 命令 | 回复 |
|---|---|
| `PING` | `PONG` |
| `LED ON` | `OK ON`(LED 亮) |
| `LED OFF` | `OK OFF`(LED 灭) |
| `STATUS` | `OK ON` / `OK OFF` |

Mac 端 agent(cclight-mac)用 pyserial 打开同一端口、按行读写即可。

## 注意

- 程序运行时占用了 USB 串口的 REPL 输入;要回到 REPL 交互,先 `Ctrl-C`
  中断程序(KeyboardInterrupt 会退出主循环)。
- 要临时禁用自动运行,可删除设备上的 main.py:
  `mpremote connect <port> rm :main.py`
