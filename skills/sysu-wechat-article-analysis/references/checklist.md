# Validation Checklist

Run deterministic validation first, then complete the semantic review.

## Deterministic Validation

One article:

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 -Root . -ArticleBaseName '[id]title'
```

All existing artifacts:

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 -Root . -All
```

For legacy artifacts, the command must return exit code `0`. Fix every `FAIL`; inspect every `WARN`.

The current script validates the legacy schema. It does not enforce the new templates object, style fields, top-level theme/entity split, controlled paragraph labels, or fact verification fields. For new-schema articles, complete the manual checks below and do not rebuild the full index until the validator and index builder are upgraded.

The validator checks:

- marker and text-output exclusivity
- marker schema and forbidden analysis fields
- clean Markdown noise and footer residue
- JSON parsing and required top-level/schema keys
- fact provenance fields and paragraph-local quote containment
- paragraph and visual backlinks
- continuous paragraph and image anchors
- `caption_source` values
- `image_stats` counts
- template entry shape
- style label count, order, uniqueness, and analysis consistency
- all 12 analysis sections

## Content Mode Review

- Run `classify-article.ps1` before generating outputs.
- Confirm explicit `cover_image` nodes are excluded from image-dominance counts.
- Confirm ordinary title text containing `推荐` does not trigger the body cutoff.
- For `long_image` and `pasted_image`, create only the marker and do not infer image content.

## Clean Body Review

- Preserve title/account/time/location and every substantive body section before the boundary.
- Remove the boundary line and everything after it.
- Keep interaction or layout notes out of paragraph functions.
- Confirm captions are either source text or clearly marked inferred/structural descriptions.

## Structure And Fact Coverage

- Structure must reflect article-specific sections, not a generic four-part shell.
- Every substantive section needs at least one fact.
- Separate important people, dates, figures, conditions, awards, research results, and conclusions when combining them weakens traceability.
- Do not use a fixed fact limit.
- Verify each `source_quote` against its specified paragraph, not merely the full article.
- Keep `source_quote` string-valued; do not split it into raw and normalized fields.
- Confirm every fact has boolean `requires_verification` and a `high`, `medium`, or `low` `risk_level`.
- Confirm first/largest/highest, awards, rankings, official titles, typical-case designations, and equivalent strong claims use `requires_verification: true` and `risk_level: high`.

## Templates And Semantic Fields

- Confirm `templates` defines all seven required arrays.
- Require at least one title, opening, structure, transition, and ending template.
- Keep unsupported visual-caption and notice-flow template arrays empty; do not invent patterns.
- Confirm every template has content plus applicable and non-applicable scenarios.
- Confirm `value_themes` contains only abstract values and `topic_entities` contains only concrete named entities, with no overlap.
- Confirm every paragraph tag belongs to the controlled vocabulary, is deduplicated, and describes an actual function.
- Reject systematic use of `核心事实` as a fallback.

## Type And Style Review

- `article_types` describe subject and function.
- `style.style_labels` describe writing mode, emotional posture, and narrative mechanism.
- Use the canonical vocabulary in `style-labels.md`; reject avoidable synonyms.
- JSON and analysis Markdown must list identical labels in identical order.
- Keep reusable wording, rhetorical devices, writing methods, style labels, and non-reusable wording in their respective fields.
- Reject entities, rhetorical names, method labels, generic descriptions, and fact-bound passages from `reusable_phrases`.

## High-Risk Review

Manually verify:

- first/largest/highest and national-level claims
- awards, official titles, rankings, and institutional names
- exact dates, codes, counts, percentages, and distances
- admissions eligibility, registration windows, fees, examination, and admission rules
- political, conference, international, medical, and research terminology
- direct quotations and named speakers

Strong claims must appear in `generation_constraints.strong_claims_require_source` or `type_specific_constraints`.

## Final Repository Check

- `git diff --check` passes.
- Only task-related files are staged.
- Unrelated untracked files remain untouched.
