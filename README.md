# Simple Mod Replacer

Windows 程序一键替换工具。在保留用户 Mods 目录的前提下，完成旧版本清理与新版部署，全程写入日志。

## 使用 AI Agent 适配

如需适配自己的程序，可将本仓库链接交给任意 AI Agent，并提供目标程序的以下信息，由 Agent 修改 `SimpleModReplacer.ps1` 顶部配置区：

- 旧程序目录、Mods 目录、新版压缩包路径
- 需要清理的 Windows 服务名、注册表值、桌面快捷方式名（没有则不填）

## 功能

- 替换前先进行预检：验证全部配置路径与 7z 环境，确认后才开始执行
- 备份 Mods 目录，并用 7z 测试备份包完整性，校验失败则不执行删除
- 新版先解压到暂存目录验证，通过后才删除旧程序
- 清理残留：服务、桌面快捷方式、注册表值（均可配置，不存在的项自动跳过）
- 新版部署后将 Mods 还原到原位置；源目录不存在时创建同名空目录
- 可选：成功后归档新版压缩包；可选保留或自动删除 Mods 备份包
- 防呆检查：拒绝盘符根目录/系统关键目录作为删除目标；备份目录、暂存目录不允许位于待删除目录之内
- 日志：每一步操作、7z 输出、失败原因均记录到带时间戳的日志文件

## 环境要求

- Windows 10 / 11（或带 PowerShell 5.1 的系统）
- 已安装 7-Zip（自动探测常见安装路径及 PATH 中的 `7z.exe`）
- 管理员权限（清理服务、注册表需要；启动器自动请求提权）

## 使用方法

1. 将 `SimpleModReplacer.bat` 与 `SimpleModReplacer.ps1` 放在同一目录。
2. 编辑 `SimpleModReplacer.ps1` 顶部「用户配置区」，填写目标程序的路径与残留项。
3. 双击 `SimpleModReplacer.bat`，在 UAC 中允许提权，查看预检结果后输入 `Y` 执行。
4. 日志生成于脚本同目录，文件名为 `SimpleModReplacer_<时间戳>.log`。

非交互执行（跳过确认）：

```powershell
powershell -ExecutionPolicy Bypass -File .\SimpleModReplacer.ps1 -Yes
```

```bat
SimpleModReplacer.bat -Yes
```

## 配置参数

### 路径

| 变量 | 必填 | 说明 |
|------|------|------|
| `$DeleteDir` | 是 | 旧程序目录。将被删除，新版部署到该位置。不允许为盘符根目录或系统关键目录 |
| `$BackupSrc` | 否 | 要保留的 Mods 目录。留空 `''` 则不备份；执行时不存在则部署后创建同名空目录 |
| `$BackupDst` | 条件 | 备份包存放目录。设置了 `$BackupSrc` 时必填；不允许位于 `$DeleteDir` 之内 |
| `$ArchivePath` | 是 | 新版压缩包路径（`.7z` / `.zip` / `.rar` 等 7z 支持的格式），预检时必须存在 |
| `$SevenZip` | 否 | `7z.exe` 完整路径；留空自动探测 |
| `$StageDir` | 否 | 新版暂存解压目录；留空使用系统 `%TEMP%`。必须为绝对路径且不允许位于 `$DeleteDir` 之内 |
| `$NewVersionStore` | 否 | 新版压缩包归档目录；全部流程成功后将压缩包移动到该目录。留空则保留原位 |

### 残留清理（均可选）

| 变量 | 说明 |
|------|------|
| `$ServiceNames` | 需要停止并删除的 Windows 服务名数组，如 `@('VKHelperSvc')`；无则写 `@()` |
| `$RegKey` | 注册表键，使用 PSDrive 前缀（`HKLM:\` / `HKCU:\`）；不清理则留空 `''` |
| `$RegValueName` | 要删除的注册表值名（仅删除该值，保留主键） |
| `$ShortcutName` | 桌面快捷方式名称，不含 `.lnk`；无则留空 `''` |

### 开关

| 变量 | 默认 | 说明 |
|------|------|------|
| `$KeepBackup` | `$false` | `$true`：还原后保留 Mods 备份包；`$false`：还原校验通过后删除（还原失败时始终保留） |

## 配置示例

以下示例中程序名、服务名、注册表项均为虚构（假设一款《星露谷物语》模组管理器 ValleyKit），请替换为实际值。

```powershell
# 路径
$DeleteDir    = 'D:\Games\ValleyKit'
$BackupSrc    = 'D:\Games\ValleyKit\Mods'
$BackupDst    = 'D:\Backup\ModArchives'
$ArchivePath  = 'C:\Users\YourName\Downloads\ValleyKit_v2.0.zip'
$SevenZip     = ''

# 残留清理
$ServiceNames = @('VKHelperSvc')
$RegKey       = 'HKCU:\SOFTWARE\ValleyKit'
$RegValueName = 'DeviceId'
$ShortcutName = 'ValleyKit'

# 可选项
$StageDir        = 'D:\Temp\SMR'
$NewVersionStore = 'D:\Archive\Apps'
$KeepBackup      = $false
```

无残留需要清理时：

```powershell
$ServiceNames = @()
$RegKey       = ''
$RegValueName = ''
$ShortcutName = ''
```

## 执行流程

```
预检（不修改任何文件）
  - 7z.exe 可用性
  - 压缩包存在性
  - 删除目标合法性（非盘符根目录/非系统关键目录）
  - 备份目录/暂存目录/归档目录不位于待删除目录之内
  - 磁盘空间提示
确认（输入 Y 继续；-Yes 跳过）
步骤1 备份 Mods，测试备份包完整性
步骤2 解压新版到暂存目录并验证
步骤3 删除服务、快捷方式、注册表值、旧程序目录
步骤4 部署新版
步骤5 还原 Mods，核对文件数，按配置处理备份包
步骤6 归档新版压缩包（可选）
```

## 日志

- 位置：脚本同目录 `SimpleModReplacer_yyyyMMdd_HHmmss.log`
- 编码：UTF-8
- 失败终止时会记录暂存目录与备份包路径，可据此手动恢复

## 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 执行成功；或用户在确认阶段取消（未做任何修改） |
| 1 | 预检未通过或执行失败（详见日志） |

## 故障排查

| 现象 | 处理 |
|------|------|
| 预检提示压缩包不存在 | 检查 `$ArchivePath`，修正后重新执行；旧程序不受影响 |
| 预检提示目录不允许位于待删除目录之内 | 将备份/暂存/归档目录改到 `$DeleteDir` 之外 |
| 双击 bat 出现乱码或命令被截断 | 使用仓库原版的 `.bat`（纯 ASCII）；中文内容均在 `.ps1`（UTF-8 BOM）中 |
| 7z 退出码 1 | 属警告（如个别文件被占用），脚本视为成功，核对日志即可 |
| 服务删除失败 | 确认已以管理员运行；驱动级服务可能需重启后完全移除 |
| 还原文件数与备份前不一致 | 备份包会自动保留，核对后手动恢复 |

## 许可证

[MIT](LICENSE)
