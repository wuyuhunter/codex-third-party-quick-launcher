# Changelog

## v0.5.0

- 将当前国产模型适配实验线升级为 `v0.5.0` 发布基准。
- 保留 no-config 路线：provider 定义、adapter 地址、KEY 选择和模型参数继续通过便携包 state 与进程级参数传入，不依赖 `~/.codex/config.toml`。
- 保留“模型系列 -> 模型版本 -> 推理深度”配置结构，聚合平台可在同一 provider 下勾选多个模型系列。
- 保留 MiniMax、Qwen、DeepSeek、GLM、Kimi 适配器路径，以及 `yanling`、`ciii_next`、`xiaolan` 对照 provider。
- “检查更新”继续只放在“关于”窗口中，不自动检查，避免新手频繁更新。
- “关于”窗口新增红色“更新验证标记：v0.5.0 国产模型适配发布版”，方便从旧版本升级后肉眼确认已经更新成功。
- 发布前执行脱敏、全局配置依赖、adapter、打包和本地升级路径检查。

## v0.4.3-update-checker

- “检查更新”入口移到“关于”窗口里，只给熟练用户保留，主界面不再直接提示更新。
- 更新源默认读取 Gitee raw 上的 `update/manifest.json`，支持 manifest 里声明版本号、下载地址、SHA256 和更新说明。
- 点击检查更新后会先比对版本，再下载更新包并校验 SHA256，确认后由独立 updater 覆盖当前安装目录。
- 更新过程保留 `state`、`logs`、`secrets`、`.omx` 等本机数据目录，不会把用户配置和本机 key 一起覆盖掉。
- 版本号同步升到 `0.4.3`，便于后续发布和更新日志追踪。

## v0.4.2-model-series-editor

- 配置窗口默认高度提升到 `1040`，宽度提升到 `1100`，KEY 区域继续保留在默认视窗内。
- “模型系列”和“此通道可用模型”改为左右并排；“默认模型”移动到下面一行薄下拉框。
- “模型系列”改为复选框列表，选中状态更明显，列表高度提升到 `180`。
- 修复可用模型空选择逻辑：新建服务默认勾选 OpenAI / GPT；但用户把可用模型全部取消后，列表和保存结果保持为空，不再自动回退到 `gpt-5.5/gpt-5.4/gpt-5.4-mini`。
- “模型和推理深度”页签重做为“模型系列和版本”：可以维护模型系列 ID、名称、该系列下的模型版本和默认模型。
- “模型系列和版本”页签调整为“系列 -> 版本 -> 深度”三列结构，系列、版本、深度均支持上移 / 下移。
- 服务配置页的模型系列列表高度提升到 `230`。
- 修复模型系列取消后重新勾选时默认模型下拉不刷新的问题；深度配置现在挂在模型版本下。
- 配置窗口默认宽度提升到 `1250`，最小宽度提升到 `1100`。
- “此通道可用模型”改为复选框列表；勾选模型系列时默认勾选当前系列可用的全部模型，并同步刷新默认模型下拉。

## v0.4.1-provider-model-capabilities

- 配置窗口默认高度提升到 `920`，最小高度提升到 `840`；服务列表、可用模型列表和 KEY 列表同步加高，避免 KEY 按钮被遮挡。
- 模型服务提供方列表新增“置顶 / 置底”，保留“上移 / 下移”，只调整顺序，不改默认 provider。
- 将“模型厂家”改为“模型系列”，并支持一个接入平台同时勾选多个模型系列；provider schema 新增 `vendorIds`，继续保留 `vendorId/vendorName` 兼容旧配置。
- “模型和推理模式”改为“模型和推理深度”，settings 新增 `modelReasoningEfforts`，每个模型可单独配置支持的推理深度。
- 启动页推理深度下拉框优先读取模型级配置；国产/国内通道默认只开放 `medium`，避免把 OpenAI/Codex 专用深度误传给不支持的模型。
- 调研官方文档后保守处理：OpenAI/Codex 保留 `low/medium/high/xhigh`，Qwen/GLM/DeepSeek/Kimi/MiniMax 先以模型级兼容配置承载，后续再做 vendor-specific thinking 参数转译。

## v0.4.0-provider-model-catalog

- 新增“模型厂家 -> 接入通道 -> 可用模型”三层配置：每个 provider 现在带 `vendorId`、`models` 和 `defaultModel`。
- 启动页模型下拉框按当前 provider 过滤，只显示这个接入通道可用的模型；切换 provider 时自动落到该通道默认模型。
- 命令行启动也会校验 provider/model 组合，传入错配模型时自动改为 provider 默认模型并打印提示。
- 配置页新增“模型厂家”“此通道可用模型”“默认模型”，新手只需选厂家并勾选模型，不再从全局模型池里手工猜。
- OpenAI / GPT 厂家模型池包含 `gpt-5.5`、`gpt-5.4`、`gpt-5.4-mini`，示例配置也同步到 v0.4 provider schema。
- Qwen 接入通道默认仅开放已验证稳定的 `qwen3.6-plus` 和 `qwen-plus`；`qwen-max` 保留在厂家目录中，需确认当前通道可用后再手动勾选。
- 继续保持 no-config 路线：所有 provider 定义仍随本次进程通过 `-c model_providers.<id>.*` 注入，不写入 `~/.codex/config.toml`。

## v0.3.32-no-config-domestic

- 新增 `minimax` provider，默认模型 `minimax2.7`，通过本机 adapter 转译到上游 `MiniMax-M2.7` Chat Completions。
- MiniMax 启动时同样不写 `~/.codex/config.toml`，Codex 侧继续使用临时 `-c model_providers.<id>.*` 参数和本机 adapter 地址。
- MiniMax adapter 对 Codex 的多段 system message 做合并，并清理上游返回中的 `<think>...</think>` 包裹，避免 `MiniMax-M2.7` 因 chat setting 或思考标签污染导致 smoke test 失败。
- 连通性测试默认模型补齐 `yanling`、`ciii_next`、`OpenAI/小蓝` 的 `gpt-5.5` 映射，避免国产实验默认模型误用于对照 provider。

## v0.3.31-no-config-domestic

- 启动 Codex 时不再向 `~/.codex/config.toml` 写入、同步或删除 provider；所有 provider 定义改为随本次进程通过 `-c model_providers.<id>.*` 临时传入。
- 本机 adapter 动态端口只出现在当前 Codex 进程参数中，不再保存到用户全局 Codex 配置。
- 读 settings/catalog 不再顺手保存配置，避免多个启动器进程并发读取时把实验 catalog 重置成默认 OpenAI。
- 默认 Codex 工作根设为用户目录；调用方显式传入 `-C` 或 `--cd` 时尊重调用方，避免 Codex CLI 因信任当前启动器目录而改写 `config.toml`。
- 重新恢复 Qwen、DeepSeek、GLM、Kimi 的独立上游地址和 KEY，不再误用环境里残留的 `ciii` KEY。

## v0.3.30-nightly-domestic

- 接手 `v0.3.29-exp-domestic` 作为 2026-05-08 晚间更新基准。
- 修复 Kimi K2 在 transport shim 后使用 `gpt-5.4` 作为 Codex 侧模型名时，adapter 未按真实上游模型 `kimi-k2.6` 套用 temperature / thinking 约束的问题。
- 修复便携实验包在继承旧 `CODEX_SWITCHER_HOME` 环境变量时误读其他安装目录 state，导致国产 provider 和模型列表缺失的问题。
- 启动器只复用当前版本的本机 adapter，避免旧进程继续提供已修复前的转译逻辑。

## v0.3.29-exp-domestic

- 本机适配器改为动态端口，不再把 `127.0.0.1:8787` 写成用户可见的 provider 地址。
- 新增 `state\domestic-adapter-runtime.json` 运行态记录，保存当前适配器端口、PID 和 wrapper lease。
- WT / Codex wrapper 持有适配器 lease，Codex 进程退出后释放 lease；lease 归零后自动停止适配器。
- 启动时会校验带随机 nonce 的 `/health` 签名，只复用当前启动器拉起的 `codex-domestic-responses-adapter`，如果 `8787` 被其他程序占用会自动换到 `8788` 等可用端口。
- 连通性测试按 provider 使用对应默认模型，避免用 Qwen 模型名误测 DeepSeek、GLM 或 Kimi。

## v0.3.28-exp-domestic

- 为国产模型增加 transport shim：Codex CLI 看到内置模型 `gpt-5.4`，本地适配器再转译到真实上游模型，例如 `qwen3.6-plus`。
- Qwen / DashScope 改为通过本地适配器代理 `/responses`，消除 TUI 对 `qwen3.6-plus` 的 unknown model metadata 警告。
- 启动日志会显示 `Transport model: gpt-5.4 -> upstream <真实模型>`，便于确认实际调用的国产模型。

## v0.3.27-exp-domestic

- 新增模型与推理档位绑定：GPT / Codex 类模型可用 `xhigh`，国产模型默认只显示并使用 `medium/high/low`。
- 启动时会校验所选模型支持的推理档位；例如给 `qwen3.6-plus` 传 `xhigh` 会自动降为 `medium`，给 `gpt-5.5` 传 `xhigh` 会保留。
- 全局推理档位列表恢复包含 `xhigh`，避免影响 GPT 模型使用。

## v0.3.26-exp-domestic

- 将 DeepSeek 默认推荐模型更新为 `deepseek-v4-pro` / `deepseek-v4-flash`，保留 `deepseek-chat` / `deepseek-reasoner` 作为兼容项。
- 将 GLM 默认推荐模型更新为 `glm-5.1`，适配器默认关闭 thinking，避免把推理过程当作最终回复输出。
- 将 Kimi 默认推荐模型更新为 `kimi-k2.6`，适配器兼容 Kimi K2 的 temperature / thinking 约束；保留 Moonshot v1 系列作为备用。
- 国产模型实验版默认推理档位调整为 `medium/high/low`，不再把 OpenAI 专用的 `xhigh` 放在默认档位中。

## v0.3.25-exp-domestic

- 将 Qwen 实验默认模型从 `qwen-plus` 切换为显式版本模型 `qwen3.6-plus`。
- 保留 `qwen-plus` 作为 DashScope 稳定别名备用。
- 更新 `qwen3.6-plus` 和 `qwen-plus` 的 Codex CLI 模型元数据参数，减少未知模型 fallback 提示和上下文预算误判。

## v0.3.24-exp-domestic

- 为 Qwen、DeepSeek、GLM 和 Kimi 实验模型补充 Codex CLI 模型元数据启动参数。
- 选择 `qwen-plus` 等第三方模型时自动传入 `model_context_window`、`model_auto_compact_token_limit` 和 `model_max_output_tokens`，避免 Codex 使用 fallback metadata。
- 继续保持国产模型实验版与稳定版隔离。

## v0.3.23-exp-domestic

- 新增国产 OpenAI-compatible 模型实验版，隔离验证 DeepSeek、DashScope/Qwen、GLM 和 Kimi。
- 默认模型列表加入 `qwen-plus`、`qwen-max`、`deepseek-chat`、`deepseek-reasoner`、`glm-4-plus`、`glm-5.1`、`moonshot-v1-32k` 和 `moonshot-v1-8k`。
- 新增本机 Responses-to-Chat 适配器，DeepSeek、GLM 和 Kimi 可通过 `127.0.0.1:8787` 供 Codex CLI 使用。
- 启动 Codex 或测试连通性时会自动拉起国产模型适配器；Qwen/DashScope 继续直连原生 Responses API。
- 本版本仅用于本机实验和复测，不作为公开无 KEY 发布包。

## v0.3.22

- 调整关于窗口布局，将 MIT、GitHub 和 Gitee 入口移动到左下角。
- 关于窗口链接文字和图标改为黑色，降低蓝色超链接对界面的视觉干扰。

## v0.3.21

- 修复多个启动器或脚本进程同时读取配置时，瞬时读取失败可能把便携配置重置为默认 OpenAI 的问题。
- 已有 `state\codex-quick-launcher-config.json` 读取失败时不再自动覆盖，避免误清除本机 provider 和 KEY。

## v0.3.20

- 修复便携版干净首次启动会自动读取本机 `~\.codex\config.toml` 和环境变量，并把本机模型服务与 KEY 写入 `state\codex-quick-launcher-config.json` 的问题。
- 干净便携包首次启动只生成不含 KEY 的 OpenAI 默认配置；旧版拆分 state 文件仍保留兼容迁移。
- 发布包继续排除运行日志和真实配置文件，避免误把本机 KEY 一起分发。

## v0.3.19

- 关于窗口的 GitHub 和 Gitee 入口改为打开真实公开仓库链接。
- README、SUPPORT 和安装/配置界面文案移除仓库待创建占位。
- 重编 Windows exe，并准备 GitHub/Gitee 同步发布包。

## v0.3.18

- 主页移除版本、作者、链接弱提示和“即将使用”详情框，保留更干净的核心选择面板。
- 新增 `关于` 窗口，集中展示版本、作者、软件说明、MIT、GitHub 和 Gitee 入口。
- 恢复 MIT 点击打开内置协议文件，GitHub / Gitee 使用图标加文字的可点击入口。
- PowerShell 标题栏显示当前版本和作者信息。
- 移除主页 `测试连通性` 右侧说明和检测返回后的状态提示。

## v0.3.17

- 修复历史恢复会话时旧会话配置把当前模型服务覆盖回 OpenAI 的问题。
- `resume` 命令会在会话参数后再次注入当前模型服务配置，确保外层选择的服务在恢复会话内继续生效。

## v0.3.16

- 修复使用自定义模型服务 KEY 启动 Codex 时仍提示缺少 `OPENAI_API_KEY` 的问题。
- 启动时会将当前选中的 KEY 同时写入服务自己的环境变量和 Codex CLI 兼容的 `OPENAI_API_KEY`。

## v0.3.15

- 安装并验证 .NET 8 SDK 构建链路。
- 新增 `tools/build-launcher.ps1`，用于从 `src/launcher/` 重编根目录 `Codex 便捷启动器.exe`。
- 新增 `BUILD.md` 和 `RELEASE_CONTENTS.md`，明确构建方式、源码组成、发布包内容和排除项。
- 更新 `.gitignore`，排除构建输出、临时压缩包、运行日志和真实配置。
- 重编 Windows exe，使根目录 exe 与当前源码版本对齐。

## v0.3.14

- 字体恢复为 v1.9.2 的 `Segoe UI` 配置。
- 主页左下角按钮恢复为 `测试连通性`。
- 启动、安装和配置窗口的版本/作者信息恢复到标题区副标题位置，不再放在右下角。
- 主页右上角按钮改为 `安装`、`配置`。
- MIT / GitHub / Gitee 信息恢复到标题区下方的弱提示位置。
- 主页连通性说明移动到 `测试连通性` 按钮右侧，连通性窗口顶部不再额外占一行说明。

## v0.3.13

- 主页左下角 `测试服务` 按钮改名为 `测试可用性`。

## v0.3.12

- 高级组件窗口改为和安装环境页一致的列表样式，增加状态列和滚动区域。
- 打开高级组件窗口时检测本机安装状态，已安装组件禁用安装按钮，仅未安装组件可操作。
- 高级组件入口从核心安装、完整安装按钮组中拆出，独立放在安装环境页左侧。
- 调整安装环境页中 PowerShell 7 和 Windows Terminal 的用途说明。
- 提高高级组件窗口高度，避免底部按钮被遮挡。

## v0.3.11

- 修复高级组件窗口打开失败时提示 `if` 无法识别的问题。
- 高级组件操作按钮统一右对齐并固定宽度。
- 调整 PowerShell 7 和 Windows Terminal 的用途说明，改为更适合普通用户理解的描述。

## v0.3.10

- 修复点击 `高级组件` 后窗口闪退的问题。
- 将高级组件弹窗改为独立顶层函数打开，减少 WPF 事件闭包导致的运行时风险。
- 高级组件按钮增加异常提示，后续即使打开失败也会显示原因，不再直接退出。

## v0.3.9

- 安装环境页新增 `高级组件` 入口。
- 高级组件按名称、用途和操作排列，支持用户自行安装 OMX 增强组件、Git for Windows、PowerShell 7、Windows Terminal。
- 高级组件不再放入默认完整安装流程，点击安装前会单独确认。

## v0.3.8

- Gitee 页脚标识改为更小的灰色单线图标，降低视觉抢占。
- 保留 Gitee 占位入口，不引入官方彩色商标资源。

## v0.3.7

- 页脚新增 Gitee 占位入口，样式与 GitHub 保持一致。
- Gitee 点击后先提示仓库链接待创建，后续可接入真实镜像仓库。
- README 和安装脚本占位信息增加 Gitee。

## v0.3.6

- 配置页右上角新增 `导出配置` 和 `导入配置`，用于一键迁移单配置文件。
- 导出前提醒配置可能包含 KEY，不要公开上传或外传。
- 导入前提醒会覆盖当前配置，并在导入后刷新模型服务、KEY、模型和推理模式列表。
- 修复安装环境窗口通过 Windows Terminal 启动完整安装时，带空格标题可能被拆成错误可执行文件的问题。
- 修复部分 `Start-Process` 调用的参数引用，降低路径带空格时找不到文件的风险。

## v0.3.5

- 将启动器定位文案中的区域表述改为“中文环境”和“本地网络环境”。
- 将旧的服务提供方界面文案统一为“模型服务提供方”。
- 安装环境中的镜像源提示去掉区域限定表述，改为更中性的“镜像源”。

## v0.3.4

- 页脚恢复右下角弱提示位置。
- GitHub 占位改为无边框图标加文字，和页脚文字垂直对齐。
- 安装环境中的区域表述统一为更自然的本地化表述。
- 新增 `LICENSE.zh-CN.md` 作为 MIT 协议中文参考译文，英文 `LICENSE` 保持为正式许可文本。
- 新增 `SUPPORT.md`，把联系邮箱放在支持文档中，不放入软件主界面。

## v0.3.3

- 底部版本、协议、GitHub 和作者信息改为左对齐。
- `MIT 协议` 改为可点击文字，点击后打开包内置的 `LICENSE` 文件。
- GitHub 信息改为内置图标占位，后续创建仓库后可接入跳转链接。
- 作者名统一为 `砚行`。

## v0.3.2

- 产品名改为 `Codex 便捷启动器`。
- 对外入口文件改名为 `Codex 便捷启动器.exe` 和 `启动 Codex 便捷启动器.cmd`。
- 启动页副标题增加自动换行，避免右侧按钮挤压时文字溢出窗口。
- 运行配置文件改名为 `state\codex-quick-launcher-config.json`，示例配置同步改名。

## v0.3.1

- 启动窗口、安装窗口、历史会话窗口、连通性测试窗口和服务配置窗口的字体优先级改为 `Microsoft YaHei UI, Segoe UI`。
- 目标是在 Windows 简体中文环境下让中文显示更自然，同时仍然只调用系统字体，不打包字体文件。

## v0.3.0

- 产品定位从“Codex 切换器”调整为“Codex 便捷启动器”。
- 面向中文环境下的 Windows 普通用户重写启动窗口、配置窗口、安装窗口文案。
- 将版本、MIT 协议、GitHub 占位和作者信息移动到底部弱提示位置。
- 作者更新为夏小曦、知晴、砚行。
- 新增开源准备材料：`README.md`、`CHANGELOG.md`、`LICENSE`、`.gitignore`、`PROJECT_STRUCTURE.md`。
- 清理发布结构：不带本机日志、不带空 `secrets/`、不带真实 KEY 配置。
- 活动配置文件改为单文件，并提供不含 KEY 的示例配置。

## v0.2.4

- 启动窗口改为可调整大小。
- 提高默认窗口高度，解决权限说明增加后摘要框被挤到窗口底部的问题。
- 收紧表单区域边距，让“即将使用 provider / KEY / 模型 / 权限”的摘要默认可见。

## v0.2.3

- 权限模式选择栏下方增加动态说明。
- 切换安全模式或全权限模式时，说明文字同步变化，明确告知本次启动权限行为。

## v0.2.2

- 启动窗口新增权限模式：安全模式、全权限模式 (YOLO)。
- 安全模式显式传入 `-a on-request -s workspace-write`，不受本机全局 YOLO 配置影响。
- 全权限模式显式传入 `--dangerously-bypass-approvals-and-sandbox`。
- 权限模式随服务、KEY、模型和推理强度一起保存。
- 程序配置合并为单文件，方便导入导出。

## v0.2.1

- 新增服务连通性测试。
- 每个 KEY 一行，并行检测 `/responses` 接口。
- 显示状态、HTTP 状态码、耗时、摘要和 base_url，不显示完整 KEY。

## v0.2.0

- 新增历史会话入口。
- 从本工具窗口读取本机 `.codex\sessions`，选择会话后执行 `codex resume <SESSION_ID> -C <session cwd>`。
- 恢复历史会话时带入当前服务、KEY、模型和推理配置。

## v0.1.0

- 初始便携版 Windows Codex 启动入口。
- 支持核心安装：Node.js/npm、npm 镜像源、Codex CLI、Codex 初始配置。
- 支持完整安装：在核心安装基础上补 PowerShell 7 和 Windows Terminal。
- 支持维护模型服务、KEY、模型和推理强度。




