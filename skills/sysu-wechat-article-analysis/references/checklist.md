# Validation Checklist

Run checks after generating or updating artifacts.

## Noise Check

Clean Markdown must not contain:

- `在小说阅读器读本章`
- `去阅读`
- `推荐阅读`
- `javascript:void`
- `预览时标签不可点`
- `微信扫一扫`
- comment-area residue unrelated to article body

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

## Paragraph Dual Text

```powershell
$missing = @($j.paragraph_functions | Where-Object { -not $_.display_text -or -not $_.normalized_text })
$missing.Count
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

## Final Review

- `clean_md`, `analysis.md`, and JSON agree on paragraph IDs and image IDs.
- Strong claims appear in `generation_constraints`.
- Templates have applicable and not-applicable scenarios.
- Analysis document covers the 12 required sections.
- Only task-related files are staged.
