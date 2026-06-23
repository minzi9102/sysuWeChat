[CmdletBinding(DefaultParameterSetName = 'One')]
param(
  [Parameter(Mandatory = $true)]
  [string] $Root,

  [Parameter(Mandatory = $true, ParameterSetName = 'One')]
  [string] $ArticleBaseName,

  [Parameter(Mandatory = $true, ParameterSetName = 'All')]
  [switch] $All
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $Root).Path
$baseLabels = @('事实驱动','分章节叙事','校媒报道')
$requiredTop = @('article_id','title','publish_time','account','publish_location','article_types','keywords','summary','communication_goal','facts','structure','paragraph_functions','style','value_narrative','visuals','image_stats','templates','generation_constraints')
$requiredStyle = @('labels','tone','sentence_features','layout_features','common_phrases','rhetorical_devices','style_metrics','reusable_phrases','not_reusable_phrases')
$requiredValue = @('themes','levels','transition_method','school_image','ending_method')
$requiredConstraints = @('must_not_invent','strong_claims_require_source','quote_handling','scenario_boundaries','recommended_writer_use','type_specific_constraints')
$requiredEvidence = @('effective_paragraphs','effective_characters','body_image_nodes','unique_body_image_urls','pre_title_image_nodes','pre_title_unique_urls','post_title_image_nodes','matched_rule')
$script:failureCount = 0
$script:warningCount = 0

function Normalize-Text {
  param([string] $Text)
  if ($null -eq $Text) { return '' }
  return (($Text -replace '\*\*|_', '' -replace '\\---', '---' -replace '\s+', ' ').Trim())
}

function Add-Issue {
  param([Collections.Generic.List[string]] $Issues, [string] $Code, [string] $Detail = '')
  $Issues.Add($(if ($Detail) { "${Code}:$Detail" } else { $Code }))
}

function Test-ContinuousIds {
  param([int[]] $Values)
  if (-not $Values.Count) { return $true }
  $sorted = @($Values | Sort-Object)
  return ($sorted -join ',') -eq ((1..$sorted.Count) -join ',')
}

function Test-Marker {
  param([string] $Name)
  $issues = [Collections.Generic.List[string]]::new()
  $path = Join-Path $repo "article_markers\$Name.marker.json"
  try { $marker = [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { Add-Issue $issues 'json_parse'; $marker = $null }
  if ($marker) {
    if ($marker.content_mode -notin @('long_image','pasted_image')) { Add-Issue $issues 'content_mode' }
    if ($marker.processing_status -ne 'skipped') { Add-Issue $issues 'processing_status' }
    if ($marker.reason -ne 'image_dominant_article') { Add-Issue $issues 'reason' }
    foreach ($key in $requiredEvidence) { if ($key -notin $marker.evidence.PSObject.Properties.Name) { Add-Issue $issues 'evidence' $key } }
    foreach ($forbidden in @('facts','paragraph_functions','style','templates','generation_constraints')) { if ($forbidden -in $marker.PSObject.Properties.Name) { Add-Issue $issues 'marker_analysis_field' $forbidden } }
  }
  foreach ($other in @("clean_md\$Name.clean.md","article_analysis_md\$Name.analysis.md","article_json\$Name.json")) { if (Test-Path -LiteralPath (Join-Path $repo $other)) { Add-Issue $issues 'mode_conflict' $other } }
  Write-Result -Name $Name -Kind 'marker' -Issues $issues -Warnings @()
}

function Test-TextArtifacts {
  param([string] $Name)
  $issues = [Collections.Generic.List[string]]::new()
  $warnings = [Collections.Generic.List[string]]::new()
  $cleanPath = Join-Path $repo "clean_md\$Name.clean.md"
  $analysisPath = Join-Path $repo "article_analysis_md\$Name.analysis.md"
  $jsonPath = Join-Path $repo "article_json\$Name.json"
  foreach ($path in @($cleanPath,$analysisPath,$jsonPath)) { if (-not (Test-Path -LiteralPath $path)) { Add-Issue $issues 'missing_file' $path } }
  if ($issues.Count) { Write-Result -Name $Name -Kind 'text' -Issues $issues -Warnings $warnings; return }
  $clean = [IO.File]::ReadAllText($cleanPath)
  $analysis = [IO.File]::ReadAllText($analysisPath)
  try { $json = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json } catch { Add-Issue $issues 'json_parse'; Write-Result -Name $Name -Kind 'text' -Issues $issues -Warnings $warnings; return }
  if (Test-Path -LiteralPath (Join-Path $repo "article_markers\$Name.marker.json")) { Add-Issue $issues 'mode_conflict' 'marker_exists' }
  if ($clean -match '在小说阅读器读本章|去阅读|javascript:void|预览时标签不可点|微信扫一扫|iSYSU|(?m)^\s*(?:\*+\s*)?▼') { Add-Issue $issues 'clean_noise' }
  foreach ($key in $requiredTop) { if ($key -notin $json.PSObject.Properties.Name) { Add-Issue $issues 'top_level' $key } }
  foreach ($key in $requiredStyle) { if ($key -notin $json.style.PSObject.Properties.Name) { Add-Issue $issues 'style_key' $key } }
  foreach ($key in $requiredValue) { if ($key -notin $json.value_narrative.PSObject.Properties.Name) { Add-Issue $issues 'value_key' $key } }
  foreach ($key in $requiredConstraints) { if ($key -notin $json.generation_constraints.PSObject.Properties.Name) { Add-Issue $issues 'constraint_key' $key } }
  $paragraphs = @{}
  foreach ($paragraph in @($json.paragraph_functions)) {
    if (-not $paragraph.paragraph_id -or -not $paragraph.display_text -or -not $paragraph.normalized_text) { Add-Issue $issues 'paragraph_fields' $paragraph.paragraph_id; continue }
    $paragraphs[$paragraph.paragraph_id] = Normalize-Text $paragraph.normalized_text
    if ($clean -notmatch "<!--\s*$([regex]::Escape($paragraph.paragraph_id))\s*-->") { Add-Issue $issues 'paragraph_anchor' $paragraph.paragraph_id }
    if ($paragraph.normalized_text -match '左右滑动查看更多|iSYSU|(?m)^\s*▼' -or $paragraph.function_tags -contains '交互提示') { Add-Issue $issues 'paragraph_noise' $paragraph.paragraph_id }
  }
  foreach ($fact in @($json.facts)) {
    foreach ($key in @('source_paragraph_id','source_quote','confidence')) { if (-not $fact.$key) { Add-Issue $issues 'fact_field' "$($fact.id).$key" } }
    if ($fact.source_paragraph_id -and (-not $paragraphs.ContainsKey($fact.source_paragraph_id) -or -not $paragraphs[$fact.source_paragraph_id].Contains((Normalize-Text $fact.source_quote)))) { Add-Issue $issues 'fact_quote' $fact.id }
  }
  $paragraphIds = @([regex]::Matches($clean, '<!--\s*p(\d+)\s*-->') | ForEach-Object { [int]$_.Groups[1].Value })
  $imageIds = @([regex]::Matches($clean, '<!--\s*img(\d+)\s*-->') | ForEach-Object { [int]$_.Groups[1].Value })
  if (-not (Test-ContinuousIds $paragraphIds)) { Add-Issue $issues 'paragraph_sequence' }
  if (-not (Test-ContinuousIds $imageIds)) { Add-Issue $issues 'image_sequence' }
  foreach ($visual in @($json.visuals)) {
    if ($visual.caption_source -notin @('original','inferred','structural')) { Add-Issue $issues 'caption_source' $visual.image_id }
    if ($visual.image_id -eq 'cover') { if ($clean -notmatch '<!--\s*cover\s*-->') { Add-Issue $issues 'visual_anchor' 'cover' } }
    elseif ($clean -notmatch "<!--\s*$([regex]::Escape($visual.image_id))\s*-->") { Add-Issue $issues 'visual_anchor' $visual.image_id }
  }
  $urls = @([regex]::Matches($clean, '!\[[^\]]*\]\(([^)]+)\)') | ForEach-Object { $_.Groups[1].Value })
  if ($json.image_stats.total_image_nodes_in_clean -ne $urls.Count) { Add-Issue $issues 'image_count' }
  if ($json.image_stats.unique_image_urls -ne @($urls | Sort-Object -Unique).Count) { Add-Issue $issues 'unique_image_count' }
  foreach ($template in @($json.templates)) { foreach ($key in @('template','applicable_scenarios','not_applicable_scenarios')) { if ($key -notin $template.PSObject.Properties.Name) { Add-Issue $issues 'template_key' $key } } }
  $labels = @($json.style.labels)
  if ($labels.Count -notin 5..7 -or @($labels | Select-Object -Unique).Count -ne $labels.Count -or ($labels[0..2] -join '|') -ne ($baseLabels -join '|')) { Add-Issue $issues 'style_labels' }
  $analysisLabels = [regex]::Match($analysis, '(?m)^- 标签：(.*)$').Groups[1].Value
  if ($analysisLabels -ne ($labels -join '、')) { Add-Issue $issues 'analysis_labels' }
  if ([regex]::Matches($analysis, '(?m)^## (?:[1-9]|1[0-2])\. ').Count -ne 12) { Add-Issue $issues 'analysis_sections' }
  if (@($json.facts).Count -lt @($json.structure).Count) { $warnings.Add('section_coverage_review') }
  Write-Result -Name $Name -Kind 'text' -Issues $issues -Warnings $warnings
}

function Write-Result {
  param([string] $Name, [string] $Kind, [Collections.Generic.List[string]] $Issues, [object[]] $Warnings)
  if ($Issues.Count) {
    $script:failureCount++
    Write-Output "FAIL [$Kind] $Name :: $($Issues -join ', ')"
  } elseif (@($Warnings).Count) {
    $script:warningCount++
    Write-Output "WARN [$Kind] $Name :: $($Warnings -join ', ')"
  } else {
    Write-Output "PASS [$Kind] $Name"
  }
}

$textNames = @()
$markerNames = @()
if ($All) {
  $textNames = @(Get-ChildItem (Join-Path $repo 'article_json') -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
  $markerNames = @(Get-ChildItem (Join-Path $repo 'article_markers') -Filter '*.marker.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name -replace '\.marker\.json$','' })
} else {
  if (Test-Path -LiteralPath (Join-Path $repo "article_markers\$ArticleBaseName.marker.json")) { $markerNames = @($ArticleBaseName) } else { $textNames = @($ArticleBaseName) }
}
foreach ($name in $textNames | Sort-Object -Unique) { Test-TextArtifacts -Name $name }
foreach ($name in $markerNames | Sort-Object -Unique) { Test-Marker -Name $name }
Write-Output "SUMMARY failures=$script:failureCount warnings=$script:warningCount checked=$($textNames.Count + $markerNames.Count)"
if ($script:failureCount) { exit 1 }
