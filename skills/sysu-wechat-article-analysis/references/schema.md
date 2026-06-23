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

Use `source_image_id` only when a fact is supported by an image caption. Keep `source_paragraph_id` as the closest related body paragraph.

`confidence` values: `high`, `medium`, `low`.

`source_quote` may remove Markdown styling markers such as `**` and normalize excess whitespace. It must not change meaning, add missing details, or reorder source text in a way that weakens traceability.

## paragraph_functions[]

Each paragraph object must include:

- `paragraph_id`
- `display_text`
- `normalized_text`
- `summary`
- `function_tags`
- `writing_method`
- `reuse_value`

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
  "labels": [],
  "tone": "",
  "sentence_features": [],
  "layout_features": [],
  "common_phrases": [],
  "rhetorical_devices": [],
  "style_metrics": {},
  "reusable_phrases": [],
  "not_reusable_phrases": []
}
```

`style_metrics` should include operational indicators useful to a writer when supported by the article, such as:

- `headline_emotion_level`
- `fact_density`
- `quote_density`
- `value_sublimation_level`
- `average_paragraph_length`
- `bold_usage`
- `image_caption_dependency`

## value_narrative

Use this exact outer shape:

```json
{
  "themes": [],
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
