---
name: sysu-wechat-article-analysis
description: Classify, analyze, repair, and validate Sun Yat-sen University WeChat Markdown articles. Use for 中山大学公众号推文 when Codex must distinguish text, long-image, or pasted-image content; generate clean Markdown, traceable analysis Markdown, structured writing-training JSON, or marker JSON; repair unreliable existing artifacts; enforce recommendation cutoffs, fact provenance, image statistics, style labels, and batch consistency.
---

# SYSU WeChat Article Analysis

Process `md/[timestamp]title.md` through seven stages: classify, clean, model structure, extract facts, model reusable writing, label style, validate.

Read these references before editing artifacts:

- `references/schema.md`: output interfaces and invariants.
- `references/style-labels.md`: semi-controlled style vocabulary.
- `references/checklist.md`: deterministic and manual acceptance checks.

Use the source under `md/` as primary evidence. A same-name file under `中山大学/` is reference-only.

## 1. Classify

Run:

```powershell
./skills/sysu-wechat-article-analysis/scripts/classify-article.ps1 -SourcePath 'md/[id]title.md'
```

The script is read-only and emits `content_mode`, the body boundary, and marker-compatible evidence.

Classification order is exclusive:

1. `pasted_image`
2. `long_image`
3. `text`

For `pasted_image` or `long_image`, create only `article_markers/[id]title.marker.json`, set `processing_status` to `skipped`, and stop. Do not infer text, facts, captions, or templates from images.

For `text`, ensure no marker exists and continue.

## 2. Clean

Create `clean_md/[id]title.clean.md`.

Use the classifier's line-level boundary. A title containing an ordinary word such as `推荐` is not a cutoff. Cut at the earliest explicit recommendation heading, recommendation item beginning with `▼`, `iSYSU` footer, or selected-comment heading. Remove the matched line and everything after it.

Remove reader UI, `javascript:void`, preview residue, comments, mini-program prompts, empty shells, duplicated metadata, source/editor chains, QR codes, and footer content.

Keep cover, title, account, publish time/location, complete body text, meaningful headings, body images, emphasis, and real captions.

Add continuous anchors:

- `<!-- cover -->`
- `<!-- img001 -->`, `<!-- img002 -->`, ...
- `<!-- p001 -->`, `<!-- p002 -->`, ...
- `<!-- caption: ... -->` for real or structural captions
- `<!-- structural_note: ... -->` for retained layout notes

Do not assign paragraph anchors to metadata, captions, interaction prompts, or layout-only notes.

## 3. Model Structure

Identify substantive sections from headings and topic transitions before writing facts. Record article-specific structure rather than a generic opening/expansion/support/ending template.

Choose `article_types` from subject and function. Keep them separate from writing style.

Semantic judgments belong here, not in index construction. Determine paragraph functions, value themes, topic entities, reusable expressions, and template types from the source article before writing JSON. Index construction may normalize fields for retrieval, but must not invent or repair missing semantic analysis.

Keep `paragraph_functions[].function_tags` as a deduplicated array of complementary labels selected from the controlled vocabulary in `references/schema.md`. Multiple labels are allowed when they describe distinct functions. Use `核心事实` only for a paragraph that carries a principal news fact; never apply it mechanically as a fallback.

Separate abstract `value_themes` from concrete `topic_entities`. People, organizations, projects, platforms, instruments, places, and named programs are entities, not values.

For existing artifacts:

- Fully rebuild when article type, structure, paragraph segmentation, or fact coverage is broadly unreliable.
- Repair only affected fields when clean body, structure, and facts are otherwise trustworthy.
- Never preserve recommendation-derived content merely to keep old IDs stable; renumber retained anchors and IDs continuously.

## 4. Extract Facts

Cover every substantive section with at least one fact. Add separate facts for important people, dates, figures, conditions, awards, research results, and conclusions. Do not impose a global fact limit.

Every fact must include `source_paragraph_id`, string-valued `source_quote`, `confidence`, `requires_verification`, and `risk_level`. The quote must occur inside the referenced paragraph after removing Markdown emphasis and normalizing whitespace. Whole-article occurrence is insufficient.

`source_quote` may remove Markdown styling and excess whitespace. It must not paraphrase, combine distant sentences, invent missing details, or weaken traceability. Use `source_image_id` only for facts supported by an original image caption.

Strong assertions such as first/largest/highest, awards, official titles, exact dates, codes, counts, and percentages require direct evidence and generation constraints. Assertions containing terms such as `首例`, `全球首例`, `全国首个`, `首次`, `首批`, `最大`, `最高`, or `典型案例`, and equivalent comparative or authoritative claims, must set `requires_verification` to `true` and `risk_level` to `high`.

## 5. Model Reusable Writing

Generate a `templates` object with all seven arrays defined in `references/schema.md`. Every article must provide at least one title, opening, structure, transition, and ending template. Generate visual-caption and notice-flow templates only when supported by the source; otherwise use empty arrays.

Generalize patterns without copying article-specific names, figures, claims, or quotations. Each template must state applicable and non-applicable scenarios.

## 6. Label Style

Set `style.style_labels` to the three base labels followed by 2-4 discriminative labels:

1. `事实驱动`
2. `分章节叙事`
3. `校媒报道`

Select canonical fine labels from `references/style-labels.md`. Add a new label only when no existing term captures the writing mode, emotional posture, or narrative mechanism. Do not mechanically copy `article_types` or create synonyms.

Keep JSON and analysis Markdown labels identical and ordered. Put only source-grounded reusable wording in `reusable_phrases`; route rhetorical names to `rhetorical_devices`, writing techniques to `writing_methods`, style categories to `style_labels`, and entity-specific or fact-bound wording to `not_reusable_phrases`.

## 7. Validate

Validate one article:

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 -Root . -ArticleBaseName '[id]title'
```

Validate every existing text artifact and marker:

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 -Root . -All
```

The validator is read-only. It currently checks the legacy article schema only. Use it for existing artifacts, but do not treat it as validation of the new templates, style, theme/entity, paragraph-label, or fact-risk rules. Until the validator and index builder are upgraded, validate newly analyzed articles manually against `references/schema.md` and `references/checklist.md`, and do not rebuild the full index from new-schema artifacts.

Then perform the semantic checks in `references/checklist.md`, especially section coverage, article type accuracy, strong assertions, inferred captions, and admissions or policy conditions.

## Outputs

Text articles:

- `clean_md/[id]title.clean.md`
- `article_analysis_md/[id]title.analysis.md`
- `article_json/[id]title.json`

Image-dominant articles:

- `article_markers/[id]title.marker.json`

Follow repository `AGENTS.md`: read required Git history before edits, commit only task files, and send the completion notification after verification.
