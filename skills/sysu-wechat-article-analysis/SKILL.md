---
name: sysu-wechat-article-analysis
description: Analyze a single Sun Yat-sen University WeChat article from md/*.md into clean_md, article_analysis_md, and article_json outputs. Use when Codex needs to process 中山大学公众号推文, create clean Markdown with anchors, build fact-traceable analysis docs, generate writing-training JSON, maintain paragraph display/normalized text, image_stats, unified style/value_narrative/generation_constraints schemas, or validate article-analysis artifacts.
---

# SYSU WeChat Article Analysis

Use this skill to analyze one 中山大学公众号 Markdown article into the project-standard three artifacts:

- `clean_md/[id]title.clean.md`
- `article_analysis_md/[id]title.analysis.md`
- `article_json/[id]title.json`

Before writing outputs, read:

- `references/schema.md` for required JSON and analysis schema.
- `references/checklist.md` for validation commands and acceptance checks.

## Workflow

1. Use `md/[timestamp]title.md` as the primary input.
2. Use a same-name file under `中山大学/` only as a reference copy, not the primary source.
3. Create output directories if missing.
4. Produce clean Markdown first, then the analysis document, then JSON.
5. Keep the work scoped to the requested article unless the user explicitly asks for batch changes.

## clean_md Rules

Remove:

- Reader noise such as `在小说阅读器读本章`, `去阅读`.
- `javascript:void`, preview UI residue, mini-program prompts, comments, and interaction leftovers.
- Recommendation-reading blocks and their images.
- Empty shell content and repeated metadata labels.

Keep:

- Cover image, title, account, publish time, publish location.
- Body paragraphs, bold emphasis, image links, real captions, source and editor chain.
- Article-specific section headings and meaningful display rhythm.

Add anchors:

- `<!-- cover -->` before the cover image.
- `<!-- img001 -->`, `<!-- img002 -->` before images retained in clean output.
- `<!-- caption: ... -->` after images with real or structural captions.
- `<!-- p001 -->`, `<!-- p002 -->` before analyzed body paragraphs.

Do not count metadata, cover, source/editor chain, recommendation blocks, or preview residue as body paragraphs.

## Analysis Document Rules

Cover these sections:

1. 基础信息
2. 一句话主旨
3. 传播目的
4. 核心事实库
5. 文章结构
6. 段落功能表
7. 标题分析
8. 语言风格
9. 价值叙事
10. 图文编排
11. 可复用模板
12. 写作器调用建议

Facts table must include source paragraph, source quote, and confidence.

## JSON Rules

Use the stable fields in `references/schema.md`.

Critical requirements:

- Every `facts[]` item must include `source_paragraph_id`, `source_quote`, and `confidence`.
- Every `paragraph_functions[]` item must include `display_text` and `normalized_text`.
- Every template must include `applicable_scenarios` and `not_applicable_scenarios`.
- Strong assertions must appear in `generation_constraints.strong_claims_require_source` and/or `type_specific_constraints`.
- Do not invent facts, quotes, dates, awards, official statuses, image captions, or numbers.

## Commit and Notification

Follow repository `AGENTS.md`:

- Read the required git history before modifications.
- Commit only task-related files.
- Ignore unrelated untracked files unless the user asks otherwise.
- Send the completion notification after final verification.
