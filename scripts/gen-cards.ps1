[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Preview','Apply')][string]$Mode,
    [string]$ScanPath,
    [string]$VaultRoot,
    [string]$VaultSubdir='Bookshelf',
    [string]$StagingPath,
    [string]$PlanHash,
    [string[]]$AdvancedItem=@(),
    [string[]]$Character=@(),
    [switch]$InventoryConfirmed,
    [switch]$ApprovedSmallLibraryStandard,
    [string[]]$ApprovedImage=@(),
    [string[]]$Image=@()
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:ManagedKeys=@('title','route','kind','bookshelf_source_root_id','bookshelf_relpath','bookshelf_plan_hash','platform','type','status','author','tags','time','event','course','source')

function Get-TextHash([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-FileSha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Directory([string]$Path,[string]$Label) {
    if(-not [IO.Directory]::Exists($Path)){throw "$Label 不存在或不是目录: $Path"}
    [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
}
function Get-TempRoot { [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') }
function Assert-InTemp([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path); $prefix=(Get-TempRoot)+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "staging 必须位于系统临时目录: $full"}
    $full
}
function Get-Inside([string]$Root,[string]$Relative) {
    if([IO.Path]::IsPathRooted($Relative)){throw "相对路径不能是绝对路径: $Relative"}
    $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/',[IO.Path]::DirectorySeparatorChar)))
    $prefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if($full -ne $Root -and -not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "路径越界: $Relative"}
    $full
}
function Get-Relative([string]$Root,[string]$Child) {
    $prefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $Child.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "路径越界: $Child"}
    $Child.Substring($prefix.Length).Replace('\','/')
}
function Test-Excluded([IO.FileSystemInfo]$Entry) {
    $mask=[IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReparsePoint
    (($Entry.Attributes -band $mask) -ne 0)
}
function Get-SourceItemHash([string]$ItemPath) {
    if(-not [IO.Directory]::Exists($ItemPath)){throw "源条目不存在: $ItemPath"}
    $lines=New-Object 'System.Collections.Generic.List[string]'; $lines.Add('D|.')
    $pending=New-Object 'System.Collections.Generic.Stack[string]'; $pending.Push($ItemPath)
    while($pending.Count -gt 0){
        $current=$pending.Pop()
        foreach($child in @(Get-ChildItem -LiteralPath $current -Force|Where-Object{-not(Test-Excluded $_)}|Sort-Object FullName)){
            $rel=Get-Relative $ItemPath $child.FullName
            if($child.PSIsContainer){$lines.Add("D|$rel");$pending.Push($child.FullName)}
            else{$lines.Add("F|$rel|$($child.Length)|$(Get-FileSha $child.FullName)")}
        }
    }
    Get-TextHash ([string]::Join("`n",@($lines|Sort-Object)))
}
function Assert-Source($Payload) {
    $source=Get-Directory ([string]$Payload.source_root) '源目录'
    if((Get-TextHash $source.Replace('\','/').ToLowerInvariant()) -ne [string]$Payload.source_root_id){throw 'source_root_id 与源路径不一致'}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($item in @($Payload.items)){
        $actual=Get-SourceItemHash (Get-Inside $source ([string]$item.relative_path))
        if($actual -ne [string]$item.source_snapshot_hash){throw "源快照已变化: $($item.relative_path)"}
        $lines.Add("$($item.relative_path)|$actual")
    }
    if((Get-TextHash ([string]::Join("`n",$lines))) -ne [string]$Payload.source_snapshot_hash){throw '批次源快照哈希不一致'}
}
function Get-SafeName([string]$Name) {
    $safe=[regex]::Replace($Name,'[\x00-\x1f<>:"/\\|?*\[\]#^]','_').Trim().TrimEnd('.')
    if([string]::IsNullOrWhiteSpace($safe)){'_'}else{$safe}
}
function Read-Document([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path);$bom=$bytes.Length-ge 3-and$bytes[0]-eq 0xEF-and$bytes[1]-eq 0xBB-and$bytes[2]-eq 0xBF
    $offset=if($bom){3}else{0};$utf8=New-Object Text.UTF8Encoding($false,$true)
    $text=$utf8.GetString($bytes,$offset,$bytes.Length-$offset);$newline=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
    [pscustomobject]@{text=$text;bom=$bom;newline=$newline}
}
function Write-Document([string]$Path,[string]$Text,[bool]$Bom) {
    $parent=[IO.Path]::GetDirectoryName($Path);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($Bom)))
}
function Merge-Document([string]$Generated,[string]$ExistingPath) {
    $new=$Generated.Replace("`r`n","`n");$nm=[regex]::Match($new,'\A---\n(.*?)\n---\n?(.*)\z',[Text.RegularExpressions.RegexOptions]::Singleline)
    if(-not$nm.Success){throw '模板缺少有效 frontmatter'}
    if(-not[IO.File]::Exists($ExistingPath)){return [pscustomobject]@{text=$new;bom=$false;newline="`n"}}
    $doc=Read-Document $ExistingPath;$old=$doc.text.Replace("`r`n","`n");$om=[regex]::Match($old,'\A---\n(.*?)\n---\n?(.*)\z',[Text.RegularExpressions.RegexOptions]::Singleline)
    $oldYaml=@();$oldBody=$old;if($om.Success){$oldYaml=@($om.Groups[1].Value-split"`n");$oldBody=$om.Groups[2].Value}
    $yaml=New-Object 'System.Collections.Generic.List[string]';foreach($line in @($nm.Groups[1].Value-split"`n")){$yaml.Add($line)}
    foreach($line in $oldYaml){$km=[regex]::Match($line,'^([A-Za-z0-9_-]+)\s*:');if($km.Success-and$script:ManagedKeys-contains$km.Groups[1].Value){continue};$yaml.Add($line)}
    $begin='<!-- obsidian-bookshelf:begin -->';$end='<!-- obsidian-bookshelf:end -->';$newBody=$nm.Groups[2].Value
    $ns=$newBody.IndexOf($begin,[StringComparison]::Ordinal);$ne=$newBody.IndexOf($end,[StringComparison]::Ordinal)
    if($ns-lt 0-or$ne-lt$ns){throw '模板缺少受管区块'};$block=$newBody.Substring($ns,($ne+$end.Length)-$ns)
    $os=$oldBody.IndexOf($begin,[StringComparison]::Ordinal);$oe=$oldBody.IndexOf($end,[StringComparison]::Ordinal)
    if($os-ge 0-and$oe-ge$os){$body=$oldBody.Substring(0,$os)+$block+$oldBody.Substring($oe+$end.Length)}
    else{$separator=if([string]::IsNullOrEmpty($oldBody)){''}else{"`n`n"};$body=$oldBody+$separator+$block}
    $merged="---`n"+[string]::Join("`n",$yaml)+"`n---`n"+$body
    [pscustomobject]@{text=$merged.Replace("`n",$doc.newline);bom=[bool]$doc.bom;newline=$doc.newline}
}
function Expand-Template([string]$Name,[hashtable]$Values) {
    $path=Join-Path (Split-Path $PSScriptRoot -Parent) "assets\templates\$Name"
    if(-not[IO.File]::Exists($path)){throw "模板不存在: $Name"};$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    foreach($key in $Values.Keys){$text=$text.Replace('{{'+$key+'}}',[string]$Values[$key])}
    if([regex]::IsMatch($text,'\{\{[^}]+\}\}')){throw "模板变量未解析: $Name"};$text
}
function Get-TargetState([string]$Path) { if([IO.File]::Exists($Path)){[pscustomobject][ordered]@{exists=$true;sha256=Get-FileSha $Path}}else{[pscustomobject][ordered]@{exists=$false;sha256=''}} }
function Assert-Target([string]$Path,$State) {
    $exists=[IO.File]::Exists($Path);if($exists-ne[bool]$State.exists){throw "目标在 Preview 后变化: $Path"}
    if($exists-and(Get-FileSha $Path)-ne[string]$State.sha256){throw "目标内容在 Preview 后变化: $Path"}
}

if($Mode-eq'Preview'){
    if([string]::IsNullOrWhiteSpace($ScanPath)-or-not[IO.File]::Exists($ScanPath)){throw 'Preview 需要有效 ScanPath'}
    if([string]::IsNullOrWhiteSpace($VaultRoot)){throw 'Preview 需要 VaultRoot'}
    $vault=Get-Directory $VaultRoot 'Vault'
    if([IO.Path]::IsPathRooted($VaultSubdir)-or$VaultSubdir-match'(^|[\\/])\.\.([\\/]|$)'){throw 'VaultSubdir 必须是安全相对路径'}
    [void](Get-Inside $vault $VaultSubdir)
    $scan=[IO.File]::ReadAllText($ScanPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
    if([int]$scan.schema_version-ne 1){throw '不支持的扫描 schema_version'};Assert-Source $scan
    $route=[string]$scan.route;if(@('game','manga','photo','course')-notcontains$route){throw "未知路由: $route"}
    $hasAdvanced=$AdvancedItem.Count-gt 0-or$Character.Count-gt 0-or$InventoryConfirmed-or$ApprovedSmallLibraryStandard
    if(@('photo','course')-contains$route-and$hasAdvanced){throw "$route 路由永不生成进阶集群"}
    $selected=@($scan.items|ForEach-Object{[string]$_.relative_path})
    foreach($named in $AdvancedItem){if($selected-notcontains$named){throw "点名条目不在本批精确路径中: $named"}}
    $smallApproved=$InventoryConfirmed-and$ApprovedSmallLibraryStandard
    if($smallApproved-and[int]$scan.total_count-gt 20){throw '总数超过 20，不能使用小库标准触发'}
    $advanced=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($named in $AdvancedItem){[void]$advanced.Add($named)};if($smallApproved){foreach($rel in $selected){[void]$advanced.Add($rel)}}

    if([string]::IsNullOrWhiteSpace($StagingPath)){$StagingPath=Join-Path (Get-TempRoot) ("obsidian-bookshelf-stage-{0}"-f[Guid]::NewGuid().ToString('N'))}
    $stage=Assert-InTemp $StagingPath
    if([IO.Directory]::Exists($stage)-and@(Get-ChildItem -LiteralPath $stage -Force).Count-gt 0){throw "staging 非空，拒绝覆盖: $stage"}
    [IO.Directory]::CreateDirectory($stage)|Out-Null;$filesRoot=Join-Path $stage 'files';[IO.Directory]::CreateDirectory($filesRoot)|Out-Null

    $routeInfo=switch($route){
        'game'{@{folder='游戏库';moc='游戏书架.md';title='游戏书架';template='game-moc.md';props="platform: ''`ntype: ''`nstatus: ''"}}
        'manga'{@{folder='漫画库';moc='漫画书架.md';title='漫画书架';template='manga-moc.md';props="author: ''`nstatus: ''`ntags: []"}}
        'photo'{@{folder='照片库';moc='相册.md';title='相册';template='photo-moc.md';props="time: ''`nevent: ''"}}
        'course'{@{folder='课程库';moc='课程总览.md';title='课程总览';template='course-moc.md';props="course: ''`nsource: ''"}}
    }
    $used=@{};$safeNames=@{}
    foreach($item in @($scan.items)){
        $safe=Get-SafeName ([string]$item.title);$key=$safe.ToLowerInvariant()
        if($used.ContainsKey($key)){$short=(Get-TextHash ([string]$item.relative_path)).Substring(0,8);$safe="$safe-$short"}
        $used[$safe.ToLowerInvariant()]=$true;$safeNames[[string]$item.relative_path]=$safe
    }
    $fileSpecs=New-Object 'System.Collections.Generic.List[object]'
    function Add-Markdown([string]$VaultRelative,[string]$Generated){
        $target=Get-Inside $vault $VaultRelative;$merged=Merge-Document $Generated $target;$staged=Get-Inside $filesRoot $VaultRelative
        Write-Document $staged $merged.text $merged.bom
        $fileSpecs.Add([pscustomobject][ordered]@{vault_relative_path=$VaultRelative.Replace('\','/');staged_relative_path=Get-Relative $stage $staged;staged_sha256=Get-FileSha $staged;target_snapshot=Get-TargetState $target})
    }
    $links=New-Object 'System.Collections.Generic.List[string]'
    foreach($item in @($scan.items)){
        $itemRel=[string]$item.relative_path;$safe=[string]$safeNames[$itemRel]
        $cardRel=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/条目/'+$safe+'.md').TrimStart('/')
        $links.Add('- [['+$cardRel.Substring(0,$cardRel.Length-3)+']]')
        $card=Expand-Template 'card.md' @{title=[string]$item.title;route=$route;source_root_id=[string]$scan.source_root_id;relative_path=$itemRel;route_properties=$routeInfo.props;managed_body="- 源相对路径：``$itemRel```n- 自动化仅更新受管区块。"}
        Add-Markdown $cardRel $card
        if($advanced.Contains($itemRel)){
            $base=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/条目/'+$safe).TrimStart('/');$common=@{title=[string]$item.title;route=$route;source_root_id=[string]$scan.source_root_id;relative_path=$itemRel}
            if($route-eq'game'){Add-Markdown "$base/介绍.md" (Expand-Template 'intro.md' $common);Add-Markdown "$base/攻略.md" (Expand-Template 'guide.md' $common)}
            Add-Markdown "$base/剧情.md" (Expand-Template 'plot.md' $common);Add-Markdown "$base/角色索引.md" (Expand-Template 'characters-index.md' $common)
        }
    }
    foreach($characterSpec in $Character){
        $parts=$characterSpec-split'::',2
        if($parts.Count-ne 2-or-not$advanced.Contains($parts[0])-or[string]::IsNullOrWhiteSpace($parts[1])){throw "角色参数必须为已触发条目::角色名: $characterSpec"}
        $rel=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/条目/'+[string]$safeNames[$parts[0]]+'/角色/'+(Get-SafeName $parts[1])+'.md').TrimStart('/')
        Add-Markdown $rel (Expand-Template 'character.md' @{character=$parts[1];route=$route;source_root_id=[string]$scan.source_root_id;relative_path=$parts[0]})
    }
    $mocRel=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/'+$routeInfo.moc).TrimStart('/');$mocTarget=Get-Inside $vault $mocRel
    if([IO.File]::Exists($mocTarget)){foreach($m in [regex]::Matches((Read-Document $mocTarget).text,'(?m)^- \[\[[^\]]+\]\]$')){if(-not$links.Contains($m.Value)){$links.Add($m.Value)}}}
    Add-Markdown $mocRel (Expand-Template $routeInfo.template @{title=$routeInfo.title;managed_body=[string]::Join("`n",@($links|Sort-Object))})
    if(@('game','manga')-contains$route){$rel=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/分类/未分类.md').TrimStart('/');Add-Markdown $rel (Expand-Template 'category.md' @{title='未分类';route=$route;managed_body=[string]::Join("`n",@($links|Sort-Object))})}
    if($route-eq'photo'){$rel=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/时间轴.md').TrimStart('/');Add-Markdown $rel (Expand-Template 'timeline.md' @{title='时间轴';managed_body=[string]::Join("`n",@($links|Sort-Object))})}
    $homeFile=Join-Path $vault 'HOME.md'
    if([IO.File]::Exists($homeFile)){$homeGenerated="---`ntitle: HOME`nkind: moc`n---`n# HOME`n`n<!-- obsidian-bookshelf:begin -->`n- [[$($mocRel.Substring(0,$mocRel.Length-3))]]`n<!-- obsidian-bookshelf:end -->`n";Add-Markdown 'HOME.md' $homeGenerated}

    $imageSpecs=New-Object 'System.Collections.Generic.List[object]';$imageNames=@{};$allowed=@('.png','.jpg','.jpeg','.gif','.webp')
    foreach($relativeImage in $ApprovedImage){
        $sourceImage=Get-Inside ([string]$scan.source_root) $relativeImage
        if(-not[IO.File]::Exists($sourceImage)){throw "批准图片不存在: $relativeImage"};$info=Get-Item -LiteralPath $sourceImage -Force
        if((Test-Excluded $info)-or$allowed-notcontains$info.Extension.ToLowerInvariant()){throw "图片不符合批准规则: $relativeImage"}
        $safe=Get-SafeName $info.Name;$key=$safe.ToLowerInvariant();if($imageNames.ContainsKey($key)){$safe="$safe-$((Get-TextHash $relativeImage).Substring(0,8))"};$imageNames[$safe.ToLowerInvariant()]=$true
        $imageRel=($VaultSubdir.TrimEnd('\','/')+'/'+$routeInfo.folder+'/Assets/'+$safe).TrimStart('/');$staged=Get-Inside $filesRoot $imageRel;$parent=[IO.Path]::GetDirectoryName($staged);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($sourceImage,$staged,$false)
        $imageSpecs.Add([pscustomobject][ordered]@{source_relative_path=$relativeImage.Replace('\','/');source_sha256=Get-FileSha $sourceImage;vault_relative_path=$imageRel.Replace('\','/');staged_relative_path=Get-Relative $stage $staged;staged_sha256=Get-FileSha $staged;target_snapshot=Get-TargetState (Get-Inside $vault $imageRel)})
    }
    $last=[string]$scan.last_processed_before;if(@($scan.items).Count-gt 0){$last=[string]@($scan.items)[@($scan.items).Count-1].relative_path}
    $payload=[pscustomobject][ordered]@{
        schema_version=1;operation='gen-cards';source_root=[string]$scan.source_root;source_root_id=[string]$scan.source_root_id;source_snapshot_hash=[string]$scan.source_snapshot_hash;route=$route
        total_count=[int]$scan.total_count;processed_count_before=[int]$scan.processed_count_before;processed_count_after=([int]$scan.processed_count_before+@($scan.items).Count);last_processed_relpath=$last
        items=@($scan.items|ForEach-Object{[pscustomobject][ordered]@{relative_path=[string]$_.relative_path;source_snapshot_hash=[string]$_.source_snapshot_hash}})
        vault_root=$vault;vault_subdir=$VaultSubdir;files=$fileSpecs.ToArray();approved_images=$imageSpecs.ToArray();bookmark_snapshot=Get-TargetState (Join-Path $vault '.obsidian-bookshelf\last-run.json')
        cluster_trigger=if($smallApproved){'small-library-approved'}elseif($AdvancedItem.Count-gt 0){'named-items'}else{'basic-only'}
    }
    $hash=Get-TextHash ($payload|ConvertTo-Json -Depth 15 -Compress);$plan=[pscustomobject][ordered]@{payload=$payload;plan_hash=$hash}
    [IO.File]::WriteAllText((Join-Path $stage 'plan.json'),($plan|ConvertTo-Json -Depth 15),(New-Object Text.UTF8Encoding($false)))
    [pscustomobject][ordered]@{mode='Preview';staging_path=$stage;plan_hash=$hash;file_count=$fileSpecs.Count;image_count=$imageSpecs.Count;cluster_trigger=$payload.cluster_trigger;vault_writes=0}|ConvertTo-Json -Compress
    exit 0
}

if([string]::IsNullOrWhiteSpace($StagingPath)-or[string]::IsNullOrWhiteSpace($PlanHash)){throw 'Apply 需要 StagingPath 和 PlanHash'}
$stage=Assert-InTemp $StagingPath;$planPath=Join-Path $stage 'plan.json';if(-not[IO.File]::Exists($planPath)){throw 'staging 中没有 plan.json'}
$plan=[IO.File]::ReadAllText($planPath,[Text.Encoding]::UTF8)|ConvertFrom-Json;$actualHash=Get-TextHash ($plan.payload|ConvertTo-Json -Depth 15 -Compress)
if($actualHash-ne[string]$plan.plan_hash-or$actualHash-ne$PlanHash){throw 'plan_hash 验证失败'};if([string]$plan.payload.operation-ne'gen-cards'){throw '计划类型错误'}
Assert-Source $plan.payload;$vault=Get-Directory ([string]$plan.payload.vault_root) 'Vault';$approved=@($plan.payload.approved_images|ForEach-Object{[string]$_.source_relative_path})
foreach($requested in $Image){if($approved-notcontains$requested.Replace('\','/')){throw "图片未在 Preview 获批: $requested"}}
foreach($spec in @($plan.payload.files)){$target=Get-Inside $vault ([string]$spec.vault_relative_path);Assert-Target $target $spec.target_snapshot;$staged=Get-Inside $stage ([string]$spec.staged_relative_path);if(-not[IO.File]::Exists($staged)-or(Get-FileSha $staged)-ne[string]$spec.staged_sha256){throw "staging 文件变化: $($spec.staged_relative_path)"}}
foreach($spec in @($plan.payload.approved_images)){$sourceImage=Get-Inside ([string]$plan.payload.source_root) ([string]$spec.source_relative_path);if(-not[IO.File]::Exists($sourceImage)-or(Get-FileSha $sourceImage)-ne[string]$spec.source_sha256){throw "批准图片已变化: $($spec.source_relative_path)"};$target=Get-Inside $vault ([string]$spec.vault_relative_path);Assert-Target $target $spec.target_snapshot;$staged=Get-Inside $stage ([string]$spec.staged_relative_path);if(-not[IO.File]::Exists($staged)-or(Get-FileSha $staged)-ne[string]$spec.staged_sha256){throw "staging 图片变化: $($spec.staged_relative_path)"}}
$bookmark=Join-Path $vault '.obsidian-bookshelf\last-run.json';Assert-Target $bookmark $plan.payload.bookmark_snapshot
$transaction=Join-Path (Get-TempRoot) ("obsidian-bookshelf-transaction-{0}"-f[Guid]::NewGuid().ToString('N'));$backupRoot=Join-Path $transaction 'backup';[IO.Directory]::CreateDirectory($backupRoot)|Out-Null;$committed=New-Object 'System.Collections.Generic.List[object]'
try{
    foreach($spec in @($plan.payload.files)+@($plan.payload.approved_images)){
        $target=Get-Inside $vault ([string]$spec.vault_relative_path);$staged=Get-Inside $stage ([string]$spec.staged_relative_path);$backup=Get-Inside $backupRoot ([string]$spec.vault_relative_path);$existed=[IO.File]::Exists($target)
        if($existed){$parent=[IO.Path]::GetDirectoryName($backup);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($target,$backup,$true)}
        $parent=[IO.Path]::GetDirectoryName($target);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($staged,$target,$true);$committed.Add([pscustomobject]@{target=$target;backup=$backup;existed=$existed})
    }
    $bookmarkBackup=Get-Inside $backupRoot '.obsidian-bookshelf/last-run.json';$bookmarkExisted=[IO.File]::Exists($bookmark)
    if($bookmarkExisted){$parent=[IO.Path]::GetDirectoryName($bookmarkBackup);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($bookmark,$bookmarkBackup,$true)}
    $parent=[IO.Path]::GetDirectoryName($bookmark);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
    $bookmarkData=[pscustomobject][ordered]@{source_root_id=[string]$plan.payload.source_root_id;last_processed_relpath=[string]$plan.payload.last_processed_relpath;processed_count=[int]$plan.payload.processed_count_after;total_count=[int]$plan.payload.total_count;plan_hash=$actualHash}
    $tempBookmark=Join-Path $transaction 'last-run.json';[IO.File]::WriteAllText($tempBookmark,($bookmarkData|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)));[IO.File]::Copy($tempBookmark,$bookmark,$true);$committed.Add([pscustomobject]@{target=$bookmark;backup=$bookmarkBackup;existed=$bookmarkExisted})
}catch{
    for($i=$committed.Count-1;$i-ge 0;$i--){$entry=$committed[$i];if($entry.existed){[IO.File]::Copy($entry.backup,$entry.target,$true)}elseif([IO.File]::Exists($entry.target)){[IO.File]::Delete($entry.target)}};throw
}finally{if([IO.Directory]::Exists($transaction)){[IO.Directory]::Delete($transaction,$true)}}
[pscustomobject][ordered]@{mode='Apply';plan_hash=$actualHash;markdown_written=@($plan.payload.files).Count;images_written=@($plan.payload.approved_images).Count;bookmark_updated=$true}|ConvertTo-Json -Compress
