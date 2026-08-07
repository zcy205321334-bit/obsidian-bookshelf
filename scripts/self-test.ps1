[CmdletBinding()]
param(
    [string]$SkillPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SkillPath)){$SkillPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'SKILL.md'}
$script:Pass=0
$script:Fail=0
$script:Red=New-Object 'System.Collections.Generic.List[string]'
$script:Green=New-Object 'System.Collections.Generic.List[string]'

function Assert-Test([bool]$Condition,[string]$Name){if($Condition){$script:Pass++;Write-Output "PASS $Name"}else{$script:Fail++;Write-Output "FAIL $Name"}}
function Write-Utf8([string]$Path,[string]$Text,[bool]$Bom=$false){$parent=[IO.Path]::GetDirectoryName($Path);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($Bom)))}
function Get-TextHash([string]$Text){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Get-FileSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-Relative([string]$Root,[string]$Child){$prefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$Child.Substring($prefix.Length).Replace('\','/')}
function Get-TreeHash([string]$Root){
    $lines=New-Object 'System.Collections.Generic.List[string]';$pending=New-Object 'System.Collections.Generic.Stack[string]';$pending.Push($Root)
    while($pending.Count-gt 0){$current=$pending.Pop();foreach($entry in @(Get-ChildItem -LiteralPath $current -Force|Sort-Object FullName)){$rel=Get-Relative $Root $entry.FullName;$attrs=[int]$entry.Attributes
        if($entry.PSIsContainer){$lines.Add("D|$rel|$attrs");if(($entry.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq 0){$pending.Push($entry.FullName)}}else{$lines.Add("F|$rel|$attrs|$($entry.Length)|$(Get-FileSha $entry.FullName)")}
    }};Get-TextHash ([string]::Join("`n",@($lines|Sort-Object)))
}
function Quote-Argument([string]$Value){'"'+$Value.Replace('\','\').Replace('"','\"')+'"'}
function Invoke-Child([string]$Script,[string[]]$Arguments){
    $parts=New-Object 'System.Collections.Generic.List[string]';$parts.Add('-NoProfile');$parts.Add('-ExecutionPolicy');$parts.Add('Bypass');$parts.Add('-File');$parts.Add((Quote-Argument $Script));foreach($arg in $Arguments){$parts.Add((Quote-Argument $arg))}
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.Arguments=[string]::Join(' ',$parts);$psi.WorkingDirectory=$PSScriptRoot;$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$psi;if(-not$process.Start()){throw "无法启动测试进程: $Script"};$stdout=$process.StandardOutput.ReadToEnd();$stderr=$process.StandardError.ReadToEnd();$process.WaitForExit();$code=$process.ExitCode;$process.Dispose()
    [pscustomobject]@{code=$code;stdout=$stdout;stderr=$stderr}
}
function Get-JsonResult($Result){if([string]::IsNullOrWhiteSpace($Result.stdout)){throw "子进程没有 JSON 输出。stderr=$($Result.stderr)"};$Result.stdout.Trim()|ConvertFrom-Json}
function Add-ExpectedFailure($Result,[string]$Name){$ok=$Result.code-ne 0;Assert-Test $ok "$Name（红）";if($ok){$script:Red.Add($Name)};return $ok}
function Add-RecoveredSuccess($Result,[string]$Name){$ok=$Result.code-eq 0;Assert-Test $ok "$Name（绿）";if($ok){$script:Green.Add($Name)};return $ok}
function Read-StrictUtf8([string]$Path){
    $fullPath=[IO.Path]::GetFullPath($Path);if(-not[IO.File]::Exists($fullPath)){throw "SKILL.md 不存在: $fullPath"}
    $utf8=New-Object Text.UTF8Encoding($false,$true);$utf8.GetString([IO.File]::ReadAllBytes($fullPath))
}

$scanScript=Join-Path $PSScriptRoot 'scan.ps1';$genScript=Join-Path $PSScriptRoot 'gen-cards.ps1';$linksScript=Join-Path $PSScriptRoot 'fix-links.ps1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ("obsidian-bookshelf-selftest-{0}"-f[Guid]::NewGuid().ToString('N'))
$source=Join-Path $testRoot '虚构源目录';$vault=Join-Path $testRoot '虚构 Vault';$junctionTarget=Join-Path $testRoot '联接目标';$junctionPath=Join-Path $source '重解析条目'
[IO.Directory]::CreateDirectory($source)|Out-Null;[IO.Directory]::CreateDirectory($vault)|Out-Null;[IO.Directory]::CreateDirectory($junctionTarget)|Out-Null

try{
    $skillText=Read-StrictUtf8 $SkillPath
    $entityCount=([regex]::Matches($skillText,'&#(?:x[0-9A-Fa-f]+|[0-9]+);')).Count
    $chineseCount=([regex]::Matches($skillText,'[\u3400-\u4DBF\u4E00-\u9FFF]')).Count
    Write-Output "SKILL_ENCODING ENTITIES=$entityCount CHINESE=$chineseCount"
    Assert-Test ($entityCount-eq 0) 'SKILL.md HTML 数字实体门禁'
    Assert-Test ($chineseCount-gt 0) 'SKILL.md 真实中文字符门禁'

    foreach($name in @('星际 冒险','传说[重置版]','空目录','镜像甲','镜像乙','隐藏条目','系统条目')){[IO.Directory]::CreateDirectory((Join-Path $source $name))|Out-Null}
    Write-Utf8 (Join-Path $source 'README.md') '# 虚构夹具说明';Write-Utf8 (Join-Path $source '星际 冒险\资料.txt') 'alpha';[IO.File]::WriteAllBytes((Join-Path $source '星际 冒险\封面.png'),[byte[]](1,2,3,4,5))
    Write-Utf8 (Join-Path $source '传说[重置版]\说明.md') 'beta';Write-Utf8 (Join-Path $source '镜像甲\说明.md') 'same-a';Write-Utf8 (Join-Path $source '镜像乙\说明.md') 'same-b'
    Write-Utf8 (Join-Path $source '星际 冒险\隐藏文件.txt') 'hidden';(Get-Item -LiteralPath (Join-Path $source '星际 冒险\隐藏文件.txt') -Force).Attributes=[IO.FileAttributes]::Hidden
    (Get-Item -LiteralPath (Join-Path $source '隐藏条目') -Force).Attributes=[IO.FileAttributes]::Directory-bor[IO.FileAttributes]::Hidden
    (Get-Item -LiteralPath (Join-Path $source '系统条目') -Force).Attributes=[IO.FileAttributes]::Directory-bor[IO.FileAttributes]::System
    Write-Utf8 (Join-Path $junctionTarget '外部.txt') 'junction-target';New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget|Out-Null
    $sourceHashBefore=Get-TreeHash $source

    $fullScanPath=Join-Path $testRoot 'scan-full.json';$fullScanRun=Invoke-Child $scanScript @('-SourceRoot',$source,'-VaultRoot',$vault,'-Route','game','-BatchSize','50','-OutputPath',$fullScanPath)
    Assert-Test ($fullScanRun.code-eq 0) '扫描虚构源目录成功';$fullScan=[IO.File]::ReadAllText($fullScanPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
    Assert-Test ([int]$fullScan.total_count-eq 5) '排除 Hidden/System/ReparsePoint 且 README 不作为条目'
    Assert-Test (@($fullScan.items|Where-Object{$_.relative_path-eq'空目录'}).Count-eq 1) '空目录具有稳定条目快照'
    Assert-Test (@($fullScan.items|Where-Object{$_.relative_path-eq'星际 冒险'}).Count-eq 1-and@($fullScan.items|Where-Object{$_.relative_path-eq'传说[重置版]'}).Count-eq 1) '中文、空格与方括号条目可扫描'

    $batchScanPath=Join-Path $testRoot 'scan-batch.json';$batchRun=Invoke-Child $scanScript @('-SourceRoot',$source,'-VaultRoot',$vault,'-Route','game','-BatchSize','2','-OutputPath',$batchScanPath);Assert-Test ($batchRun.code-eq 0) '默认模型支持分批扫描'
    $vaultHashBefore=Get-TreeHash $vault;$stageBasic=Join-Path $testRoot 'stage-basic';$previewRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$batchScanPath,'-VaultRoot',$vault,'-VaultSubdir','收藏','-StagingPath',$stageBasic)
    Assert-Test ($previewRun.code-eq 0) '基础卡片 Preview 成功';$preview=Get-JsonResult $previewRun
    Assert-Test ((Get-TreeHash $vault)-eq$vaultHashBefore-and[bool]$preview.vault_writes-eq$false) 'Preview零写入'
    Assert-Test (-not[IO.File]::Exists((Join-Path $vault 'HOME.md'))) 'HOME.md 不存在时不创建'

    $badHashRun=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$stageBasic,'-PlanHash',('0'*64));[void](Add-ExpectedFailure $badHashRun '错误 plan_hash')
    $applyBasic=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$stageBasic,'-PlanHash',[string]$preview.plan_hash);[void](Add-RecoveredSuccess $applyBasic '正确 plan_hash')
    $bookmarkPath=Join-Path $vault '.obsidian-bookshelf\last-run.json';$bookmark=[IO.File]::ReadAllText($bookmarkPath,[Text.Encoding]::UTF8)|ConvertFrom-Json;Assert-Test ([int]$bookmark.processed_count-eq 2) '仅成功 Apply 更新续跑书签'

    $resumePath=Join-Path $testRoot 'scan-resume.json';$resumeRun=Invoke-Child $scanScript @('-SourceRoot',$source,'-VaultRoot',$vault,'-Route','game','-BatchSize','2','-OutputPath',$resumePath);$resume=[IO.File]::ReadAllText($resumePath,[Text.Encoding]::UTF8)|ConvertFrom-Json
    Assert-Test ($resumeRun.code-eq 0-and[bool]$resume.bookmark_used-and[int]$resume.processed_count_before-eq 2-and@($resume.items).Count-eq 2) '续跑书签按相对路径继续下一批'

    $namedStage=Join-Path $testRoot 'stage-named';$namedRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$fullScanPath,'-VaultRoot',$vault,'-VaultSubdir','点名集群','-StagingPath',$namedStage,'-AdvancedItem','星际 冒险','-Character','星际 冒险::林澈');$named=Get-JsonResult $namedRun
    Assert-Test ($namedRun.code-eq 0-and[string]$named.cluster_trigger-eq'named-items'-and@(Get-ChildItem -LiteralPath (Join-Path $namedStage 'files') -Filter '介绍.md' -Recurse).Count-eq 1-and@(Get-ChildItem -LiteralPath (Join-Path $namedStage 'files') -Filter '林澈.md' -Recurse).Count-eq 1) '集群触发一：用户精确点名条目'
    $smallStage=Join-Path $testRoot 'stage-small';$smallRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$fullScanPath,'-VaultRoot',$vault,'-VaultSubdir','小库集群','-StagingPath',$smallStage,'-InventoryConfirmed','-ApprovedSmallLibraryStandard');$small=Get-JsonResult $smallRun
    Assert-Test ($smallRun.code-eq 0-and[string]$small.cluster_trigger-eq'small-library-approved'-and@(Get-ChildItem -LiteralPath (Join-Path $smallStage 'files') -Filter '介绍.md' -Recurse).Count-eq 5) '集群触发二：盘点后明确批准且总数不超过20'
    $photoScanPath=Join-Path $testRoot 'scan-photo.json';[void](Invoke-Child $scanScript @('-SourceRoot',$source,'-VaultRoot',$vault,'-Route','photo','-OutputPath',$photoScanPath));$photoAdvanced=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$photoScanPath,'-VaultRoot',$vault,'-VaultSubdir','照片','-StagingPath',(Join-Path $testRoot 'stage-photo'),'-AdvancedItem','星际 冒险');Assert-Test ($photoAdvanced.code-ne 0) '照片路由拒绝进阶集群'

    $stageChanged=Join-Path $testRoot 'stage-source-change';$changePreviewRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$fullScanPath,'-VaultRoot',$vault,'-VaultSubdir','收藏','-StagingPath',$stageChanged);$changePreview=Get-JsonResult $changePreviewRun
    $changedFile=Join-Path $source '星际 冒险\资料.txt';$originalBytes=[IO.File]::ReadAllBytes($changedFile);Write-Utf8 $changedFile 'changed-after-preview'
    $changedApply=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$stageChanged,'-PlanHash',[string]$changePreview.plan_hash);[void](Add-ExpectedFailure $changedApply 'Preview 后源变化')
    [IO.File]::WriteAllBytes($changedFile,$originalBytes);$restoredApply=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$stageChanged,'-PlanHash',[string]$changePreview.plan_hash);[void](Add-RecoveredSuccess $restoredApply '还原源快照后 Apply')

    $cardPath=Join-Path $vault '收藏\游戏库\条目\星际 冒险.md';$cardText=[IO.File]::ReadAllText($cardPath,[Text.Encoding]::UTF8).Replace("`r`n","`n");if(-not$cardText.StartsWith("---`n")){throw '卡片 frontmatter 起始无效'};$cardText="---`nmanual_owner: 测试员`n"+$cardText.Substring(4)+"`n`n人工正文保留标记`n";Write-Utf8 $cardPath $cardText.Replace("`n","`r`n") $true
    $manualStage=Join-Path $testRoot 'stage-manual';$manualPreviewRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$fullScanPath,'-VaultRoot',$vault,'-VaultSubdir','收藏','-StagingPath',$manualStage);$manualPreview=Get-JsonResult $manualPreviewRun;$manualApply=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$manualStage,'-PlanHash',[string]$manualPreview.plan_hash)
    $manualBytes=[IO.File]::ReadAllBytes($cardPath);$manualAfter=[IO.File]::ReadAllText($cardPath,[Text.Encoding]::UTF8)
    Assert-Test ($manualApply.code-eq 0-and$manualBytes[0]-eq 0xEF-and$manualBytes[1]-eq 0xBB-and$manualBytes[2]-eq 0xBF-and$manualAfter.Contains("`r`n")-and$manualAfter.Contains('manual_owner: 测试员')-and$manualAfter.Contains('人工正文保留标记')) '人工内容、BOM 与换行保留'

    $unapprovedStage=Join-Path $testRoot 'stage-unapproved';$unapprovedPreviewRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$fullScanPath,'-VaultRoot',$vault,'-VaultSubdir','收藏','-StagingPath',$unapprovedStage);$unapprovedPreview=Get-JsonResult $unapprovedPreviewRun
    $unapprovedApply=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$unapprovedStage,'-PlanHash',[string]$unapprovedPreview.plan_hash,'-Image','星际 冒险/封面.png');[void](Add-ExpectedFailure $unapprovedApply '未批准图片')
    $approvedStage=Join-Path $testRoot 'stage-approved';$approvedPreviewRun=Invoke-Child $genScript @('-Mode','Preview','-ScanPath',$fullScanPath,'-VaultRoot',$vault,'-VaultSubdir','收藏','-StagingPath',$approvedStage,'-ApprovedImage','星际 冒险/封面.png');$approvedPreview=Get-JsonResult $approvedPreviewRun
    $approvedApply=Invoke-Child $genScript @('-Mode','Apply','-StagingPath',$approvedStage,'-PlanHash',[string]$approvedPreview.plan_hash,'-Image','星际 冒险/封面.png');[void](Add-RecoveredSuccess $approvedApply '图片获批后事务复制');$copiedImage=Join-Path $vault '收藏\游戏库\Assets\封面.png';Assert-Test ([IO.File]::Exists($copiedImage)-and(Get-FileSha $copiedImage)-eq(Get-FileSha (Join-Path $source '星际 冒险\封面.png'))) '只复制获批图片且哈希一致'

    $linkScope=Join-Path $vault '链接测试';[IO.Directory]::CreateDirectory((Join-Path $linkScope '甲'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $linkScope '乙'))|Out-Null
    Write-Utf8 (Join-Path $linkScope '主[重置版].md') "| 导航 |`n|---|`n| [[目标|别名]] |`n`n[[不存在]]`n";Write-Utf8 (Join-Path $linkScope '目标.md') '# 目标';Write-Utf8 (Join-Path $linkScope '甲\说明.md') '# 甲';Write-Utf8 (Join-Path $linkScope '乙\说明.md') '# 乙';Write-Utf8 (Join-Path $linkScope '甲\说明：一.md') '# 甲一';Write-Utf8 (Join-Path $linkScope '甲\说明？一.md') '# 甲二'
    $brokenAudit=Invoke-Child $linksScript @('-Mode','Audit','-RootPath',$vault,'-ScopeRelativePath','链接测试');[void](Add-ExpectedFailure $brokenAudit '断链审计')
    Write-Utf8 (Join-Path $linkScope '主[重置版].md') "| 导航 |`n|---|`n| [[目标|别名]] |`n";$greenAudit=Invoke-Child $linksScript @('-Mode','Audit','-RootPath',$vault,'-ScopeRelativePath','链接测试');[void](Add-RecoveredSuccess $greenAudit '修正断链后审计')
    $linkStage=Join-Path $testRoot 'stage-links';$linkPreviewRun=Invoke-Child $linksScript @('-Mode','Preview','-RootPath',$vault,'-ScopeRelativePath','链接测试','-StagingPath',$linkStage);$linkPreview=Get-JsonResult $linkPreviewRun;$linkApply=Invoke-Child $linksScript @('-Mode','Apply','-StagingPath',$linkStage,'-PlanHash',[string]$linkPreview.plan_hash)
    $safeMain=Join-Path $linkScope '主_重置版_.md';$duplicateFiles=@(Get-ChildItem -LiteralPath $linkScope -Filter '说明-*.md' -File -Recurse);$sameDirDuplicateFiles=@(Get-ChildItem -LiteralPath (Join-Path $linkScope '甲') -Filter '说明*一*.md' -File);$postAudit=Invoke-Child $linksScript @('-Mode','Audit','-RootPath',$vault,'-ScopeRelativePath','链接测试')
    Assert-Test ($linkApply.code-eq 0-and[IO.File]::Exists($safeMain)-and([IO.File]::ReadAllText($safeMain,[Text.Encoding]::UTF8).Contains('\|'))-and$duplicateFiles.Count-eq 0-and$postAudit.code-eq 0) '链接 Preview→Apply、表格转义、危险字符与稳定重名哈希'
    Assert-Test ($sameDirDuplicateFiles.Count-eq 2) '同目录清洗重名仍使用稳定哈希消歧'

    $sourceHashAfter=Get-TreeHash $source;Assert-Test ($sourceHashAfter-eq$sourceHashBefore) '源目录前后哈希不变'
    Assert-Test ($script:Red.Count-eq 4-and$script:Green.Count-eq 4) '红→绿反向验证覆盖错误哈希、源变化、未批准图片、断链'
}catch{
    $script:Fail++;Write-Output "FAIL 未预期异常: $($_.Exception.Message)";Write-Output $_.ScriptStackTrace
}finally{
    if([IO.Directory]::Exists($junctionPath)){[IO.Directory]::Delete($junctionPath)}
    if([IO.Directory]::Exists($testRoot)){[IO.Directory]::Delete($testRoot,$true)}
}

Write-Output "PASS=$script:Pass"
Write-Output "FAIL=$script:Fail"
if($script:Fail-ne 0){exit 1};exit 0
