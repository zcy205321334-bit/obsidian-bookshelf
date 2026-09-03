# 📚 Obsidian Bookshelf

**把散落在硬盘里的游戏、漫画、照片和课程，整理成一座能在 Obsidian 里浏览的书架。**

收藏放在不同文件夹里，找起来得一层层翻。这个 Skill 会为它们生成分类页和条目卡片，让你从 Obsidian 里找到对应的文件，也能在旁边记下自己的笔记。

这是一个给 AI Agent 使用的 Skill。告诉它要整理哪个目录，它会先盘点、做预览，等你确认后再写入笔记。

## ✨ 能做什么

| 你想做的事 | 它会帮你做 |
|---|---|
| 看清一个目录里有哪些收藏 | 扫描目录，生成清单，支持分批和续跑 |
| 给收藏建立 Obsidian 入口 | 生成分类页和条目卡片 |
| 整理已有笔记之间的联系 | 检查并修复符合规则的内部链接 |
| 补充游戏、漫画的资料页 | 在你明确指定范围后，创建介绍、剧情、攻略等页面 |

源文件保持原样，已有笔记中的人工内容也会保留。

## 💬 怎么用

装好后，可以这样对 Agent 说

```text
把 D:\收藏\游戏 整理成 Obsidian 书架。
先给我看分类和卡片预览，确认后再写入 D:\笔记\收藏。
```

也可以从几个文件夹开始

```text
先整理这三个课程文件夹，每个课程做一张卡片，并建立一个课程目录页。
```

每次整理都会先给你看结果，确认后再写入笔记。

**选目录 → 看盘点结果 → 看笔记预览 → 确认写入**

## 📦 安装

对支持安装 Skill 的 Agent 说

```text
帮我安装这个 Skill：
https://github.com/zcy205321334-bit/obsidian-bookshelf
```

也可以手动下载

```bash
git clone --depth 1 https://github.com/zcy205321334-bit/obsidian-bookshelf.git
```

把整个 `obsidian-bookshelf` 文件夹放进你的 Agent 的 Skills 目录。保留 `SKILL.md`、`scripts/`、`references/` 和 `assets/`，具体安装位置按所用 Agent 的配置确定。

运行脚本需要 **Windows 与 PowerShell 5.1 或更高版本**。

## 使用前知道这几件事

- **先预览，再写入。** 确认目录和卡片内容后再执行 Apply。
- **核心整理流程离线运行。** 外部评分、简介等资料不会凭空补齐。
- 游戏、漫画支持进一步整理资料页；照片、课程主要生成基础卡片。
- 角色页需要你明确提供角色名，已有人工笔记不会被整页覆盖。

<details>
<summary>文件说明与自检</summary>

| 文件 | 用途 |
|---|---|
| [SKILL.md](https://github.com/zcy205321334-bit/obsidian-bookshelf/blob/main/SKILL.md) | Agent 的使用流程与边界 |
| [scripts/](https://github.com/zcy205321334-bit/obsidian-bookshelf/tree/main/scripts) | 扫描、生成卡片和修复链接 |
| [references/](https://github.com/zcy205321334-bit/obsidian-bookshelf/tree/main/references) | 数据结构、路由和命令示例 |
| [assets/templates/](https://github.com/zcy205321334-bit/obsidian-bookshelf/tree/main/assets/templates) | 笔记模板 |

在仓库根目录运行自检

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/self-test.ps1
```

</details>

## 反馈

使用中遇到问题，欢迎[提 Issue](https://github.com/zcy205321334-bit/obsidian-bookshelf/issues)。附上执行步骤和错误信息，更容易定位原因。

## 许可

MIT。
