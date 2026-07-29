# cclight

用一盏 LED 灯提示 Claude Code 状态:Claude 等你输入时亮灯,干活时灭灯。

- **cclight-esp32/** — ESP32-C3 + MicroPython 固件,USB 串口收命令控制 LED
- **cclight-mac/** — Mac 端 agent,把芯片能力暴露为 HTTP 接口,并通过
  Claude Code hooks 联动亮灭灯

## 一条命令安装(Mac 端)

```bash
curl -fsSL https://raw.githubusercontent.com/kellyxiepei/cclight/main/bootstrap.sh | bash
```

自动完成:拉取代码 → 检查 python3(≥3.9)→ 安装 agent 到 `~/.cclight-mac`
(含独立 venv 和依赖)→ 配置 Claude Code 全局 hooks(原配置自动备份)。

装完后:

```bash
~/.cclight-mac/start_cclight.sh   # 启动 agent(后台)
```

再重启 Claude Code 使 hooks 生效。板子端的刷固件/烧录见
[cclight-esp32/README.md](cclight-esp32/README.md)(`./burn.sh` 一键烧录)。

## 一条命令卸载

```bash
curl -fsSL https://raw.githubusercontent.com/kellyxiepei/cclight/main/cclight-mac/uninstall.sh | bash
```

停掉 agent、从 `~/.claude/settings.json` 移除 cclight hooks(自动备份,
你自己的配置不受影响)、删除 `~/.cclight-mac`。本地装好的机器上也可以直接跑
`~/.cclight-mac/uninstall.sh`。

## 手动安装

```bash
git clone https://github.com/kellyxiepei/cclight.git
cclight/cclight-mac/install.sh
```

详细文档:[cclight-mac/README.md](cclight-mac/README.md)
