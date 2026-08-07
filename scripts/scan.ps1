[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][ValidateSet('game','manga','photo','course')][string]$Route,
    [string]$VaultRoot,
    [ValidateRange(1,10000)][int]$BatchSize = 50,
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Sha256Text([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-NormalizedDirectory([string]$Path, [string]$Label) {
    if (-not [System.IO.Directory]::Exists($Path)) { throw "$Label 不存在或不是目录: $Path" }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-RelativePath([string]$Base, [string]$Child) {
    $prefix = $Base.TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Child.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "路径越界: $Child" }
    return $Child.Substring($prefix.Length).Replace('\','/')
}

function Test-Excluded([System.IO.FileSystemInfo]$Entry) {
    $mask = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System -bor [System.IO.FileAttributes]::ReparsePoint
    return (($Entry.Attributes -band $mask) -ne 0)
}

function Get-ItemSnapshot([string]$ItemPath) {
    $records = New-Object System.Collections.Generic.List[object]
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('D|.')
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($ItemPath)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $children = @(Get-ChildItem -LiteralPath $current -Force | Where-Object { -not (Test-Excluded $_) } | Sort-Object FullName)
        foreach ($child in $children) {
            $relative = Get-RelativePath $ItemPath $child.FullName
            if ($child.PSIsContainer) {
                $lines.Add("D|$relative")
                $records.Add([pscustomobject][ordered]@{ type = 'directory'; relative_path = $relative })
                $pending.Push($child.FullName)
            } else {
                $hash = (Get-FileHash -LiteralPath $child.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                $lines.Add("F|$relative|$($child.Length)|$hash")
                $records.Add([pscustomobject][ordered]@{ type = 'file'; relative_path = $relative; length = [long]$child.Length; sha256 = $hash })
            }
        }
    }
    $orderedRecords = @($records | Sort-Object type, relative_path)
    $orderedLines = @($lines | Sort-Object)
    return [pscustomobject][ordered]@{
        hash = Get-Sha256Text ([string]::Join("`n", $orderedLines))
        records = $orderedRecords
    }
}

$source = Get-NormalizedDirectory $SourceRoot '源目录'
$normalizedIdentity = $source.Replace('\','/').ToLowerInvariant()
$sourceRootId = Get-Sha256Text $normalizedIdentity

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\','/')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $tempRoot ("obsidian-bookshelf-scan-{0}.json" -f [Guid]::NewGuid().ToString('N'))
}
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
$tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $outputFull.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "扫描输出必须位于系统临时目录: $outputFull" }

$entries = @(Get-ChildItem -LiteralPath $source -Directory -Force | Where-Object { -not (Test-Excluded $_) } | Sort-Object Name)
$relativeNames = @($entries | ForEach-Object { Get-RelativePath $source $_.FullName })
$totalCount = $entries.Count
$processedBefore = 0
$lastBefore = ''
$bookmarkUsed = $false

if (-not [string]::IsNullOrWhiteSpace($VaultRoot)) {
    $vault = Get-NormalizedDirectory $VaultRoot 'Vault'
    $bookmarkPath = Join-Path $vault '.obsidian-bookshelf\last-run.json'
    if ([System.IO.File]::Exists($bookmarkPath)) {
        $bookmark = [IO.File]::ReadAllText($bookmarkPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([string]$bookmark.source_root_id -eq $sourceRootId) {
            $bookmarkUsed = $true
            $lastBefore = [string]$bookmark.last_processed_relpath
            $processedBefore = [int]$bookmark.processed_count
            if ($processedBefore -lt 0 -or $processedBefore -gt $totalCount) { throw '书签 processed_count 超出当前库范围' }
            if ($processedBefore -gt 0) {
                $index = [Array]::IndexOf([string[]]$relativeNames, $lastBefore)
                if ($index -lt 0 -or ($index + 1) -ne $processedBefore) { throw '书签相对路径与当前排序不一致，拒绝不确定续跑' }
            }
        }
    }
}

$selectedEntries = @($entries | Select-Object -Skip $processedBefore -First $BatchSize)
$items = New-Object System.Collections.Generic.List[object]
foreach ($entry in $selectedEntries) {
    $snapshot = Get-ItemSnapshot $entry.FullName
    $relative = Get-RelativePath $source $entry.FullName
    $items.Add([pscustomobject][ordered]@{
        relative_path = $relative
        title = $entry.Name
        source_snapshot_hash = $snapshot.hash
        snapshot = $snapshot.records
    })
}
$sourceSnapshotLines = @($items | ForEach-Object { "$($_.relative_path)|$($_.source_snapshot_hash)" })
$scan = [pscustomobject][ordered]@{
    schema_version = 1
    source_root = $source
    source_root_id = $sourceRootId
    route = $Route
    batch_size = $BatchSize
    total_count = $totalCount
    processed_count_before = $processedBefore
    last_processed_before = $lastBefore
    bookmark_used = $bookmarkUsed
    items = $items.ToArray()
    source_snapshot_hash = Get-Sha256Text ([string]::Join("`n", $sourceSnapshotLines))
}

$parent = [System.IO.Path]::GetDirectoryName($outputFull)
if (-not [System.IO.Directory]::Exists($parent)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
[System.IO.File]::WriteAllText($outputFull, ($scan | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

[pscustomobject][ordered]@{
    scan_path = $outputFull
    source_root_id = $sourceRootId
    total_count = $totalCount
    processed_count_before = $processedBefore
    selected_count = $items.Count
    bookmark_used = $bookmarkUsed
} | ConvertTo-Json -Compress
