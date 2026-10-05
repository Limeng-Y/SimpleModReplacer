# Simple Mod Replacer

一个通用的 Windows 程序（含 Mod 数据）一键替换工具：**保留 Mods → 清理旧程序及残留 → 部署新版 → 还原 Mods**，全程日志记录。纯 PowerShell + 批处理实现，无需编译，双击即用。

适用于"绿色软件 + 用户数据目录（Mods）"的升级替换场景。例如一款《星露谷物语》（Stardew Valley，官方默许 SMAPI 模组生态）的模组管理器，升级程序本体时需要保留游戏的 Mods 目录。

> 文档中的 **ValleyKit**（含服务名、注册表项、路径）均为**虚构示例**，不指向任何真实软件。请替换为你自己目标程序的实际值。

---

## 为什么需要它

直接"删旧版 → 解压新版"会丢失用户 Mod，而先删后解压一旦压缩包路径错误/包损坏，旧程序已无法挽回。本工具的核心原则是：

> **任何删除操作发生之前，所有关键前提必须已验证通过。**

- ✅ **预检（Preflight）**：先检查全部路径、7z、磁盘空间，只报告不改动；致命问题直接终止
- ✅ **确认机制**：列出将要执行的全部操作，输入 `Y` 才开始（可 `-Yes` 跳过）
- ✅ **备份先行 + 完整性校验**：先备份 Mods，并用 `7z t` 验证压缩包可读，校验失败绝不删除旧程序
- ✅ **先暂存后删除**：新版先解压到暂存目录并验证非空，**之后才删除旧程序**，避免"删了却解压失败"
- ✅ **防呆保护**：禁止盘符根目录/系统关键目录作为删除目标；备份目录、暂存目录均不允许位于待删除目录内
- ✅ **失败可恢复**：若旧目录删除后部署失败，日志会给出暂存目录和备份文件路径
- ✅ **自动还原**：新版若没有 Mods 目录（未启动过、未生成），自动在原位置创建并还原
- ✅ **可选归档**：部署成功后可把新版压缩包移动到指定归档目录保存
- ✅ **详细日志**：每一步、7z 输出、错误原因均写入带时间戳的日志文件

---

## 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10 / 11（或带 PowerShell 5.1 的 Windows 7+） |
| PowerShell | 5.1 及以上（系统自带；无需额外安装） |
| 7-Zip | 已安装 7-Zip（自动探测常见安装路径与 PATH 中的 `7z.exe`） |
| 权限 | 管理员（清理服务 / `HKLM` 注册表需要；启动器会自动 UAC 提权） |

---

## 快速开始

1. 下载本项目两个文件，放在**同一个任意目录**：
   - `SimpleModReplacer.bat`（启动器）
   - `SimpleModReplacer.ps1`（主脚本，配置在这里）
2. 用记事本 / VS Code 打开 `SimpleModReplacer.ps1`，修改顶部 **「用户配置区」** 的参数。
3. 双击 `SimpleModReplacer.bat` → UAC 点「是」→ 查看预检结果 → 输入 `Y` 执行。
4. 同目录会生成 `SimpleModReplacer_<时间戳>.log`，出问题直接看日志。

无人值守（自动化 / Agent 调用）：

```powershell
powershell -ExecutionPolicy Bypass -File .\SimpleModReplacer.ps1 -Yes
```

或通过启动器：

```bat
SimpleModReplacer.bat -Yes
```

---

## 配置参数（用户配置区）

### 路径参数

| 变量 | 必填 | 说明 |
|------|------|------|
| `$DeleteDir` | ✅ | 旧程序目录。将被删除，新版也部署到这个原位置；不能是盘符根目录或系统关键目录 |
| `$BackupSrc` | ⭕ | 要保留的 Mods 目录。留空 `''` 则不备份；执行时不存在则部署后创建同名空文件夹 |
| `$BackupDst` | 条件必填 | 备份 `.7z` 的存放目录。指定了 `$BackupSrc` 时必填，**不能位于 `$DeleteDir` 之内** |
| `$ArchivePath` | ✅ | 新版压缩包文件路径（`.7z` / `.zip` / `.rar` 等 7z 支持的格式），预检时必须存在 |
| `$SevenZip` | ⭕ | `7z.exe` 完整路径；留空自动探测 |
| `$StageDir` | ⭕ | 新版**暂存解压目录**；留空使用系统 `%TEMP%`。系统盘空间紧张时可改到其它盘，必须是绝对路径且不能位于 `$DeleteDir` 之内 |
| `$NewVersionStore` | ⭕ | 新版压缩包**归档目录**；全部流程成功后把压缩包移动到此目录保存。留空则压缩包保留原位；与压缩包当前目录相同则跳过 |

### 残留清理参数（均可选）

| 变量 | 说明 |
|------|------|
| `$ServiceNames` | 要停止并删除的 Windows 服务名数组，如 `@('VKHelperSvc')`；无则 `@()` |
| `$RegKey` | 要清理的注册表键（PSDrive 形式）；不清理则留空 `''` |
| `$RegValueName` | 要删除的注册表**值名**（只删值，不删主键） |
| `$ShortcutName` | 桌面快捷方式名（不含 `.lnk`，自动跟随系统 Desktop 路径，兼容 OneDrive 重定向）；无则 `''` |

### 开关

| 变量 | 默认 | 说明 |
|------|------|------|
| `$KeepBackup` | `$false` | `$true` = Mods 还原后保留临时生成的备份压缩包；`$false` = 还原并校验文件数通过后自动删除（还原失败时始终保留） |

---

## 配置示例（虚构）

场景：升级一款虚构的星露谷物语模组管理器 **ValleyKit**，保留其管理的 Mods 目录，并清理它安装的后台服务、注册表标识与桌面快捷方式。

```powershell
# 路径
$DeleteDir    = 'D:\Games\ValleyKit'
$BackupSrc    = 'D:\Games\ValleyKit\Mods'
$BackupDst    = 'D:\Backup\ModArchives'
$ArchivePath  = 'C:\Users\YourName\Downloads\ValleyKit_v2.0.zip'
$SevenZip     = ''

# 残留清理 (不存在的项会自动跳过)
$ServiceNames = @('VKHelperSvc')                         # Stop-Service -> sc.exe delete
$RegKey       = 'HKCU:\SOFTWARE\ValleyKit'               # 只删 DeviceId 这个值, 主键保留
$RegValueName = 'DeviceId'
$ShortcutName = 'ValleyKit'

# 可选项
$StageDir        = 'D:\Temp\SMR'     # 暂存到 D 盘; 留空则用 %TEMP%
$NewVersionStore = 'D:\Archive\Apps' # 成功后把安装包移到这里; 留空则原位保留
$KeepBackup      = $false            # 还原成功后删除 Mods 备份包
```

没有任何残留时：

```powershell
$ServiceNames = @()
$RegKey       = ''
$RegValueName = ''
$ShortcutName = ''
```

> 注册表键必须使用 PowerShell PSDrive 前缀：`HKLM:\...` 或 `HKCU:\...`（不是 `HKEY_LOCAL_MACHINE\...`）。

---

## 执行流程

```
预检阶段(零改动)
  ├─ 7z.exe 是否可用
  ├─ 压缩包是否存在且为文件        ← 致命前置检查
  ├─ 删除地址合法性(非盘符根目录/非系统关键目录)
  ├─ Mods 源状态统计(文件数/大小)
  ├─ 备份目录/暂存目录/归档目录是否位于待删除目录之内  ← 致命检查
  └─ 暂存盘/目标盘空间(仅警告)
确认 (输入 Y; 或 -Yes 跳过)
步骤1 备份 Mods -> 7z t 完整性校验(失败即终止, 旧程序原样保留)
步骤2 新版压缩包解压到暂存目录 -> 单层顶层文件夹自动上移 -> 校验非空
步骤3 删除残留: 服务 -> 快捷方式 -> 注册表值 -> 旧程序目录
步骤4 暂存目录移动到 $DeleteDir (部署新版)
步骤5 还原 Mods 到原位置(不存在则建空文件夹) -> 文件数核对 -> 删除/保留备份包
步骤6 (可选) 新版压缩包移动到 $NewVersionStore 归档
```

**关键安全顺序**：备份校验 → 暂存验证 → 才允许删除。压缩包缺失、损坏、为空这三类问题都会在旧程序未受影响时暴露。

---

## 日志

- 位置：脚本同目录 `SimpleModReplacer_yyyyMMdd_HHmmss.log`（已被 `.gitignore` 排除）
- 内容：预检结果、每一步操作、7z 原始输出、警告与错误、失败时的恢复路径
- 编码：UTF-8 无 BOM

---

## 给 AI Agent 的说明

其它 Agent 可直接修改 `SimpleModReplacer.ps1` 顶部「用户配置区」的变量来适配新目标：

- 路径：`$DeleteDir` / `$BackupSrc` / `$BackupDst` / `$ArchivePath`
- 暂存与归档：`$StageDir`（空=`%TEMP%`）/ `$NewVersionStore`（空=原位保留）
- 残留三要素：`$ServiceNames[]` / `$RegKey` + `$RegValueName` / `$ShortcutName`
- 开关：`$KeepBackup`；命令行 `-Yes` 非交互执行

约定：

| 退出码 | 含义 |
|--------|------|
| `0` | 成功，或用户在确认时取消（未做任何修改） |
| `1` | 预检失败 / 备份或解压失败 / 删除部署失败（终止时旧程序状态见日志） |

脚本在任何致命终止时都会打印暂存目录（`<暂存根>\SMR_stage_*`）与备份文件路径，便于自动/手动恢复。

---

## 故障排查

| 现象 | 原因 / 处理 |
|------|-------------|
| 预检报「新版压缩包不存在」 | `$ArchivePath` 路径错误或文件未下载完成——这正是预检要拦截的情况，修正后重跑即可，旧程序未受影响 |
| 预检报「不能位于 `$DeleteDir` 之内」 | 备份/暂存/归档目录会随旧程序一起被删除或在删除时消失，改到程序目录之外 |
| 双击 bat 出现乱码/命令被截断 | 确认使用本仓库的纯 ASCII `.bat`；中文全部在 `.ps1`（UTF-8 BOM）中 |
| 7z 退出码 `1` | 警告（如个别文件锁定），脚本按成功处理并完整记录输出，请核对日志 |
| 服务删除失败 | 确认以管理员运行；驱动级服务可能需要重启后才完全消失 |
| 还原文件数与备份前不一致 | 日志会明确警告；此时备份包自动保留，请检查后手动恢复 |
| 归档步骤跳过 | 未配置 `$NewVersionStore`，或归档目录与压缩包当前所在目录相同 |

---

## 许可证

[MIT](LICENSE)
