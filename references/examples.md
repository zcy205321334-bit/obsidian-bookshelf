# 命令示例

以下均使用虚构目录，实际运行前替换为用户明确指定的路径。

## 盘点与续跑

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/scan.ps1 -SourceRoot 'D:\虚构资料\游戏' -VaultRoot 'D:\虚构Vault' -Route game
```

默认批次是 50。同一源根再次扫描时只读 `.obsidian-bookshelf/last-run.json` 并从已成功 Apply 的相对路径后继续。

## Preview 与 Apply

```powershell
$preview = powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/gen-cards.ps1 -Mode Preview -ScanPath $scanPath -VaultRoot 'D:\虚构Vault' -VaultSubdir '收藏' -AdvancedItem '星港纪事'
$result = $preview | ConvertFrom-Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/gen-cards.ps1 -Mode Apply -StagingPath $result.staging_path -PlanHash $result.plan_hash
```

小库第二种触发必须同时传入 `-InventoryConfirmed -ApprovedSmallLibraryStandard`。

角色页示例（角色名必须来自用户明确提供）：powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/gen-cards.ps1 -Mode Preview -ScanPath $scanPath -VaultRoot 'D:\虚构Vault' -VaultSubdir '收藏' -AdvancedItem '星港纪事' -Character '星港纪事::林澈'

## 链接审计与修复

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fix-links.ps1 -Mode Audit -RootPath 'D:\虚构Vault' -ScopeRelativePath '收藏'
$preview = powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fix-links.ps1 -Mode Preview -RootPath 'D:\虚构Vault' -ScopeRelativePath '收藏'
$result = $preview | ConvertFrom-Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fix-links.ps1 -Mode Apply -StagingPath $result.staging_path -PlanHash $result.plan_hash
```

表格链接输出为 `[[星港纪事\|详情]]`。Audit 遇到断链退出失败，必须补正目标或链接后重新审计。
