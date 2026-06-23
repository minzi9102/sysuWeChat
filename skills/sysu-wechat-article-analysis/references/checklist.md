# Validation Checklist

Run checks after generating or updating artifacts.

## Content Mode Gate

Classify before analysis. For `long_image` and `pasted_image`:

- A marker must exist under `article_markers/`.
- No matching clean Markdown, analysis Markdown, or article JSON may exist.
- `content_mode` must be `long_image` or `pasted_image`.
- `processing_status` must be `skipped`.
- `reason` must be `image_dominant_article`.
- Every evidence field defined in `schema.md` must be present.

Example marker validation:

```powershell
$m = Get-Content -LiteralPath 'article_markers\[id]title.marker.json' -Raw | ConvertFrom-Json
$requiredEvidence = @(
  'effective_paragraphs','effective_characters','body_image_nodes',
  'unique_body_image_urls','pre_title_image_nodes','pre_title_unique_urls',
  'post_title_image_nodes','matched_rule'
)
@($requiredEvidence | Where-Object { $_ -notin $m.evidence.PSObject.Properties.Name }).Count
$m.content_mode -in @('long_image','pasted_image')
$m.processing_status -eq 'skipped'
$m.reason -eq 'image_dominant_article'
```

Expected: `0`, `True`, `True`, `True`.

For `text`, no marker should exist; continue with the checks below.

## Noise Check

Clean Markdown must not contain:

- `在小说阅读器读本章`
- `去阅读`
- `推荐阅读`
- `javascript:void`
- `预览时标签不可点`
- `微信扫一扫`
- comment-area residue unrelated to article body
- `iSYSU`, source/editor chains, QR codes, or any content following the first recommendation-reading marker

When the source contains a recommendation-reading marker, verify that clean Markdown ends before that marker and retains all substantive body sections before it.

## JSON Parse

```powershell
Get-Content -LiteralPath 'article_json\[id]title.json' -Raw | ConvertFrom-Json | Out-Null
```

## Fact Provenance

All facts must have:

```powershell
$j = Get-Content -LiteralPath 'article_json\[id]title.json' -Raw | ConvertFrom-Json
@($j.facts | Where-Object { -not $_.source_paragraph_id -or -not $_.source_quote -or -not $_.confidence }).Count
```

Expected: `0`.

## Section Coverage

- Identify the substantive body sections from headings and topic transitions.
- Every substantive section must be represented by at least one `facts[]` item.
- Important people, dates, figures, awards, research results, and conclusions should be separate facts when combining them would weaken traceability.
- There is no fixed maximum fact count; long articles must not be compressed into an arbitrary 6-10 facts.

## Paragraph Dual Text

```powershell
$missing = @($j.paragraph_functions | Where-Object { -not $_.display_text -or -not $_.normalized_text })
$missing.Count
```

Expected: `0`.

Interaction prompts must not be paragraph functions:

```powershell
@($j.paragraph_functions | Where-Object {
  $_.display_text -match '左右滑动查看更多' -or $_.normalized_text -match '左右滑动查看更多' -or $_.function_tags -contains '交互提示'
}).Count
```

Expected: `0`.

## Anchor Backlinks

```powershell
$clean = Get-Content -LiteralPath 'clean_md\[id]title.clean.md' -Raw
$missingP = @($j.paragraph_functions.paragraph_id | Where-Object {
  $clean -notmatch "<!--\s*$([regex]::Escape($_))\s*-->"
})
$missingV = @($j.visuals.image_id | Where-Object {
  if ($_ -eq 'cover') { $clean -notmatch '<!--\s*cover\s*-->' }
  else { $clean -notmatch "<!--\s*$([regex]::Escape($_))\s*-->" }
})
"missing_paragraphs=$($missingP.Count) missing_visuals=$($missingV.Count)"
```

Expected: both `0`.

## image_stats

```powershell
$urls = @([regex]::Matches($clean,'!\[[^\]]*\]\(([^)]+)\)') | ForEach-Object { $_.Groups[1].Value })
$j.image_stats.total_image_nodes_in_clean -eq $urls.Count
$j.image_stats.unique_image_urls -eq @($urls | Sort-Object -Unique).Count
```

Expected: both `True`.

## structural_notes

When present, every structural note must include required fields:

```powershell
@($j.structural_notes | Where-Object { -not $_.text -or -not $_.note_type -or -not $_.position }).Count
```

Expected: `0`.

All visual items must include a valid `caption_source`:

```powershell
@($j.visuals | Where-Object { $_.caption_source -notin @('original','inferred','structural') }).Count
```

Expected: `0`.

All fact paragraph references must resolve to clean Markdown anchors:

```powershell
@($j.facts.source_paragraph_id | Where-Object {
  $_ -and $clean -notmatch "<!--\s*$([regex]::Escape($_))\s*-->"
}).Count
```

Expected: `0`.

## Unified Schema

Required style keys:

```powershell
'labels','tone','sentence_features','layout_features','common_phrases','rhetorical_devices','style_metrics','reusable_phrases','not_reusable_phrases'
```

Required value narrative keys:

```powershell
'themes','levels','transition_method','school_image','ending_method'
```

Required generation constraint keys:

```powershell
'must_not_invent','strong_claims_require_source','quote_handling','scenario_boundaries','recommended_writer_use','type_specific_constraints'
```

## Style Label Discrimination

```powershell
$base = @('事实驱动','分章节叙事','校媒报道')
$j.style.labels.Count -in 5..7
@($j.style.labels | Select-Object -Unique).Count -eq $j.style.labels.Count
@($j.style.labels[0..2]) -join '|' -eq $base -join '|'
@($j.style.labels | Where-Object { $_ -notin $base }).Count -in 2..4
```

Expected: all `True`.

- JSON and analysis Markdown must list the same labels in the same order.
- Prefer canonical labels and reject unregistered synonyms when a canonical equivalent exists.
- Discriminative labels must describe writing mode, emotional posture, or narrative mechanism rather than mechanically repeat `article_types`.

## Final Review

- `clean_md`, `analysis.md`, and JSON agree on paragraph IDs and image IDs.
- Strong claims appear in `generation_constraints`.
- Templates have applicable and not-applicable scenarios.
- Analysis document covers the 12 required sections.
- Only task-related files are staged.
