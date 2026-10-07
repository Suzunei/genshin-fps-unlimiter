# 原神 FPS 自定义上限脚本

Windows 10/11 x64，兼容 Windows PowerShell 5.1 和 PowerShell 7。默认上限 **120 FPS**，可设置 **10–1000** 的整数。国服 `YuanShen.exe` 与国际服 `GenshinImpact.exe` 均可用。

脚本负责设置、下载校验与启动，实际解除 60 FPS 上限由 [z3lx/genshin-unlock](https://github.com/z3lx/genshin-unlock) 的原生后端完成。已固定并校验的版本为 **7.1.0**，适配原神 **7.1**；游戏更新后需要相应后端版本。没有使用写死的游戏内存地址。

## 最快开始

从 GitHub 克隆或下载本仓库后，无需复制配置示例；没有 `settings.json` 时脚本自动使用默认配置，成功启动或保存设置后会生成该文件。首次启动会下载并校验后端，因此需要访问 GitHub。仓库不包含本机配置、缓存或上游二进制。

1. 先正常关闭原神。
2. 双击本目录的 **start.cmd**。
3. 输入帧率上限，例如 `144`，或直接回车使用上次设置。
4. 脚本优先从米哈游启动器注册表查找客户端；找不到时，输入 **YuanShen.exe / GenshinImpact.exe** 的完整路径。也可以输入只包含其中一个客户端的游戏目录。不要选择 `launcher.exe`。
5. 启动时允许 Windows 的管理员提示；进入游戏后关闭游戏内垂直同步，并用帧率计检查实际 FPS。

脚本目录可以包含中文和空格。无需安装 Python 或 .NET。`start.cmd` 的执行策略设置仅作用于本次 PowerShell 进程，不会修改系统执行策略。

## 命令行

在此目录打开 PowerShell。第一次指定客户端路径，以后会记住：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\fps-unlock.ps1 -Fps 144 -GamePath 'D:\Games\Genshin Impact game\YuanShen.exe'
```

只保存上限，不启动游戏、不请求管理员权限：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\fps-unlock.ps1 -Mode Configure -Fps 165
```

使用保存的设置启动，不再显示输入提示：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\fps-unlock.ps1 -NonInteractive
```

查看配置和后端文件校验结果：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\fps-unlock.ps1 -Mode Status
```

可选：切到其他窗口时降至 10 FPS；此选项默认关闭，开启后记住设置。关闭时传入 `-BackgroundThrottle:$false`。

```powershell
.\fps-unlock.ps1 -Mode Configure -Fps 144 -BackgroundThrottle
.\fps-unlock.ps1 -Mode Configure -BackgroundThrottle:$false
```

**修改设置或更新后端前，请关闭游戏。** 配置文件会被插件持有；脚本避免在游戏运行时替换它们。设置将在下次通过本脚本启动时应用。

## 下载、离线安装和更新

首次启动缺少后端时，会从原作者 GitHub 发布地址下载。安装前验证发布包 SHA256，每次启动再验证 `loader.exe` 和 `plugin.dll` 的文件哈希。

已核对的 [7.1.0 发布页](https://github.com/z3lx/genshin-unlock/releases/tag/7.1.0) 与 [mod.zip 下载](https://github.com/z3lx/genshin-unlock/releases/download/7.1.0/mod.zip)，SHA256 来自 [GitHub 发布资产](https://github.com/z3lx/genshin-unlock/releases/expanded_assets/7.1.0)：

```text
7a46202bb2e7065fc226587499850b14bd901e8d3adb2b1e89afbb15915b3ddc
```

网络不通时，手动下载上面的 `mod.zip`，然后离线安装；这一步只解压和校验，不运行游戏：

```powershell
.\fps-unlock.ps1 -Mode Install -BackendArchive 'C:\Users\你的用户名\Downloads\mod.zip'
```

游戏更新后，获取原作者最新稳定版，仍要求 GitHub 提供 SHA256：

```powershell
.\fps-unlock.ps1 -Mode Update
```

`Install` 安装本文固定的 7.1.0，`Update` 获取最新稳定版；新版如果改变配置接口，包装脚本也可能需要调整。安装保留其他版本目录，成功后才更新 `backend.json`。不要混用不同版本的 EXE 和 DLL。

## 文件

- `fps-unlock.ps1`：入口脚本。
- `FpsUnlock.Core.ps1`：配置、哈希校验、后端安装与版本检查。
- `start.cmd`：双击入口。
- `settings.example.json`：默认配置示例，可按需复制成 `settings.json`。
- `settings.json`：本地生成的帧数、客户端路径和后台节流设置，不提交到 Git。
- `backend.json`：当前后端版本与文件哈希。
- `backend/<版本>/`：解帧后端及生成的配置文件。
- `cache/`：已校验的原作者发布包。
- `THIRD_PARTY_LICENSE.txt`：原作者 MIT 许可证。

`backend.json`、`backend/` 与 `cache/` 也由脚本在本地生成，已加入 `.gitignore`。

额外的 FOV 功能默认关闭；上游没有“禁用快捷键”的配置值，因此相关键改为通常不在键盘上的 F24/F23/F22，避免方向键误触。显示模式、分辨率和手机 UI 使用游戏原有设置。后台节流默认关闭。

## 故障排查与边界

- **仍然只有 60 FPS**：确认通过脚本启动、游戏内垂直同步已关闭，并检查显卡驱动、RTSS 等是否另有限帧。设定上限并不保证硬件能达到该帧数。
- **版本不兼容**：运行 `-Mode Update`。如果上游尚未适配当前游戏版本，等待更新。脚本不会绕过版本检查。
- **文件缺失或校验失败**：用 `-Mode Install` 重新安装固定版本，或用 `-Mode Update` 安装最新稳定版。
- **下载失败**：使用上面的离线安装。脚本不会关闭 TLS 证书校验，也不会自动关闭安全软件；若安全软件阻止了后端，请自行核实来源。
- **已检测到游戏进程** 仅代表进程启动，不能据此确认解帧成功。实际 FPS 需要在游戏中验证。加载器完成后退出，脚本窗口无需持续打开。
- 插件会在运行时修改游戏行为，不改写客户端安装文件；这是第三方功能，原作者也提示可能违反游戏条款并存在账号风险，[见原项目说明](https://github.com/z3lx/genshin-unlock#disclaimer)。

本次验证覆盖脚本解析、配置、离线安装、哈希检测与版本检查；未启动实际游戏，尚未验证游戏内解帧效果。
