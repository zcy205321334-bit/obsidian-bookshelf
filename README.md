# Obsidian Bookshelf

把本地游戏 / 漫画 / 照片 / 课程目录安全地整理成 Obsidian wiki 的 agent skill。

SKILL.md 定义工作流（九步 SOP），PowerShell 脚本负责全部确定性计算（盘点、卡片生成、链接修复），references/ 承载数据模型与路由规范。**不修改源文件、不覆盖人工笔记、不联网**，Preview→Apply 双阶段 + plan_hash 校验保证可回滚。

## 目录结构

```
obsidian-bookshelf/
├── SKILL.md                  # 主规范：安全边界、九步 SOP、阶段路由、续跑规则
├── references/
│   ├── routes.md             # 路由、阶段、进阶触发条件
│   ├── schema.md             # 数据模型、受管属性、事务与哈希
│   └── examples.md           # 命令示例（虚构目录）
├── assets/templates/         # 可复制模板（MOC/卡片/角色页等）
└── scripts/
    ├── scan.ps1              # 盘点（分批、续跑、书签）
    ├── gen-cards.ps1         # Preview / Apply 双阶段卡片生成
    ├── fix-links.ps1         # 链接审计与修复
    └── self-test.ps1         # 开发自检（PASS=29 FAIL=0）
```

## 安装

把整个目录复制到你的 agent 的 skills 目录：

| Agent | 目标路径 |
|---|---|
| Codex CLI | `C:\Users\<你>\.codex\skills\obsidian-bookshelf\` |
| OpenClaw / QClaw | `C:\Users\<你>\<QClaw配置目录>\skills\obsidian-bookshelf\` |
| Hermes | `~/AppData/Local/hermes/skills/note-taking/obsidian-bookshelf/` |

## 自检

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/self-test.ps1
```

预期输出 `PASS=29  FAIL=0`（覆盖编码门禁、安全边界、事务、路由拒绝、图片批准、链接修复）。

## 使用

见 `SKILL.md` 九步 SOP。核心流程：`scan.ps1` 盘点 → 用户确认 → `gen-cards.ps1 -Mode Preview` 审阅 → `-Mode Apply` 落盘。游戏/漫画支持进阶集群（介绍/剧情/攻略/角色页），照片/课程只生成基础卡片；角色页仅通过 `-Character '条目相对路径::角色名'` 生成且角色名必须由用户明确提供。

## License

MIT
