---
name: sysu-wechat-article-analysis
description: Analyze a single Sun Yat-sen University WeChat article from md/*.md into clean_md, article_analysis_md, and article_json outputs. Use when Codex needs to process 中山大学公众号推文, create clean Markdown with anchors, build fact-traceable analysis docs, generate writing-training JSON, maintain paragraph display/normalized text, image_stats, unified style/value_narrative/generation_constraints schemas, or validate article-analysis artifacts.
---

# SYSU WeChat Article Analysis

Use this skill to classify one 中山大学公众号 Markdown article before analysis. Text articles produce the project-standard three artifacts:

- `clean_md/[id]title.clean.md`
- `article_analysis_md/[id]title.analysis.md`
- `article_json/[id]title.json`

Image-dominant articles produce only:

- `article_markers/[id]title.marker.json`

Do not generate clean Markdown, analysis Markdown, or article JSON for `long_image` or `pasted_image` articles.

Before writing outputs, read:

- `references/schema.md` for required JSON and analysis schema.
- `references/checklist.md` for validation commands and acceptance checks.

## Workflow

1. Use `md/[timestamp]title.md` as the primary input.
2. Use a same-name file under `中山大学/` only as a reference copy, not the primary source.
3. Classify the article as `pasted_image`, `long_image`, or `text` before generating outputs.
4. For `pasted_image` or `long_image`, write only the marker file and stop.
5. For `text`, produce clean Markdown first, then the analysis document, then JSON.
6. Keep the work scoped to the requested article unless the user explicitly asks for batch changes.

## Content Mode Classification

Measure only article-body content:

- Stop at the earliest recommendation-reading block, `iSYSU`, or selected-comment section.
- Exclude explicit `cover_image` nodes, author/comment avatars, mini-program prompts, and platform residue.
- Exclude metadata, source/editor chains, recommendation titles, and interaction prompts from effective paragraphs and characters.

Classify in this order:

1. `pasted_image`: at least 2 pre-title body image nodes, at least 2 unique pre-title image URLs, and no post-title body images.
2. `long_image`: not `pasted_image`, and either:
   - fewer than 6 effective paragraphs and more than 20 body image nodes; or
   - fewer than 80 effective characters and at least 5 unique body image URLs.
3. `text`: all remaining articles.

Classification is mutually exclusive. `pasted_image` takes precedence over `long_image`.

For image-dominant articles, set `processing_status` to `skipped` and do not infer image text, facts, captions, or writing templates.

## clean_md Rules

Remove:

- Reader noise such as `在小说阅读器读本章`, `去阅读`.
- `javascript:void`, preview UI residue, mini-program prompts, comments, and interaction leftovers.
- Recommendation-reading blocks and their images.
- Empty shell content and repeated metadata labels.

Keep:

- Cover image, title, account, publish time, publish location.
- Body paragraphs, bold emphasis, image links, and real captions.
- Article-specific section headings and meaningful display rhythm.

Add anchors:

- `<!-- cover -->` before the cover image.
- `<!-- img001 -->`, `<!-- img002 -->` before images retained in clean output.
- `<!-- caption: ... -->` after images with real or structural captions.
- `<!-- p001 -->`, `<!-- p002 -->` before analyzed body paragraphs.
- `<!-- structural_note: ... -->` for retained interaction or layout notes such as `左右滑动查看更多`.

Do not count metadata, cover, source/editor chain, recommendation blocks, preview residue, or interaction prompts as body paragraphs. Interaction prompts must not appear in `paragraph_functions[]`; keep them in `structural_notes[]`.

Treat the first recommendation-reading marker (for example `推荐阅读` or a recommendation list introduced by `▼`) as a hard cutoff. Remove the marker and everything after it, including recommendation links and images, `iSYSU`, source/editor chains, QR codes, platform footers, and comments. Preserve title, account, publish time, publish location, and all article body content before the cutoff.

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

Facts are coverage-driven rather than count-driven. Identify the article's substantive sections first, then include at least one traceable fact for every section and additional facts for important people, dates, figures, results, and conclusions. Do not impose a fixed global fact limit or collapse a long article into a small generic list.

`source_quote` may remove Markdown styling markers such as `**` and normalize excess whitespace, but it must not change the meaning, invent missing details, or reorder text in a way that weakens traceability. If the quote is supported by an image caption, preserve the caption's original meaning and pair it with `source_image_id`.

## JSON Rules

Use the stable fields in `references/schema.md`.

Critical requirements:

- Every `facts[]` item must include `source_paragraph_id`, `source_quote`, and `confidence`.
- Every `paragraph_functions[]` item must include `display_text` and `normalized_text`.
- Do not place interaction prompts such as `左右滑动查看更多` in `paragraph_functions[]`; use top-level `structural_notes[]`.
- Every `visuals[]` item must include `caption_source`: `original`, `inferred`, or `structural`.
- Every template must include `applicable_scenarios` and `not_applicable_scenarios`.
- Strong assertions must appear in `generation_constraints.strong_claims_require_source` and/or `type_specific_constraints`.
- Do not invent facts, quotes, dates, awards, official statuses, image captions, or numbers.

## Commit and Notification

Follow repository `AGENTS.md`:

- Read the required git history before modifications.
- Commit only task-related files.
- Ignore unrelated untracked files unless the user asks otherwise.
- Send the completion notification after final verification.
