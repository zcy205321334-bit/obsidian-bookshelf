#!/usr/bin/env python3
"""Obsidian 全库同名 wikilink 断链审计（比 fix-links 子目录 Audit 准——后者只建 scope 内模型，scope 外链接误报 broken）。

用法:
    python obsidian-link-audit.py [vault] [--scope 生活/游戏/Gal-VN] [--name-filter <示例游戏#8>]

规则（Obsidian 解析）:
    - wikilink 按文件名全库同名解析（任意目录），[[目标]] 去 |别名 和 #锚点
    - 图片嵌入 ![[x.png]] 同理，按全库同名文件检查
    - 占位链接（标"待补充"）是已知断链，输出里人工甄别
"""
import os, re, sys, argparse

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vault", nargs="?", default=r"<wiki目录>")
    ap.add_argument("--scope", default="", help="只审计该相对子目录下的文件")
    ap.add_argument("--name-filter", default="", help="只审计文件名含此串的文件")
    args = ap.parse_args()

    vault = os.path.abspath(args.vault)
    # 全库文件名（去扩展名）→ 同名解析集合；png/jpg 等嵌入图也算
    all_notes = set()
    for root, _, files in os.walk(vault):
        for f in files:
            if f.lower().endswith((".md", ".png", ".jpg", ".jpeg", ".webp", ".gif")):
                all_notes.add(os.path.splitext(f)[0])
                if f.endswith(".md"):
                    all_notes.add(f[:-3])

    target_root = os.path.join(vault, args.scope) if args.scope else vault
    target_files = []
    for root, _, files in os.walk(target_root):
        for f in files:
            if not f.endswith(".md"):
                continue
            if args.name_filter and args.name_filter not in f:
                continue
            target_files.append(os.path.join(root, f))

    link_re = re.compile(r"\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]")
    broken, checked = [], 0
    for path in sorted(target_files):
        rel = os.path.relpath(path, vault)
        with open(path, encoding="utf-8") as fh:
            for i, line in enumerate(fh, 1):
                for m in link_re.finditer(line):
                    base = m.group(1).strip().split("#")[0].strip()
                    checked += 1
                    name = os.path.basename(base)
                    if name not in all_notes and base.lstrip("/") not in all_notes:
                        broken.append((rel, i, m.group(1).strip()))

    print(f"文件 {len(target_files)} 个，链接 {checked} 条，断链 {len(broken)} 处")
    for rel, line, target in broken:
        print(f"  {rel}:{line} -> [[{target}]]")

if __name__ == "__main__":
    main()
