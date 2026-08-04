# cclight 状态语言 v2 设计文档

日期:2026-07-29

## 目标

把"亮/灭"1 比特信号升级为四态灯效,区分打断优先级。

## 状态语言

| 灯效 | 含义 | hook 来源 |
|---|---|---|
| 呼吸(3s 三角波) | Claude 干活中(含压缩上下文) | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`(工具事件负责在授权通过后把灯从快闪拉回呼吸,因为没有"授权通过"事件), `PreCompact`(压缩确认后转呼吸) |
| 快闪(5Hz) | 权限请求,值得马上回来 | `PermissionRequest`(弹框前即触发),`Notification` 兜底(其派发有 1-3s 延迟,claude-code#19627) |
| 双闪(闪两下停一拍,1.2s 循环) | 出错/测试失败 | 暂不接 hook,仅 HTTP 能力 |
| 熄灭 | 待命等输入(回答完毕/会话启动/会话结束) | `Stop`, `SessionStart`, `SessionEnd` |

## 协议(串口)

`LED BREATH|FLASH|DOUBLE|ON|OFF` → `OK <MODE>`;`STATUS` → `OK <MODE>`;
`PING` → `PONG`。`LED ON`(常亮)供接线调试,HTTP 同样暴露 `/led/on`。

## 实现

- 固件:GPIO4 改 PWM(1kHz),主循环 20ms 节拍 = `poll(20)` 收命令 +
  `led.tick()` 按 `ticks_ms` 刷新波形。
- agent:`POST /led/<mode>`(breath/flash/double/on/off,其他 404;
  on 为常亮,调试用),`GET /led` 返回 `{"mode": "<小写模式>"}`。
- install.sh:hook 映射按上表;重跑安装即迁移(幂等),固件需重新烧录。

## 不做的事(YAGNI)

- 出错事件自动检测(需解析 PostToolUse 输出,下一轮再说)
- 等待超时升级、RGB 颜色、多会话
