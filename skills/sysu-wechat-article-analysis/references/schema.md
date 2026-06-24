# Schema Reference

## Outputs

For a `text` input, generate:

- `clean_md/[timestamp]title.clean.md`
- `article_analysis_md/[timestamp]title.analysis.md`
- `article_json/[timestamp]title.json`

For a `long_image` or `pasted_image` input, generate only:

- `article_markers/[timestamp]title.marker.json`

The marker and the three analysis artifacts are mutually exclusive.

## Image-Dominant Marker

Use this exact outer shape:

```json
{
  "article_id": "",
  "title": "",
  "source_file": "md/[timestamp]title.md",
  "content_mode": "long_image",
  "processing_status": "skipped",
  "reason": "image_dominant_article",
  "evidence": {
    "effective_paragraphs": 0,
    "effective_characters": 0,
    "body_image_nodes": 0,
    "unique_body_image_urls": 0,
    "pre_title_image_nodes": 0,
    "pre_title_unique_urls": 0,
    "post_title_image_nodes": 0,
    "matched_rule": ""
  }
}
```

Allowed `content_mode` values: `long_image`, `pasted_image`.

`processing_status` must be `skipped`, and `reason` must be `image_dominant_article`. Marker files must not contain analysis fields such as `facts`, `paragraph_functions`, `style`, `templates`, or `generation_constraints`.

## JSON Top-Level Fields

Required fields:

- `article_id`
- `title`
- `publish_time`
- `account`
- `publish_location`
- `article_types`
- `keywords`
- `summary`
- `communication_goal`
- `value_themes`
- `topic_entities`
- `facts`
- `structure`
- `paragraph_functions`
- `style`
- `value_narrative`
- `visuals`
- `image_stats`
- `templates`
- `generation_constraints`

## facts[]

Each fact object must include:

- `id`
- `fact`
- `type`
- `time`
- `subject`
- `object`
- `importance`
- `can_reuse`
- `risk`
- `source_paragraph_id`
- `source_quote`
- `confidence`
- `requires_verification`
- `risk_level`

Use `source_image_id` only when a fact is supported by an image caption. Keep `source_paragraph_id` as the closest related body paragraph.

`confidence` values: `high`, `medium`, `low`.

`requires_verification` is a JSON boolean. `risk_level` values are `high`, `medium`, `low`.

Set `requires_verification` to `true` and `risk_level` to `high` for comparative or authoritative claims, including `首例`, `全球首例`, `全国首个`, `首次`, `首批`, `最大`, `最高`, `典型案例`, awards, rankings, official titles, and equivalent claims. Exact dates, codes, counts, percentages, and policy conditions must also be reviewed and assigned a risk level based on the consequence of error.

`source_quote` may remove Markdown styling markers such as `**` and normalize excess whitespace. It must not change meaning, add missing details, or reorder source text in a way that weakens traceability.

Keep `source_quote` as a string. Do not split it into raw and normalized fields in this schema revision.

## paragraph_functions[]

Each paragraph object must include:

- `paragraph_id`
- `display_text`
- `normalized_text`
- `summary`
- `function_tags`
- `writing_method`
- `reuse_value`

`function_tags` remains an array and has no fixed item limit. Values must be unique, complementary, and selected from this controlled vocabulary:

- `章节标题`
- `背景交代`
- `核心事实`
- `人物经历`
- `人物引语`
- `成果支撑`
- `数据支撑`
- `案例展开`
- `机制说明`
- `价值转场`
- `群像呈现`
- `规则说明`
- `政策解读`
- `流程指引`
- `风险提醒`
- `媒体转载说明`
- `活动召唤`
- `未来展望`
- `行动号召`
- `结尾收束`

Use every tag only when the paragraph visibly performs that function. `核心事实` is reserved for principal news facts and must not be used as a generic fallback. Do not create synonyms or article-specific tags.

`display_text` preserves original WeChat layout rhythm: short lines, blank lines, bold markers, section headings, and quote placement.

`normalized_text` preserves clean semantic text: merged short lines, corrected spacing, stable punctuation, and no reader noise.

Interaction prompts and layout hints such as `左右滑动查看更多` are not body paragraphs. Keep them out of `paragraph_functions[]` and record them in `structural_notes[]`.

## structural_notes[]

Optional but required when retained clean Markdown contains interaction or layout notes that are not body paragraphs.

Each structural note should include:

- `id`
- `note_type`
- `text`
- `position`
- `related_image_ids`
- `source_quote`

Use `structural_notes[]` for carousel prompts, swipe hints, layout-only labels, or other retained structural information that should not train paragraph writing.

## style

Use this exact outer shape:

```json
{
  "reusable_phrases": [],
  "rhetorical_devices": [],
  "writing_methods": [],
  "style_labels": [],
  "not_reusable_phrases": []
}
```

Field boundaries:

- `reusable_phrases`: source-grounded wording that can be adapted without carrying article-specific facts.
- `rhetorical_devices`: names of rhetorical devices, such as parallelism or rhetorical questions.
- `writing_methods`: writing or organization methods, such as data-first explanation or scene-to-value transition.
- `style_labels`: retrieval labels describing writing mode and narrative mechanism.
- `not_reusable_phrases`: proper nouns, fact-bound claims, full source passages, and wording unsafe to reuse directly.

Do not place entity words such as `中大`, method descriptions such as `图文证明`, rhetorical names such as `排比`, or generic statements such as `长短句结合` in `reusable_phrases`.

`style_labels` must contain 5-7 unique values in this order:

1. Base labels: `事实驱动`, `分章节叙事`, `校媒报道`.
2. Two to four discriminative labels selected from `style-labels.md`.

Additional labels are allowed under the extension rules in `style-labels.md`. Labels describe style or narrative mechanism rather than duplicate `article_types` verbatim.

## value_themes and topic_entities

Use top-level arrays:

```json
{
  "value_themes": ["服务国家战略", "百年传承", "学科建设", "科研报国"],
  "topic_entities": ["中山大学天文台", "1.2米天文望远镜", "天琴计划"]
}
```

`value_themes` contains abstract values, missions, or public meanings. `topic_entities` contains named people, organizations, projects, platforms, instruments, places, programs, and other concrete subjects. Never duplicate an item across the two arrays.

## value_narrative

Use this exact outer shape:

```json
{
  "levels": {
    "personal_level": "",
    "team_level": "",
    "course_level": "",
    "school_level": "",
    "national_level": ""
  },
  "transition_method": "",
  "school_image": [],
  "ending_method": ""
}
```

Extra level keys are allowed inside `levels` when needed, such as `family_level`, `teacher_level`, `student_level`, or `aesthetic_level`.

## visuals[] and image_stats

Each visual item should include:

- `image_id`
- `caption`
- `caption_source`
- `type`
- `function`
- `position`

`caption_source` values:

- `original`: caption text appears in the source article.
- `inferred`: caption is supplied by analysis to describe an uncaptained image.
- `structural`: caption describes a decorative, divider, opening, closing, or interaction-only visual.

Use this exact `image_stats` shape:

```json
{
  "cover_images": 0,
  "content_images": 0,
  "decorative_images": 0,
  "recommendation_images": 0,
  "footer_images": 0,
  "total_image_nodes_in_clean": 0,
  "unique_image_urls": 0
}
```

Counting rules:

- `total_image_nodes_in_clean`: count Markdown image nodes in clean_md.
- `unique_image_urls`: count unique image URLs in clean_md.
- `cover_images`: count `cover`.
- `decorative_images`: count opening gifs, dynamic visuals, dividers, section visuals, decorative theme images, and closing visuals.
- `content_images`: count retained visuals that are not cover or decorative.
- `recommendation_images` and `footer_images`: normally `0` because clean_md removes recommendations and footer residue.

## templates

Use this exact outer shape:

```json
{
  "title_templates": [],
  "opening_templates": [],
  "structure_templates": [],
  "transition_templates": [],
  "ending_templates": [],
  "visual_caption_templates": [],
  "notice_flow_templates": []
}
```

`title_templates`, `opening_templates`, `structure_templates`, `transition_templates`, and `ending_templates` must each contain at least one entry. `visual_caption_templates` is populated only when source visuals or captions support a reusable pattern. `notice_flow_templates` is populated only for notices, calls for participation, registration instructions, policy explanations, and similar procedural articles. Unsupported optional types must be empty arrays rather than invented content.

Template entries must include:

- `template`
- `applicable_scenarios`
- `not_applicable_scenarios`

Templates should generalize across articles. Avoid single-article-only wording unless the scenarios make the limitation explicit.

## generation_constraints

Use this exact outer shape:

```json
{
  "must_not_invent": [],
  "strong_claims_require_source": [],
  "quote_handling": [],
  "scenario_boundaries": [],
  "recommended_writer_use": [],
  "type_specific_constraints": []
}
```

Use `type_specific_constraints[]` for original or article-specific constraints:

```json
{
  "term": "",
  "constraint": "",
  "category": "strong_claim"
}
```

Allowed `category` values:

- `strong_claim`
- `quote_handling`
- `scenario_boundary`
- `must_not_invent`

Strong claims include national rankings, first/largest/highest claims, awards, official titles, warning levels, response levels, exact dates, and exact numbers.
