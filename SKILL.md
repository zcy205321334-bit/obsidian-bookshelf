---
name: game-wiki-curation
description: 维护用户个人Obsidian游戏wiki时使用：书架化、评判页模板、断链审计、库存现状。
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [obsidian, wiki, 游戏书架, 评判页, 断链]
    related_skills: [obsidian, skill-qa]
---

# 用户游戏 Wiki 策展

## vault 与结构

- 主 vault：`<wiki目录>`（.obsidian 标志）。**注意**：`<文档目录>/Obsidian Vault` 是另一个 PARA 结构 vault，别搞混。
- 游戏域在 `生活/游戏/`：
  - `游戏书架.md`：MOC——书架导航表（各分类+数量+路径）+ Dataview 检索（`TABLE 类型,大小,位置,状态 FROM "生活/游戏"`）+ 仓库统计
  - 分类子目录：`Gal-VN`、`RPG`/`SLG-模拟`/`ACT-动作`/`Steam正版`/`KR模拟器`/`其他`（按实际收藏结构调整）

## 九步 SOP

1. **盘点**：`scripts/scan.ps1 -SourceRoot <游戏目录> -VaultRoot <wiki目录> -Route game`（默认批次 50，书签续跑）
2. **用户确认**：盘点结果（数量/分类/路径）给用户过目，用户确认后再生成
3. **预览**：`scripts/gen-cards.ps1 -Mode Preview`——生成卡片到 staging，不落盘
4. **审阅**：用户审阅预览（模板/字段/链接）
5. **落盘**：`scripts/gen-cards.ps1 -Mode Apply`——事务式写入，plan_hash 校验，可回滚
6. **链接审计**：`scripts/fix-links.ps1 -Mode Audit`（子目录审计的 broken 数必须人工甄别——scope 外链接如 `[[Gal-VN]]` 在全库存在时会误报）
7. **修复**：`scripts/fix-links.ps1 -Mode Preview/Apply` 修复断链
8. **进阶内容**（可选）：游戏/漫画在用户明确点名后生成介绍/剧情/攻略/角色页；照片/课程只生成基础卡片
9. **验收**：`scripts/self-test.ps1`（预期 PASS=29 FAIL=0）+ 全库断链复检 + 字段完整性检查

## 安全边界

- **不修改源文件**：扫描只读，写入只发生在 vault 内
- **不覆盖人工笔记**：受管区块用 `<!-- obsidian-bookshelf:begin/end -->` 标记界定，只替换白名单属性和受管区块
- **不联网**：核心流程完全离线
- **可回滚**：Preview→Apply 双阶段 + plan_hash 校验，Apply 前先备份目标

## 评判页模板（体验向，非百科）

**不要**（frontmatter+表格+正文出现处全删）：平台、引擎、开发商、发行商、首发日期、语言、分级；`## 内容分级说明`、`## 外部链接` 小节整删。
**要**：
- frontmatter：`tags/类型/画风/大小/文件数/位置/文档/CG/汉化/状态/通关日期/创建/更新`
- 信息表格：类型 / 画风 / 时长 / 可攻略角色 / 标签
- 小节顺序：概述 → 游戏定位与风格 → 故事背景 → 角色群像 → 游戏系统 → 美术与技术（仅画风/CG表现/换装）→ 版本与本地收藏 → 评价与影响 → 相关页面 → 关联
- 关联：返回分类（`[[Gal-VN]]`）、`[[游戏书架]]`、同系列续作（不存在标"待补充"）
- 文风：真实体验细节（数值、事件日期）> 百科罗列；社区口碑可引用，缺失事实留空不编造

## 断链审计要点

- **精确方法**（Obsidian 规则：wikilink 按文件名全库解析）：提取全部 `[[目标]]`（去掉 `|别名` 和 `#锚点`），逐一检查 vault 全库是否存在同名 `.md`；图片嵌入 `![[x.png]]` 同理。直接用 `python scripts/obsidian-link-audit.py "<wiki目录>" --scope 生活/游戏/Gal-VN`（支持 --scope 限定目录、--name-filter 限定文件名）。
- **命名体系要统一**：页面用空格"<示例游戏#8> 全"，角色用连字符"<示例游戏#8>-美雪"就不统一（wikilink 必须与文件名逐字一致）。**新页面命名规则：主条目=主题名，子页=短名，不放系列前缀。**
- 占位链接（`[[乡村狂想曲]]` 标"待补充"）是已知断链，用户可接受，不必修。

## 进阶触发规则

- 游戏与漫画只允许：用户在盘点后以 `-AdvancedItem` 精确点名；或 `total_count <= 20` 且用户在盘点后明确说"按这个标准做"，同时传入 `-InventoryConfirmed -ApprovedSmallLibraryStandard`。不得把"都整理一下""详细一点"等表达解释为触发。照片与课程即使传入上述参数也拒绝进阶集群。
- 角色页仅通过 `-Character '条目相对路径::角色名'` 生成且角色名必须由用户明确提供。没有用户提供的角色资料时不虚构角色页。

## 验证清单

- [ ] 改 wiki 文件前先重读（用户可能在 Obsidian 里动过，patch 会因格式漂移失败）
- [ ] 断链判断用全库同名解析，不用 fix-links 子目录 Audit 的裸数字
- [ ] 评判页不出现被禁 7 字段和外部链接
- [ ] 集群/文件计数对账用 Python（os.listdir + isdir），不用 `find | grep | wc` 管道——含 `[ ]` 等特殊字符的目录名会让 find 计数假象
- [ ] 批量替换前核对白名单节范围：全局 str.replace 会误改白名单外节；用带节标题的正则限定替换范围
- [ ] 越界检查路径先统一分隔符（`\` vs `/` 字符串不等会误报越界）；双向核对
- [ ] 数据源查证：评分/简介引用须标注来源（Steam/vndb/DLsite/bangumi），查不到标"未知"或"待补"，禁止编造

## License

MIT
