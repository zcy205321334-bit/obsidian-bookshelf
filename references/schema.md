# 数据与安全模型

## 路径身份

每个条目使用二元身份：`source_root_id + relative_path`。`source_root_id` 是规范化绝对源路径的小写 SHA-256；`relative_path` 使用源根下的相对路径，不保存可变的盘符外推断。

扫描 JSON 至少包含 `schema_version`、`source_root`、`source_root_id`、`route`、`batch_size`、`total_count`、`processed_count_before`、`last_processed_before`、`items` 和 `source_snapshot_hash`。每个 item 包含 `relative_path`、`title`、`source_snapshot_hash` 和文件快照；空目录也有稳定快照。

## 书签

`.obsidian-bookshelf/last-run.json` 只包含一个最近成功任务：

```json
{"source_root_id":"sha256","last_processed_relpath":"虚构条目","processed_count":50,"total_count":120,"plan_hash":"sha256"}
```

scan 只读书签。只有 `gen-cards.ps1 -Mode Apply` 的全部文件提交成功后才以事务方式替换书签。

## 受管 Markdown

属性键全部使用英文。生成器可更新的属性白名单为 `title`, `route`, `kind`, `bookshelf_source_root_id`, `bookshelf_relpath`, `bookshelf_plan_hash`, `platform`, `type`, `status`, `author`, `tags`, `time`, `event`, `course`, `source`。

正文由以下标记界定：

```markdown
<!-- obsidian-bookshelf:begin -->
自动生成内容
<!-- obsidian-bookshelf:end -->
```

生成器只替换白名单属性和这一受管区块。其他 frontmatter 键、标记外正文、UTF-8 BOM 与 CRLF/LF 风格原样保留。缺少标记时把受管区块追加到人工正文之后。

## Preview 与 Apply

Preview 只在系统临时目录创建 staging，保存目标相对路径、预览内容、源快照、目标快照、批准图片及规范化计划哈希。Apply 必须同时满足：调用者哈希与计划一致、源快照一致、目标快照一致、图片在批准清单且哈希未变、所有相对路径位于指定 vault 子目录内。

Apply 先在系统临时事务目录准备全部输出，再备份目标并提交。任一写入失败时恢复已有目标并移除本事务新建目标；书签最后写入。

## 文件名与链接

Windows 危险字符、控制字符以及会干扰 wikilink 的 `[]#^` 转为下划线；保留 Unicode 和空格。清理后重名时，追加由原始相对路径 SHA-256 前 8 位生成的稳定短哈希。Markdown 表格里的 wikilink 分隔符写作 `\|`。
