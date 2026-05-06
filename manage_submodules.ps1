# 检查并添加 Git 子模块的脚本
$ErrorActionPreference = 'Stop'

$submodules = @{
    "audio_core"         = "https://github.com/axel10/audio_core.git"
    "audio_converter"    = "https://github.com/axel10/audio_converter.git"
    "audio_ffmpeg_lib"   = "https://github.com/axel10/audio_ffmpeg_lib.git"
    "crates/ffmpeg_core" = "https://github.com/axel10/ffmpeg_core.git"
    "crates/rust-ffmpeg" = "https://github.com/axel10/rust-ffmpeg.git"
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$Args
    )

    & git @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') 失败，退出码: $LASTEXITCODE"
    }
}

function Remove-ExistingSubmoduleState {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $gitmodulesPath = Join-Path -Path (Get-Location) -ChildPath '.gitmodules'

    if (Test-Path -LiteralPath $gitmodulesPath) {
        & git config -f .gitmodules --remove-section "submodule.$Path" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "已从 .gitmodules 移除旧映射: $Path" 'Gray'
        }
    }

    & git rm -r --cached --ignore-unmatch $Path 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "已从索引移除旧条目: $Path" 'Gray'
    }

    $moduleDir = Join-Path -Path (Get-Location) -ChildPath ".git/modules/$Path"
    if (Test-Path -LiteralPath $moduleDir) {
        Remove-Item -LiteralPath $moduleDir -Recurse -Force
        Write-Log "已清理残留模块目录: $moduleDir" 'Gray'
    }
}

function Get-ExistingGitlinks {
    $lines = & git ls-files -s
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files -s 失败，退出码: $LASTEXITCODE"
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^\d+\s+[0-9a-f]+\s+\d+\s+(.+)$') {
            $paths.Add($Matches[1])
        }
    }

    return $paths
}

Write-Log "正在检查 vibe_flow 的子模块状态..." 'Cyan'

foreach ($path in $submodules.Keys) {
    $url = $submodules[$path]
    Write-Log "`n处理项目: $path" 'White'

    $status = & git submodule status $path 2>$null

    if ($status -and $status.Trim().Length -gt 0) {
        Write-Log "[OK] $path 已经是子模块。" 'Green'
        continue
    }

    Write-Log "[!] $path 不是子模块，准备添加..." 'Yellow'

    $backupPath = $null
    $backupCreated = $false
    $originalExists = Test-Path -LiteralPath $path

    try {
        Remove-ExistingSubmoduleState -Path $path

        if ($originalExists) {
            Write-Log "检测到目录 $path 已存在，正在创建备份..." 'Gray'

            $backupPath = "$($path.Replace('/', '_'))_backup_$(Get-Date -Format 'yyyyMMddHHmmss')"
            if (Test-Path -LiteralPath $backupPath) {
                throw "备份路径已存在: $backupPath"
            }

            Copy-Item -LiteralPath $path -Destination $backupPath -Recurse -Force
            $backupCreated = $true
            Write-Log "备份已完成: $backupPath" 'Gray'

            Write-Log "清理原目录以便添加子模块..." 'Gray'
            Remove-Item -LiteralPath $path -Recurse -Force
        }

        try {
            Invoke-Git -Args @('submodule', 'add', $url, $path)
            Write-Log "[SUCCESS] 已成功添加 $path 为子模块。" 'Green'

            if ($backupCreated) {
                Write-Log "原始内容已备份到 $backupPath，建议人工确认后再决定是否删除。" 'Gray'
            }
        }
        catch {
            Write-Log "[ERROR] 添加 $path 失败: $($_.Exception.Message)" 'Red'

            if ($backupCreated) {
                Write-Log "正在尝试从备份恢复原目录..." 'Yellow'
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force
                }
                Copy-Item -LiteralPath $backupPath -Destination $path -Recurse -Force
                Write-Log "已从备份恢复: $path" 'Green'
            }

            throw
        }
    }
    catch {
        Write-Log "[ERROR] 处理 $path 时发生异常: $($_.Exception.Message)" 'Red'

        if ($backupCreated -and (Test-Path -LiteralPath $backupPath)) {
            Write-Log "保留备份目录以便手动恢复: $backupPath" 'Yellow'
        }
        continue
    }
}

Write-Log "`n所有检查完成。" 'Magenta'

$gitlinks = Get-ExistingGitlinks
$pathsToUpdate = @()
foreach ($path in $submodules.Keys) {
    if ($gitlinks -contains $path) {
        $pathsToUpdate += $path
    }
}

if ($pathsToUpdate.Count -gt 0) {
    $updateArgs = @('submodule', 'update', '--init', '--') + $pathsToUpdate
    Invoke-Git -Args $updateArgs
} else {
    Write-Log "没有需要初始化的目标子模块。" 'Gray'
}
