# Codex 便捷启动器

Codex 便捷启动器是一个面向中文 Windows 用户的第三方桌面启动工具。它把 Codex CLI 的环境安装、模型服务配置、KEY 管理、模型选择、权限模式选择和历史会话恢复集中到一个简单的图形界面里，尽量减少普通用户直接操作命令行的成本。

开发这个软件的初衷，是希望能把好用的 AI 工具更轻松地分享给家人、朋友和同事，让他们不必先理解复杂的终端命令和配置文件，也能较快完成安装、配置并开始体验 AI 带来的便利和乐趣。

如果您已经熟悉命令行、脚本、开发环境和模型服务配置，也可以直接使用 Codex CLI、官方文档和更专业的开发工具。本项目更关注“快速上手”和“方便分享”，不是为了替代专业工作流。

本项目是第三方社区工具，不是 OpenAI 官方项目，也未获得 OpenAI 赞助、背书或关联授权。OpenAI、Codex、GPT 等名称属于其各自权利人；本项目仅在说明兼容对象和依赖关系时使用这些名称。

底层依赖 OpenAI Codex CLI，支持 OpenAI 及兼容 `/v1/responses` 的模型服务；当前版本也内置国产/国内模型适配路径，可通过本机 adapter 接入 Qwen、DeepSeek、GLM、Kimi、MiniMax 等 OpenAI-compatible Chat Completions 服务。安装流程优先使用本地网络更友好的镜像源，降低首次体验门槛。

## 国产模型适配

`v0.5.0` 起，本项目把国产模型适配作为一个稳定发布基准维护：

- 不依赖 `~/.codex/config.toml` 保存模型服务；启动时通过本次进程参数注入 provider。
- 支持“模型系列 -> 模型版本 -> 推理深度”的配置结构，聚合平台可以勾选多个模型系列。
- 对 Qwen、DeepSeek、GLM、Kimi、MiniMax 提供本机 adapter 转译路径，兼容新版 Codex CLI 的 Responses 调用方式。
- 可配置私有 OpenAI-compatible Responses 通道，方便用户在本机对照排查 provider 和模型映射问题。

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

## 构建

重编 Windows exe 需要 .NET 8 SDK。安装后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-launcher.ps1
```

构建脚本会从 `src/launcher/` 编译 exe，并覆盖根目录的 `Codex 便捷启动器.exe`。详细说明见 `BUILD.md`。

## 开源与分发

- 开源协议：MIT 协议，内置文本见 `LICENSE`。
- 中文参考译文：见 `LICENSE.zh-CN.md`，英文 `LICENSE` 是正式许可文本。
- 项目性质：第三方社区工具。不要使用 OpenAI 官方 Logo、图标、字体或其他品牌资产作为本项目标识。
- GitHub：https://github.com/wuyuhunter/codex-third-party-quick-launcher
- Gitee：https://gitee.com/wuyuhunter/codex-third-party-quick-launcher
- 支持与联系：见 `SUPPORT.md`。优先使用 GitHub Issues 和 Gitee Issues。
- 作者：夏小曦、知晴、砚行。

分发前建议检查：

1. `state\codex-quick-launcher-config.json` 不存在，或已经删除真实 KEY。
2. `logs/` 不包含本机路径、报错截图或个人信息。
3. `secrets/` 不存在，或为空。
4. `.omx/`、`.git/`、`artifacts/`、`src/**/bin/`、`src/**/obj/` 不进入发布包。
5. README、BUILD.md、RELEASE_CONTENTS.md、LICENSE、LICENSE.zh-CN.md、SUPPORT.md、SECURITY.md、CHANGELOG 保留在包内。

## 版本记录

历史更新已经重新整理为 `0.x` 产品线，见 `CHANGELOG.md`。
