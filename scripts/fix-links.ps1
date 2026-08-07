[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Audit','Preview','Apply')][string]$Mode,
    [string]$RootPath,
    [string]$ScopeRelativePath,
    [string]$StagingPath,
    [string]$PlanHash
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Get-TextHash([string]$Text){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Get-FileSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-Directory([string]$Path,[string]$Label){if(-not[IO.Directory]::Exists($Path)){throw "$Label 不存在: $Path"};[IO.Path]::GetFullPath($Path).TrimEnd('\','/')}
function Get-TempRoot{[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')}
function Assert-InTemp([string]$Path){$full=[IO.Path]::GetFullPath($Path);$prefix=(Get-TempRoot)+[IO.Path]::DirectorySeparatorChar;if(-not$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "staging 必须位于系统临时目录: $full"};$full}
function Get-Inside([string]$Root,[string]$Relative){if([IO.Path]::IsPathRooted($Relative)){throw "不允许绝对相对路径: $Relative"};$full=[IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/',[IO.Path]::DirectorySeparatorChar)));$prefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;if($full-ne$Root-and-not$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "路径越界: $Relative"};$full}
function Get-Relative([string]$Root,[string]$Child){$prefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;if(-not$Child.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "路径越界: $Child"};$Child.Substring($prefix.Length).Replace('\','/')}
function Test-Excluded([IO.FileSystemInfo]$Entry){$mask=[IO.FileAttributes]::Hidden-bor[IO.FileAttributes]::System-bor[IO.FileAttributes]::ReparsePoint;(($Entry.Attributes-band$mask)-ne 0)}
function Get-SafeName([string]$Name){$safe=[regex]::Replace($Name,'[\x00-\x1f<>:"/\\|?*\[\]#^]','_').Trim().TrimEnd('.');if([string]::IsNullOrWhiteSpace($safe)){'_'}else{$safe}}
function Read-Document([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$bom=$bytes.Length-ge 3-and$bytes[0]-eq 0xEF-and$bytes[1]-eq 0xBB-and$bytes[2]-eq 0xBF;$offset=if($bom){3}else{0};$utf8=New-Object Text.UTF8Encoding($false,$true);$text=$utf8.GetString($bytes,$offset,$bytes.Length-$offset);$newline=if($text.Contains("`r`n")){"`r`n"}else{"`n"};[pscustomobject]@{text=$text;bom=$bom;newline=$newline}}
function Write-Document([string]$Path,[string]$Text,[bool]$Bom){$parent=[IO.Path]::GetDirectoryName($Path);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($Bom)))}
function Get-State([string]$Path){if([IO.File]::Exists($Path)){[pscustomobject][ordered]@{exists=$true;sha256=Get-FileSha $Path}}else{[pscustomobject][ordered]@{exists=$false;sha256=''}}}
function Assert-State([string]$Path,$State){$exists=[IO.File]::Exists($Path);if($exists-ne[bool]$State.exists){throw "文件在 Preview 后变化: $Path"};if($exists-and(Get-FileSha $Path)-ne[string]$State.sha256){throw "文件内容在 Preview 后变化: $Path"}}

function Get-LinkModel([string]$Root,[string]$ScopeRelative){
    if([IO.Path]::IsPathRooted($ScopeRelative)-or$ScopeRelative-match'(^|[\\/])\.\.([\\/]|$)'){throw 'ScopeRelativePath 必须是安全相对路径'}
    $scope=Get-Inside $Root $ScopeRelative;if(-not[IO.Directory]::Exists($scope)){throw "审计子目录不存在: $scope"}
    $files=@(Get-ChildItem -LiteralPath $scope -File -Filter '*.md' -Recurse -Force|Where-Object{-not(Test-Excluded $_)}|Sort-Object FullName)
    $records=New-Object 'System.Collections.Generic.List[object]';$baseGroups=@{}
    foreach($file in $files){$rel=Get-Relative $scope $file.FullName;$stem=$rel.Substring(0,$rel.Length-3);$dir=[IO.Path]::GetDirectoryName($rel);if($null-eq$dir){$dir=''};$base=[IO.Path]::GetFileName($stem);$key=($dir.Replace('\','/')+'/'+$base).ToLowerInvariant();if(-not$baseGroups.ContainsKey($key)){$baseGroups[$key]=New-Object 'System.Collections.Generic.List[string]'};$baseGroups[$key].Add($rel)}
    $finalUsed=@{}
    foreach($file in $files){
        $rel=Get-Relative $scope $file.FullName;$dir=[IO.Path]::GetDirectoryName($rel);if($null-eq$dir){$dir=''};$base=[IO.Path]::GetFileNameWithoutExtension($rel);$safe=Get-SafeName $base
        $groupKey=($dir.Replace('\','/')+'/'+$base).ToLowerInvariant();if($baseGroups[$groupKey].Count-gt 1){$safe="$safe-$((Get-TextHash $rel).Substring(0,8))"}
        if([string]::IsNullOrEmpty($dir)){$final=$safe+'.md'}else{$final=$dir.Replace('\','/')+'/'+$safe+'.md'};$key=$final.ToLowerInvariant()
        if($finalUsed.ContainsKey($key)){if([string]::IsNullOrEmpty($dir)){$stemPrefix=$safe}else{$stemPrefix=$dir.Replace('\','/')+'/'+$safe};$final=$stemPrefix+'-'+(Get-TextHash $rel).Substring(0,8)+'.md'};$finalUsed[$final.ToLowerInvariant()]=$true
        $doc=Read-Document $file.FullName;$records.Add([pscustomobject][ordered]@{original_relative=$rel;final_relative=$final;original_stem=$rel.Substring(0,$rel.Length-3);final_stem=$final.Substring(0,$final.Length-3);base_name=$base;text=$doc.text;bom=$doc.bom;newline=$doc.newline})
    }
    [pscustomobject]@{scope=$scope;records=$records.ToArray()}
}

function Resolve-Link([string]$Target,$Model,[string]$ScopeRelative){
    $plain=($Target-split'#',2)[0].TrimEnd('\').Replace('\','/').TrimStart('/')
    $scopePrefix=$ScopeRelative.Trim('/').Replace('\','/')
    if(-not[string]::IsNullOrEmpty($scopePrefix)-and$plain.StartsWith($scopePrefix+'/',[StringComparison]::OrdinalIgnoreCase)){$plain=$plain.Substring($scopePrefix.Length+1)}
    $direct=@($Model.records|Where-Object{$_.original_stem-eq$plain-or$_.final_stem-eq$plain})
    if($direct.Count-eq 1){return $direct[0]}
    $base=[IO.Path]::GetFileName($plain);$byBase=@($Model.records|Where-Object{$_.base_name-eq$base-or[IO.Path]::GetFileName($_.final_stem)-eq$base})
    if($byBase.Count-eq 1){return $byBase[0]};$null
}

function Convert-Links($Model,[string]$ScopeRelative,[switch]$AuditOnly){
    $broken=New-Object 'System.Collections.Generic.List[object]';$outputs=New-Object 'System.Collections.Generic.List[object]';$changes=0
    foreach($record in $Model.records){
        $lines=$record.text-split'(?<=\r\n)|(?<=\n)';$newLines=New-Object 'System.Collections.Generic.List[string]';$lineNumber=0
        foreach($line in $lines){$lineNumber++;$matches=@([regex]::Matches($line,'\[\[([^\]\|]+)(?:\\?\|([^\]]+))?\]\]'));$rebuilt=$line
            for($i=$matches.Count-1;$i-ge 0;$i--){$m=$matches[$i];$resolved=Resolve-Link $m.Groups[1].Value $Model $ScopeRelative
                if($null-eq$resolved){$broken.Add([pscustomobject]@{file=$record.original_relative;line=$lineNumber;target=$m.Groups[1].Value});continue}
                $prefix=$ScopeRelative.Trim('/').Replace('\','/');$newTarget=if([string]::IsNullOrEmpty($prefix)){$resolved.final_stem}else{$prefix+'/'+$resolved.final_stem}
                $alias=if($m.Groups[2].Success){$m.Groups[2].Value}else{''};$separator=if([string]::IsNullOrEmpty($alias)){''}elseif($line.TrimStart().StartsWith('|')){'\|'+$alias}else{'|'+$alias}
                $replacement='[['+$newTarget+$separator+']]';if($replacement-ne$m.Value){$changes++};$rebuilt=$rebuilt.Substring(0,$m.Index)+$replacement+$rebuilt.Substring($m.Index+$m.Length)
            };$newLines.Add($rebuilt)
        }
        if($record.original_relative-ne$record.final_relative){$changes++};$outputs.Add([pscustomobject]@{record=$record;text=[string]::Join('',$newLines)})
    }
    [pscustomobject]@{broken=$broken.ToArray();outputs=$outputs.ToArray();changes=$changes}
}

if($Mode-eq'Audit'-or$Mode-eq'Preview'){
    if([string]::IsNullOrWhiteSpace($RootPath)-or[string]::IsNullOrWhiteSpace($ScopeRelativePath)){throw "$Mode 需要 RootPath 与 ScopeRelativePath"}
    $root=Get-Directory $RootPath '根目录';$model=Get-LinkModel $root $ScopeRelativePath;$converted=Convert-Links $model $ScopeRelativePath
    if($converted.broken.Count-gt 0){[pscustomobject][ordered]@{mode=$Mode;files=$model.records.Count;broken_count=$converted.broken.Count;broken=$converted.broken;status='failed'}|ConvertTo-Json -Depth 6 -Compress;exit 2}
    if($Mode-eq'Audit'){[pscustomobject][ordered]@{mode='Audit';files=$model.records.Count;broken_count=0;changes_required=$converted.changes;status='passed'}|ConvertTo-Json -Compress;exit 0}
    if([string]::IsNullOrWhiteSpace($StagingPath)){$StagingPath=Join-Path (Get-TempRoot) ("obsidian-bookshelf-links-{0}"-f[Guid]::NewGuid().ToString('N'))};$stage=Assert-InTemp $StagingPath
    if([IO.Directory]::Exists($stage)-and@(Get-ChildItem -LiteralPath $stage -Force).Count-gt 0){throw "staging 非空，拒绝覆盖: $stage"};[IO.Directory]::CreateDirectory($stage)|Out-Null;$filesRoot=Join-Path $stage 'files';[IO.Directory]::CreateDirectory($filesRoot)|Out-Null
    $specs=New-Object 'System.Collections.Generic.List[object]'
    foreach($output in $converted.outputs){$record=$output.record;$staged=Get-Inside $filesRoot $record.final_relative;Write-Document $staged $output.text $record.bom;$original=Get-Inside $model.scope $record.original_relative;$final=Get-Inside $model.scope $record.final_relative;$specs.Add([pscustomobject][ordered]@{original_relative=$record.original_relative;final_relative=$record.final_relative;staged_relative=Get-Relative $stage $staged;staged_sha256=Get-FileSha $staged;original_state=Get-State $original;final_state=if($original-eq$final){Get-State $original}else{Get-State $final}})}
    $payload=[pscustomobject][ordered]@{schema_version=1;operation='fix-links';root=$root;scope_relative=$ScopeRelativePath;files=$specs.ToArray()};$hash=Get-TextHash ($payload|ConvertTo-Json -Depth 12 -Compress);$plan=[pscustomobject][ordered]@{payload=$payload;plan_hash=$hash};[IO.File]::WriteAllText((Join-Path $stage 'plan.json'),($plan|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
    [pscustomobject][ordered]@{mode='Preview';staging_path=$stage;plan_hash=$hash;files=$specs.Count;changes=$converted.changes;root_writes=0}|ConvertTo-Json -Compress;exit 0
}

if([string]::IsNullOrWhiteSpace($StagingPath)-or[string]::IsNullOrWhiteSpace($PlanHash)){throw 'Apply 需要 StagingPath 和 PlanHash'};$stage=Assert-InTemp $StagingPath;$planPath=Join-Path $stage 'plan.json';if(-not[IO.File]::Exists($planPath)){throw 'staging 中没有 plan.json'}
$plan=[IO.File]::ReadAllText($planPath,[Text.Encoding]::UTF8)|ConvertFrom-Json;$hash=Get-TextHash ($plan.payload|ConvertTo-Json -Depth 12 -Compress);if($hash-ne[string]$plan.plan_hash-or$hash-ne$PlanHash){throw 'plan_hash 验证失败'};if([string]$plan.payload.operation-ne'fix-links'){throw '计划类型错误'}
$root=Get-Directory ([string]$plan.payload.root) '根目录';$scope=Get-Inside $root ([string]$plan.payload.scope_relative);$transaction=Join-Path (Get-TempRoot) ("obsidian-bookshelf-links-transaction-{0}"-f[Guid]::NewGuid().ToString('N'));$backupRoot=Join-Path $transaction 'backup';[IO.Directory]::CreateDirectory($backupRoot)|Out-Null;$committed=New-Object 'System.Collections.Generic.List[object]'
foreach($spec in @($plan.payload.files)){$original=Get-Inside $scope ([string]$spec.original_relative);$final=Get-Inside $scope ([string]$spec.final_relative);Assert-State $original $spec.original_state;if($original-ne$final){Assert-State $final $spec.final_state};$staged=Get-Inside $stage ([string]$spec.staged_relative);if(-not[IO.File]::Exists($staged)-or(Get-FileSha $staged)-ne[string]$spec.staged_sha256){throw "staging 文件变化: $($spec.staged_relative)"}}
try{
    foreach($spec in @($plan.payload.files)){$original=Get-Inside $scope ([string]$spec.original_relative);$final=Get-Inside $scope ([string]$spec.final_relative);$staged=Get-Inside $stage ([string]$spec.staged_relative);$backup=Get-Inside $backupRoot ([string]$spec.original_relative);$parent=[IO.Path]::GetDirectoryName($backup);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($original,$backup,$true);$parent=[IO.Path]::GetDirectoryName($final);if(-not[IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($staged,$final,$true);$committed.Add([pscustomobject]@{original=$original;final=$final;backup=$backup})}
    foreach($entry in $committed){if($entry.original-ne$entry.final-and[IO.File]::Exists($entry.original)){[IO.File]::Delete($entry.original)}}
}catch{
    foreach($entry in $committed){if($entry.final-ne$entry.original-and[IO.File]::Exists($entry.final)){[IO.File]::Delete($entry.final)};[IO.File]::Copy($entry.backup,$entry.original,$true)};throw
}finally{if([IO.Directory]::Exists($transaction)){[IO.Directory]::Delete($transaction,$true)}}
[pscustomobject][ordered]@{mode='Apply';plan_hash=$hash;files_written=@($plan.payload.files).Count}|ConvertTo-Json -Compress
