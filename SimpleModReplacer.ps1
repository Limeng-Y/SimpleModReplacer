# ============================================================
#  Simple Mod Replacer - 通用程序(Mod)一键替换工具
#  安全流程:
#    预检(不改动任何东西) -> 用户确认
#    -> 备份 Mods 并校验压缩包完整性
#    -> 先把新版压缩包解压到临时目录并验证(成功后才动旧程序)
#    -> 删除服务/快捷方式/注册表/旧程序目录
#    -> 部署新版 -> 还原 Mods -> 删除备份包
#  用法: 双击同目录 SimpleModReplacer.bat (自动请求管理员权限)
#        自动化: powershell -ExecutionPolicy Bypass -File .\SimpleModReplacer.ps1 -Yes
#  日志: 脚本同目录 SimpleModReplacer_<时间戳>.log
# ============================================================
param(
    [switch]$Yes          # 跳过交互确认 (供自动化 / AI agent 调用)
)

# ==================== 用户配置区 (关键参数) ====================
# [必填] 旧程序目录: 将被删除, 新版也部署到此原位置
$DeleteDir    = 'D:\all\game\game_tool\Rocket'

# [可选] 要保留的 Mods 目录; 留空 '' 表示不备份/不还原
#        若该目录在执行时不存在, 部署后会在原位置创建同名空文件夹
$BackupSrc    = 'D:\all\game\game_tool\Rocket\backing\Mods'

# [必填] 备份压缩包的临时存放目录 (必须在 $DeleteDir 之外, 否则会被一起删除)
$BackupDst    = 'D:\all\game\game_tool\R_B'

# [必填] 新版程序压缩包路径 (7z 支持的格式: .7z/.zip/.rar 等)
$ArchivePath  = 'D:\all\game\game_tool\R_B\Rocket.zip'

# [可选] 7z.exe 完整路径; 留空 '' 自动探测
$SevenZip     = ''

# ---------- 残留清理示例 (按目标程序实际情况修改) ----------
# 要停止并删除的 Windows 服务名数组; 没有则写 @()
# 示例: 某网络抓包驱动安装了内核服务 -> @('WinDivert','WinDivert14')
$ServiceNames = @('WinDivert', 'WinDivert14')

# 要删除的注册表"值": 仅删除该值, 不删除主键; 不清理则把 $RegKey 留空 ''
# 示例: 程序在 HKLM 下写入机器码
$RegKey       = 'HKLM:\SOFTWARE\SystemRuntimeData'
$RegValueName = 'Rocket_id'

# 要删除的桌面快捷方式名称 (不含 .lnk); 没有则留空 ''
$ShortcutName = 'Rocket'

# ---------- 选项 ----------
$KeepBackup   = $false   # $true = 还原成功后保留备份压缩包; 默认还原验证通过后删除
# ==============================================================

# 路径规整
$DeleteDir   = "$DeleteDir".TrimEnd('\')
$BackupSrc   = "$BackupSrc".TrimEnd('\')
$BackupDst   = "$BackupDst".TrimEnd('\')
$ArchivePath = "$ArchivePath".TrimEnd('\')

# ---------- 自提权 (管理员) ----------
$wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
if (-not $prp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    $elevArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Yes) { $elevArgs += '-Yes' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $elevArgs -Verb RunAs
    exit
}
try { chcp 65001 > $null; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ---------- 派生变量 ----------
$Ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $PSScriptRoot "SimpleModReplacer_$Ts.log"
$Stage   = Join-Path $env:TEMP "SMR_stage_$Ts"

# ---------- 日志 ----------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Log([string]$Message) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $line
    [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", $utf8NoBom)
}
function Stop-With([string]$Message, [int]$Code = 1) {
    Write-Log "[错误] $Message"
    Write-Log '---- 流程终止 ----'
    if (Test-Path -LiteralPath $Stage) {
        Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ''
    Write-Host "已终止: $Message" -ForegroundColor Red
    Read-Host '按回车键关闭'
    exit $Code
}

# ---------- 7z 探测 ----------
function Get-SevenZip {
    if ($SevenZip -and (Test-Path -LiteralPath $SevenZip)) { return $SevenZip }
    foreach ($c in @('C:\Program Files\7-Zip\7z.exe','C:\Program Files (x86)\7-Zip\7z.exe')) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $g = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $null
}

# 7z 退出码 0=成功 1=警告(视为成功)
function Test-7zOk { $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1 }

function Get-FreeGB([string]$Path) {
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        return [math]::Round((New-Object System.IO.DriveInfo($root)).AvailableFreeSpace / 1GB, 2)
    } catch { return -1 }
}

Write-Log '============================================================'
Write-Log "Simple Mod Replacer 开始  时间戳 $Ts"
Write-Log '============================================================'

# ============================================================
# 预检阶段: 只检查, 不做任何修改 (任何致命问题都在删除前暴露)
# ============================================================
Write-Log '[预检] 开始检查所有路径与环境 (本阶段不修改任何文件)'
$preErrors = @()
$preWarns  = @()

# 1. 7z
$sz = Get-SevenZip
if (-not $sz) { $preErrors += '未找到 7z.exe, 请安装 7-Zip 或在配置区指定 $SevenZip' }

# 2. 删除地址: 必填、绝对路径、不能是盘符根目录/系统关键目录
if ([string]::IsNullOrWhiteSpace($DeleteDir)) {
    $preErrors += '$DeleteDir (旧程序目录) 不能为空'
} elseif (-not [System.IO.Path]::IsPathRooted($DeleteDir)) {
    $preErrors += "`$DeleteDir 必须是绝对路径: $DeleteDir"
} else {
    $norm = $DeleteDir.TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($DeleteDir).TrimEnd('\')
    if ($norm -eq $root) { $preErrors += "`$DeleteDir 不能是盘符根目录: $DeleteDir" }
    foreach ($bad in @($env:SystemRoot, ${env:ProgramFiles}, ${env:ProgramFiles(x86)}, $env:USERPROFILE)) {
        if ($bad -and $norm -ieq "$bad".TrimEnd('\')) { $preErrors += "`$DeleteDir 不能是系统关键目录: $DeleteDir" }
    }
    if (Test-Path -LiteralPath $DeleteDir) { Write-Log "  [OK] 旧程序目录存在: $DeleteDir" }
    else { $preWarns += "旧程序目录当前不存在(全新安装模式), 将只部署新版: $DeleteDir" }
}

# 3. 压缩包: 必须存在且是文件 (这是上次事故的根因 -> 致命检查)
if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $preErrors += '$ArchivePath (新版压缩包) 不能为空'
} elseif (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    $preErrors += "新版压缩包不存在: $ArchivePath"
} else {
    $arcMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 1)
    Write-Log "  [OK] 新版压缩包存在 ($arcMB MB): $ArchivePath"
}

# 4. 备份源
$srcSize = 0L; $srcFiles = 0
if ($BackupSrc) {
    if (Test-Path -LiteralPath $BackupSrc -PathType Container) {
        $m = Get-ChildItem -LiteralPath $BackupSrc -Recurse -File -Force -ErrorAction SilentlyContinue
        $srcFiles = @($m).Count
        $srcSize  = ($m | Measure-Object -Property Length -Sum).Sum
        if (-not $srcSize) { $srcSize = 0 }
        Write-Log ("  [OK] Mods 源存在: {0} ({1} 个文件, {2} MB)" -f $BackupSrc, $srcFiles, [math]::Round($srcSize/1MB,1))
    } else {
        $preWarns += "Mods 源当前不存在, 部署后将创建同名空文件夹: $BackupSrc"
    }
    if ([string]::IsNullOrWhiteSpace($BackupDst)) {
        $preErrors += '指定了 $BackupSrc 就必须填写 $BackupDst (备份存放目录)'
    } else {
        # 备份目录绝不能在待删除目录之内 (否则备份会随旧程序一起被删)
        if ($BackupDst.TrimEnd('\') -ieq $DeleteDir.TrimEnd('\') -or
            $BackupDst.StartsWith($DeleteDir.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $preErrors += "`$BackupDst 不能位于 `$DeleteDir 之内(备份会被一起删除): $BackupDst"
        }
    }
} else {
    Write-Log '  [信息] $BackupSrc 为空, 本次不备份/不还原 Mods'
}

# 5. 删除地址父目录 (部署时要能创建)
$parent = Split-Path $DeleteDir -Parent
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    $preWarns += "删除地址的父目录不存在, 将自动创建: $parent"
}

# 6. 残留配置基本合法性
if ($ServiceNames.Count -gt 0) { Write-Log ("  [信息] 将清理服务: {0}" -f ($ServiceNames -join ', ')) }
if ($RegKey) { Write-Log "  [信息] 将清理注册表值: $RegKey -> $RegValueName" }
if ($ShortcutName) { Write-Log "  [信息] 将清理桌面快捷方式: $ShortcutName.lnk" }

# 7. 磁盘空间 (仅警告)
if (Test-Path -LiteralPath $ArchivePath -PathType Leaf) {
    $arcLen = (Get-Item -LiteralPath $ArchivePath).Length
    $tempFree = Get-FreeGB $env:TEMP
    $tgtFree  = Get-FreeGB $DeleteDir
    $needGB   = [math]::Round($arcLen * 1.5 / 1GB, 2)
    if ($tempFree -ge 0 -and $tempFree -lt $needGB) { $preWarns += "临时盘($env:TEMP) 剩余 $tempFree GB, 建议预留 $needGB GB 以上" }
    if ($tgtFree  -ge 0 -and $tgtFree  -lt $needGB) { $preWarns += "目标盘剩余 ${tgtFree}GB, 建议预留 ${needGB}GB 以上" }
}

Write-Log '  ............................................................'
foreach ($w in $preWarns)  { Write-Log "  [警告] $w" }
foreach ($e in $preErrors) { Write-Log "  [致命] $e" }

if ($preErrors.Count -gt 0) {
    Stop-With ("预检发现 {0} 个致命问题, 未做任何修改。请修正配置后重试。" -f $preErrors.Count)
}
Write-Log '[预检] 全部通过 (无致命问题)'
Write-Log '------------------------------------------------------------'

# ---------- 执行确认 ----------
$desktop  = [Environment]::GetFolderPath('Desktop')
$Shortcut = Join-Path $desktop "$($ShortcutName).lnk"
Write-Log '将执行以下操作:'
Write-Log "  1. 备份 Mods : $BackupSrc -> $BackupDst"
Write-Log "  2. 暂存解压新版(验证通过前不碰旧程序): $ArchivePath"
Write-Log "  3. 删除残留  : 服务[$($ServiceNames -join ', ')] / 快捷方式 / 注册表值 / 旧目录 $DeleteDir"
Write-Log "  4. 部署新版到: $DeleteDir"
Write-Log "  5. 还原 Mods 到原位置 (源不存在则创建空文件夹)"
if (-not $KeepBackup) { Write-Log '  6. 还原验证通过后删除备份压缩包' }

if (-not ($Yes -or $AutoConfirm)) {
    Write-Host ''
    $ans = Read-Host '确认执行? 输入 Y 继续, 其它键取消 (未改动任何文件)'
    if ($ans -ne 'Y' -and $ans -ne 'y') {
        Write-Log '[取消] 用户放弃执行, 未做任何修改'
        exit 0
    }
}
Write-Log '[确认] 开始执行'
Write-Log '------------------------------------------------------------'

# ---------- 步骤1: 备份 Mods + 完整性校验 ----------
$backupFile = ''
if ($BackupSrc -and (Test-Path -LiteralPath $BackupSrc -PathType Container)) {
    Write-Log '[步骤1] 备份 Mods'
    if (-not (Test-Path -LiteralPath $BackupDst)) {
        New-Item -ItemType Directory -Path $BackupDst -Force | Out-Null
        Write-Log "  [信息] 已创建备份存放目录: $BackupDst"
    }
    $backupName = Split-Path $BackupSrc -Leaf
    $backupFile = Join-Path $BackupDst "${backupName}_backup_$Ts.7z"
    Write-Log "  备份源   = $BackupSrc"
    Write-Log "  备份文件 = $backupFile"
    & $sz a -t7z -mx5 $backupFile $BackupSrc -y 2>&1 | ForEach-Object { Write-Log "  7z> $_" }
    if (-not (Test-7zOk) -or -not (Test-Path -LiteralPath $backupFile) -or (Get-Item -LiteralPath $backupFile).Length -eq 0) {
        Stop-With 'Mods 备份失败, 已终止 (旧程序未做任何改动)'
    }
    Write-Log '  [校验] 测试备份压缩包完整性 (7z t) ...'
    & $sz t $backupFile -y 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Log "  7z> $_" }
    if (-not (Test-7zOk)) {
        Stop-With '备份压缩包完整性校验失败, 已终止 (旧程序未做任何改动)'
    }
    Write-Log "[OK] 备份完成且校验通过 ($([math]::Round((Get-Item -LiteralPath $backupFile).Length/1MB,1)) MB)"
} else {
    Write-Log '[步骤1] 跳过备份 (源为空或不存在)'
}
Write-Log '------------------------------------------------------------'

# ---------- 步骤2: 暂存解压新版到临时目录 (旧程序此时完好无损) ----------
Write-Log '[步骤2] 暂存解压新版到临时目录 (验证通过前不删除旧程序)'
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
& $sz x $ArchivePath "-o$Stage" -y 2>&1 | ForEach-Object { Write-Log "  7z> $_" }
if (-not (Test-7zOk)) {
    Stop-With "新版压缩包解压失败 (7z 退出码 $LASTEXITCODE), 旧程序未做任何改动"
}
# 单层顶层文件夹自动上移
$top = @(Get-ChildItem -LiteralPath $Stage -Force -ErrorAction SilentlyContinue)
if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
    Write-Log "  [信息] 压缩包含单一顶层文件夹 '$($top[0].Name)', 自动上移内容"
    Get-ChildItem -LiteralPath $top[0].FullName -Force | Move-Item -Destination $Stage -Force
    Remove-Item -LiteralPath $top[0].FullName -Recurse -Force -ErrorAction SilentlyContinue
}
$stageCount = @(Get-ChildItem -LiteralPath $Stage -Force -ErrorAction SilentlyContinue).Count
if ($stageCount -eq 0) {
    Stop-With '新版压缩包解压后为空, 已终止 (旧程序未做任何改动)'
}
Write-Log "[OK] 暂存解压验证通过 ($stageCount 个顶层项), 位于 $Stage"
Write-Log '------------------------------------------------------------'

# ---------- 步骤3: 删除残留 (至此才动旧程序) ----------
Write-Log '[步骤3] 删除残留'

# 3.1 服务
foreach ($svc in $ServiceNames) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue } catch {}
        & sc.exe delete $svc 2>&1 | Out-Null
        Write-Log "  [处理] 已删除服务 $svc"
    } else {
        Write-Log "  [跳过] 服务 $svc 不存在"
    }
}

# 3.2 快捷方式
if ($ShortcutName) {
    if (Test-Path -LiteralPath $Shortcut) {
        try {
            (Get-Item -LiteralPath $Shortcut -Force).Attributes = 'Normal'
            Remove-Item -LiteralPath $Shortcut -Force -ErrorAction Stop
            Write-Log "  [OK] 快捷方式已删除: $Shortcut"
        } catch { Write-Log "  [警告] 快捷方式删除失败: $($_.Exception.Message)" }
    } else { Write-Log "  [跳过] 快捷方式不存在: $Shortcut" }
}

# 3.3 注册表值 (只删值, 不删主键)
if ($RegKey) {
    if (Test-Path -LiteralPath $RegKey) {
        $cur = (Get-Item -LiteralPath $RegKey -ErrorAction SilentlyContinue).Property
        if ($cur -contains $RegValueName) {
            try {
                Remove-ItemProperty -LiteralPath $RegKey -Name $RegValueName -Force -ErrorAction Stop
                Write-Log "  [OK] 注册表值已删除: $RegKey = $RegValueName"
            } catch { Write-Log "  [警告] 注册表值删除失败: $($_.Exception.Message)" }
        } else { Write-Log "  [跳过] 注册表值不存在: $RegValueName" }
    } else { Write-Log "  [跳过] 注册表主键不存在: $RegKey" }
}

# 3.4 旧程序目录 (删除失败必须终止, 否则新版会与残留混合)
if (Test-Path -LiteralPath $DeleteDir) {
    try {
        Get-ChildItem -LiteralPath $DeleteDir -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item -LiteralPath $DeleteDir -Recurse -Force -ErrorAction Stop
        Write-Log "  [OK] 旧程序目录已删除: $DeleteDir"
    } catch {
        Stop-With "旧程序目录删除失败: $($_.Exception.Message) (新版暂存于 $Stage, Mods备份: $backupFile, 可手动恢复)"
    }
} else {
    Write-Log '  [跳过] 旧程序目录不存在 (全新安装)'
}
Write-Log '------------------------------------------------------------'

# ---------- 步骤4: 部署新版 (暂存 -> 目标位置) ----------
Write-Log '[步骤4] 部署新版到目标位置'
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
try {
    Move-Item -LiteralPath $Stage -Destination $DeleteDir -Force -ErrorAction Stop
    Write-Log "[OK] 新版已部署: $DeleteDir"
} catch {
    Stop-With "新版部署失败: $($_.Exception.Message) (暂存: $Stage, 备份: $backupFile)"
}
$newCount = @(Get-ChildItem -LiteralPath $DeleteDir -Force -ErrorAction SilentlyContinue).Count
Write-Log "[校验] 新程序目录共 $newCount 个顶层项"
Write-Log '------------------------------------------------------------'

# ---------- 步骤5: 还原 Mods (或创建空文件夹) ----------
Write-Log '[步骤5] 还原 Mods 到原位置'
if (-not $BackupSrc) {
    Write-Log '  [跳过] 未配置 Mods 源'
} else {
    $modsParent = Split-Path $BackupSrc -Parent
    if ($backupFile -and (Test-Path -LiteralPath $backupFile)) {
        if ($modsParent -and -not (Test-Path -LiteralPath $modsParent)) {
            New-Item -ItemType Directory -Path $modsParent -Force | Out-Null
        }
        & $sz x $backupFile "-o$modsParent" -y 2>&1 | ForEach-Object { Write-Log "  7z> $_" }
        if (-not (Test-7zOk)) {
            Write-Log "  [警告] Mods 还原失败 (7z $LASTEXITCODE), 备份保留: $backupFile"
        } else {
            $restored = @(Get-ChildItem -LiteralPath $BackupSrc -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            Write-Log "  [OK] Mods 已还原 ($restored 个文件)"
            if ($restored -ne $srcFiles) {
                Write-Log "  [警告] 还原文件数($restored)与备份前($srcFiles)不一致, 请检查"
            }
            if (-not $KeepBackup) {
                try {
                    Remove-Item -LiteralPath $backupFile -Force -ErrorAction Stop
                    Write-Log "  [清理] 已删除备份压缩包: $backupFile"
                } catch { Write-Log "  [警告] 备份压缩包删除失败: $($_.Exception.Message)" }
            } else {
                Write-Log "  [信息] 按配置保留备份压缩包: $backupFile"
            }
        }
    } else {
        if (-not (Test-Path -LiteralPath $BackupSrc)) {
            New-Item -ItemType Directory -Path $BackupSrc -Force | Out-Null
            Write-Log "  [信息] 已在原位置创建同名空文件夹: $BackupSrc"
        }
    }
    if (Test-Path -LiteralPath $BackupSrc) {
        $mcnt = @(Get-ChildItem -LiteralPath $BackupSrc -Force -ErrorAction SilentlyContinue).Count
        Write-Log "  [校验] Mods 目录就绪 (共 $mcnt 项): $BackupSrc"
    }
}
Write-Log '------------------------------------------------------------'

# ---------- 结束 ----------
Write-Log '============================================================'
Write-Log "全部流程结束  时间戳 $Ts"
Write-Log "详细日志: $LogFile"
Write-Log '============================================================'
Write-Host ''
Write-Host '处理完成! 日志:' -ForegroundColor Green
Write-Host "  $LogFile" -ForegroundColor Cyan
Read-Host '按回车键关闭'
