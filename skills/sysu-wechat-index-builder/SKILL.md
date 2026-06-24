---
name: sysu-wechat-index-builder
description: Build, rebuild, update, and validate searchable JSONL indexes for the Sun Yat-sen University WeChat knowledge base. Use for 中山大学公众号知识库 when Codex must quality-gate article_json, clean_md, and article_analysis_md triplets; generate article, paragraph, fact, template, style, visual, and constraint indexes; inspect quality reports and manifests; or verify index counts, provenance, image links, and deterministic output. Do not use to analyze source articles or index image-dominant markers.
---

# SYSU WeChat Index Builder

Build deterministic retrieval indexes from validated text-article artifacts. Treat `article_json` as structured input and use same-name `clean_md` and `article_analysis_md` files for completeness and provenance checks.

## 1. Preflight

Read the repository `AGENTS.md` and follow its Git, Python, commit, and notification rules.

Require these input directories under the repository root:

- `article_json/`
- `clean_md/`
- `article_analysis_md/`

Ignore `article_markers/`. This skill indexes only complete text-article triplets.

Before rebuilding indexes, validate all source artifacts:

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 -Root . -All
```

Stop and repair source artifacts if validation reports `FAIL`. Do not weaken index validation to admit invalid inputs.

## 2. Build

Run the canonical builder:

```powershell
./skills/sysu-wechat-index-builder/scripts/build-indexes.ps1 -Root .
```

The top-level compatibility entry invokes the same implementation:

```powershell
./scripts/build-indexes.ps1 -Root .
```

The builder quality-gates every triplet, indexes only `ready_for_indexing = true` articles, and writes UTF-8 JSONL with stable record ordering.

## 3. Outputs

Expect these files under `indexed_data/`:

- `quality_report.jsonl`
- `article_index.jsonl`
- `paragraph_index.jsonl`
- `fact_index.jsonl`
- `template_index.jsonl`
- `style_index.jsonl`
- `visual_index.jsonl`
- `constraint_index.jsonl`
- `index_manifest.json`

Do not hand-edit generated index files. Change source artifacts or the canonical builder, then regenerate.

## 4. Validate

Require the builder to print `INDEX BUILD PASS`. Inspect `index_manifest.json` and require its counts to equal the actual JSONL line counts.

Inspect `quality_report.jsonl` before completion:

- `pass`: indexed normally.
- `review`: excluded until schema or noise issues are resolved.
- `exclude`: excluded because JSON parsing or triplet completeness failed.

For a normal full rebuild of the current corpus, require `review_article_count = 0` and `excluded_article_count = 0`. If either is nonzero, report the affected articles and reasons rather than silently accepting reduced coverage.

When changing builder logic, also verify:

- every JSONL line parses independently;
- all compound record IDs are unique;
- every child `article_id` exists in `article_index.jsonl`;
- every fact references an indexed paragraph;
- every visual has an image URL;
- strong claims are marked `requires_verification`;
- two consecutive builds match byte-for-byte except `index_manifest.json.generated_at`.

## 5. Complete

Report index counts and any reviewed or excluded articles. If tracked files changed, use `$git-md-micro-commit` with task-only staging. Never include unrelated worktree files.
