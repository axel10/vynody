<#
.SYNOPSIS
    清理 Git 仓库中遗留的大体积音频文件（~93MB test/test_music_dir）

.DESCRIPTION
    经排查，仓库中的音频大文件全部来自分支 origin/colors 中的 commit 7be39ca ("添加测试数据")。
    main 分支及当前工作区并未包含这些文件。
    该脚本提供两种清理策略：
      1. 方案一 (推荐): 删除废弃的远程分支 origin/colors，然后对本地执行 git gc 回收空间（不影响任何 commit hash）。
      2. 方案二: 使用 git filter-repo 彻底重写所有分支历史，剔除 test/test_music_dir/ 目录。

.PARAMETER Mode
    可选值:
      "1" 或 "DeleteBranch"  - 仅删除 origin/colors 分支并回收本地空间
      "2" 或 "FilterRepo"    - 使用 git-filter-repo 彻底改写全部分支历史
      "Check"                - 仅检查大文件占用情况与 .git 目录大小
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("1", "2", "DeleteBranch", "FilterRepo", "Check")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

function Show-RepoStats {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Git 仓库音频大文件分析" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $gitDirSize = (Get-ChildItem -Recurse .git -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host ("当前 .git 目录总大小: {0:N2} MB" -f $gitDirSize) -ForegroundColor Yellow
    
    Write-Host "`n检测到历史记录中的音频文件 (共约 92.94 MB):" -ForegroundColor Gray
    git rev-list --objects --all | git cat-file --batch-check="%(objectname) %(objecttype) %(objectsize) %(rest)" | 
        Where-Object { $_ -match "\.(mp3|flac|wav|m4a|aac|ogg|opus|wma|aiff|ape|dsf|dsd|alac)$" } | 
        ForEach-Object {
            $parts = $_ -split ' ', 4
            [PSCustomObject]@{
                "Size (MB)" = [math]::Round([int64]$parts[2] / 1MB, 2)
                "FilePath"  = $parts[3]
            }
        } | Sort-Object "Size (MB)" -Descending | Format-Table -AutoSize

    Write-Host "音频文件所在 Commit: 7be39ca2f6 ('添加测试数据')" -ForegroundColor Gray
    Write-Host "引用该 Commit 的唯一分支: remotes/origin/colors" -ForegroundColor Gray
    Write-Host "----------------------------------------`n"
}

# 确保在 Git 根目录
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "当前目录不是有效的 Git 仓库！"
    exit 1
}
Set-Location $repoRoot

Show-RepoStats

if ($Mode -eq "Check") {
    exit 0
}

# 如果未传参，提供交互式选择
if (-not $Mode) {
    Write-Host "请选择清理方式：" -ForegroundColor Green
    Write-Host "  [1] 方案一 (推荐/最安全)：删除远程 colors 分支并执行本地垃圾回收 (git gc)"
    Write-Host "      说明：main 分支不受任何影响，commit hash 保持不变，本地立刻释放 ~93MB。"
    Write-Host "  [2] 方案二 (彻底重写)：使用 git filter-repo 彻底从全部分支历史抹除 test/test_music_dir/"
    Write-Host "      说明：会改写该分支涉及的 commit hash，需 force push。"
    Write-Host "  [Q] 退出不操作"
    Write-Host ""
    $choice = Read-Host "请输入选项 (1/2/Q)"
    switch ($choice.Trim().ToUpper()) {
        "1" { $Mode = "DeleteBranch" }
        "2" { $Mode = "FilterRepo" }
        default {
            Write-Host "已取消操作。" -ForegroundColor Gray
            exit 0
        }
    }
}

if ($Mode -eq "1" -or $Mode -eq "DeleteBranch") {
    Write-Host "`n>>> 正在执行方案一：删除 origin/colors 并清理本地缓存..." -ForegroundColor Cyan
    
    # 1. 检查是否存在远程 colors 分支
    $hasRemote = git ls-remote --heads origin colors 2>$null
    if ($hasRemote) {
        Write-Host "正在从远端删除 colors 分支 (git push origin --delete colors)..." -ForegroundColor Yellow
        git push origin --delete colors
    } else {
        Write-Host "远端已无 colors 分支，跳过远程删除。" -ForegroundColor Gray
    }

    # 2. 清理本地 remote tracking ref
    Write-Host "剪裁本地已废弃的远端分支引用..." -ForegroundColor Yellow
    git remote prune origin

    # 3. 强制清空 reflog 并执行 aggressive gc
    Write-Host "执行 Git 垃圾回收 (git gc --prune=now --aggressive)..." -ForegroundColor Yellow
    git reflog expire --expire=now --all
    git gc --prune=now --aggressive

    Write-Host "`n清理完成！" -ForegroundColor Green
    $newSize = (Get-ChildItem -Recurse .git -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host ("清理后 .git 目录大小: {0:N2} MB" -f $newSize) -ForegroundColor Green
    exit 0
}

if ($Mode -eq "2" -or $Mode -eq "FilterRepo") {
    Write-Host "`n>>> 正在执行方案二：使用 git-filter-repo 重写历史..." -ForegroundColor Cyan
    
    # 检查是否有未提交的代码
    $status = git status --porcelain
    if ($status) {
        Write-Error "工作区有未提交的改动，请先提交或 stash 后再执行 git-filter-repo！"
        exit 1
    }

    Write-Host "从全部历史中剔除 test/test_music_dir/ ..." -ForegroundColor Yellow
    git filter-repo --path test/test_music_dir --invert-paths --force

    Write-Host "执行 Git 垃圾回收..." -ForegroundColor Yellow
    git reflog expire --expire=now --all
    git gc --prune=now --aggressive

    Write-Host "`n清理完成！" -ForegroundColor Green
    $newSize = (Get-ChildItem -Recurse .git -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host ("清理后 .git 目录大小: {0:N2} MB" -f $newSize) -ForegroundColor Green
    Write-Host "注意：git filter-repo 已重写涉及的 commit，远端仓库需添加回 remote 并通过 --force 推送。" -ForegroundColor Yellow
    exit 0
}
