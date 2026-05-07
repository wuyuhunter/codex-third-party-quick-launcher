# Codex 便捷启动器 v0.3.13

面向中文环境下 Windows 用户的 Codex 启动入口。目标是让普通用户少碰命令行：安装运行环境、配置模型服务、选择模型和权限模式，然后直接启动 Codex。

底层依赖 OpenAI Codex CLI，支持 OpenAI 及兼容 `/v1/responses` 的模型服务。安装流程优先使用本地网络更友好的镜像源，降低首次体验门槛。

## 快速使用

1. 双击 `Codex 便捷启动器.exe`。
2. 如果电脑还没有运行环境，点击 `安装`，优先执行 `核心安装`。
3. 点击 `配置`，填写模型服务地址、KEY、模型列表和推理强度。
4. 回到启动窗口，选择模型服务提供方、KEY、模型、推理模式和权限模式。
5. 点击 `启动 Codex`。

也可以运行 `启动 Codex 便捷启动器.cmd`，方便在没有使用 exe 的情况下从源码启动。

## 高级组件

`安装环境` 页面左侧提供 `高级组件` 入口。组件按名称、用途、状态和操作排列，进入时会检测本机安装状态；已安装组件不可重复安装，未安装组件可自行选择安装：

- `OMX 增强组件`：面向进阶 Codex 工作流，提供计划、任务、记忆、插件和协作能力。
- `Git for Windows`：用于 GitHub/Gitee 仓库同步和开源协作。
- `PowerShell 7`：给高级脚本和部分工具提供新版 PowerShell 环境。
- `Windows Terminal`：提供标签页终端窗口，安装或启动 Codex 时更容易查看输出。

高级组件不会随核心安装自动安装，安装前会弹出确认。

## 权限模式

`安全模式` 是默认选项，会显式传入：

```powershell
-a on-request -s workspace-write
```

这会覆盖本机全局 YOLO 配置，确保本次启动真的按安全模式运行。

`全权限模式 (YOLO)` 会显式传入：

```powershell
--dangerously-bypass-approvals-and-sandbox
```

它不会逐步询问确认，命令也不受 Codex 沙箱限制。只在完全信任当前目录和任务时使用。

权限模式会和服务、KEY、模型、推理强度一起保存。上次选择 YOLO，下次打开仍会默认 YOLO。

## 配置文件

运行时只使用一个程序配置文件：

```text
state\codex-quick-launcher-config.json
```

这个文件会保存模型服务地址、KEY、模型列表、默认选择和权限模式，方便导入导出。KEY 是明文保存的，分发给朋友、家人、同事或上传 GitHub 前，请删除这个文件。

配置页右上角提供 `导出配置` 和 `导入配置`：

- 导出前会提醒配置可能包含 KEY，请只在自己的设备之间迁移。
- 导入前会提醒覆盖当前配置，建议先导出备份。

仓库内提供的 `state\codex-quick-launcher-config.example.json` 是不含真实 KEY 的示例。

## 目录说明

必要目录和文件见 `PROJECT_STRUCTURE.md`。当前成品包刻意不带 `logs/` 和 `secrets/`：

- `logs/` 是运行日志，启动后需要时自动产生。
- `secrets/` 是旧版本兼容目录，当前单配置文件流程不需要默认保留。
- `state/` 只保留安全示例配置，真实配置由程序运行后生成。
- `src/launcher/` 保留 Windows exe 包装器源码，主逻辑仍在 `tools/` 脚本中。

## 开源与分发

- 开源协议：MIT 协议，内置文本见 `LICENSE`。
- 中文参考译文：见 `LICENSE.zh-CN.md`，英文 `LICENSE` 是正式许可文本。
- GitHub：待创建。创建仓库后，把 README 里的占位改成真实链接。
- Gitee：待创建。建议作为国内镜像和备用下载入口，创建后同步到 README。
- 支持与联系：见 `SUPPORT.md`，临时联系邮箱为 `wuyuhunter@126.com`。
- 作者：夏小曦、知晴、砚行。

分发前建议检查：

1. `state\codex-quick-launcher-config.json` 不存在，或已经删除真实 KEY。
2. `logs/` 不包含本机路径、报错截图或个人信息。
3. `secrets/` 不存在，或为空。
4. README、LICENSE、LICENSE.zh-CN.md、SUPPORT.md、SECURITY.md、CHANGELOG 保留在包内。

## 版本记录

历史更新已经重新整理为 `0.x` 产品线，见 `CHANGELOG.md`。
