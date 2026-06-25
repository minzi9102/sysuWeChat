[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Root,

  [Parameter(Mandatory = $true)]
  [AllowEmptyString()]
  [string[]] $ArticleTypes,

  [Parameter(Mandatory = $true)]
  [AllowEmptyString()]
  [string[]] $Keywords,

  [Parameter(Mandatory = $true)]
  [string] $Output
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function ConvertTo-QueryValues {
  param(
    [string[]] $Values,
    [string] $Name
  )

  $result = [Collections.Generic.List[string]]::new()
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($value in @($Values)) {
    foreach ($part in @($value -split '[,\uFF0C]')) {
      $normalized = $part.Trim()
      if ($normalized -and $seen.Add($normalized)) {
        $result.Add($normalized)
      }
    }
  }

  if ($result.Count -eq 0) {
    throw "Parameter -$Name cannot be empty."
  }
  return $result.ToArray()
}

function Read-JsonLines {
  param([string] $Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required index file is missing: $Path"
  }

  $records = [Collections.Generic.List[object]]::new()
  $lineNumber = 0
  foreach ($line in [IO.File]::ReadLines($Path, [Text.Encoding]::UTF8)) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
      $records.Add(($line | ConvertFrom-Json))
    }
    catch {
      throw "Invalid JSONL in index file $Path at line $lineNumber. $($_.Exception.Message)"
    }
  }
  return $records.ToArray()
}

function Get-ExactMatches {
  param(
    [object[]] $Values,
    [string[]] $Queries
  )

  $matches = [Collections.Generic.List[string]]::new()
  foreach ($query in $Queries) {
    foreach ($value in @($Values)) {
      if ([string]::Equals([string]$value, $query, [StringComparison]::OrdinalIgnoreCase)) {
        $matches.Add($query)
        break
      }
    }
  }
  return $matches.ToArray()
}

function Get-KeywordMatches {
  param(
    [object] $Record,
    [string[]] $Queries
  )

  $parts = @(
    $Record.title
    $Record.keywords
    $Record.summary
    $Record.communication_goal
    $Record.structure_summary
    $Record.style_labels
    $Record.value_themes
    $Record.topic_entities
  ) | ForEach-Object { @($_) } | ForEach-Object { [string]$_ }
  $haystack = $parts -join "`n"
  $matches = [Collections.Generic.List[string]]::new()
  foreach ($query in $Queries) {
    if ($haystack.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $matches.Add($query)
    }
  }
  return $matches.ToArray()
}

function Test-AnyOverlap {
  param(
    [object[]] $Values,
    [string[]] $Queries
  )
  return @(Get-ExactMatches $Values $Queries).Count -gt 0
}

function Select-UniqueRecords {
  param(
    [object[]] $Records,
    [scriptblock] $KeySelector,
    [int] $Limit
  )

  $selected = [Collections.Generic.List[object]]::new()
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($record in $Records) {
    $key = [string](& $KeySelector $record)
    if ($key -and $seen.Add($key)) {
      $selected.Add($record)
      if ($selected.Count -ge $Limit) { break }
    }
  }
  return $selected.ToArray()
}

$repo = (Resolve-Path -LiteralPath $Root).Path
$indexDir = Join-Path $repo 'indexed_data'
$queryArticleTypes = @(ConvertTo-QueryValues $ArticleTypes 'ArticleTypes')
$queryKeywords = @(ConvertTo-QueryValues $Keywords 'Keywords')

$articles = @(Read-JsonLines (Join-Path $indexDir 'article_index.jsonl'))
$templates = @(Read-JsonLines (Join-Path $indexDir 'template_index.jsonl'))
$styles = @(Read-JsonLines (Join-Path $indexDir 'style_index.jsonl'))
$visuals = @(Read-JsonLines (Join-Path $indexDir 'visual_index.jsonl'))
$constraints = @(Read-JsonLines (Join-Path $indexDir 'constraint_index.jsonl'))

$availableTypeSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($article in $articles) {
  foreach ($articleType in @($article.article_types)) {
    $normalized = ([string]$articleType).Trim()
    if ($normalized) {
      [void]$availableTypeSet.Add($normalized)
    }
  }
}
$unknownArticleTypes = @($queryArticleTypes | Where-Object { -not $availableTypeSet.Contains($_) })

$rankedArticles = @($articles | ForEach-Object {
  $typeMatches = @(Get-ExactMatches $_.article_types $queryArticleTypes)
  $keywordMatches = @(Get-KeywordMatches $_ $queryKeywords)
  if ($typeMatches.Count -gt 0 -or $keywordMatches.Count -gt 0) {
    [pscustomobject]@{
      record = $_
      type_matches = $typeMatches
      keyword_matches = $keywordMatches
      type_score = $typeMatches.Count
      keyword_score = $keywordMatches.Count
    }
  }
} | Sort-Object `
  @{ Expression = 'type_score'; Descending = $true },
  @{ Expression = 'keyword_score'; Descending = $true },
  @{ Expression = { $_.record.publish_time }; Descending = $true },
  @{ Expression = { $_.record.article_id }; Descending = $false })

$selectedArticleRanks = @($rankedArticles | Select-Object -First 5)
$selectedArticleIds = @($selectedArticleRanks | ForEach-Object { $_.record.article_id })
$selectedIdSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($articleId in $selectedArticleIds) { [void]$selectedIdSet.Add($articleId) }

$rankedTemplates = @($templates | ForEach-Object {
  $isPrimary = $false
  foreach ($sourceId in @($_.source_article_ids)) {
    if ($selectedIdSet.Contains([string]$sourceId)) { $isPrimary = $true; break }
  }
  $typeMatches = @(Get-ExactMatches $_.article_types $queryArticleTypes)
  if ($isPrimary -or $typeMatches.Count -gt 0) {
    [pscustomobject]@{ record = $_; primary = [int]$isPrimary; type_score = $typeMatches.Count }
  }
} | Sort-Object `
  @{ Expression = 'primary'; Descending = $true },
  @{ Expression = 'type_score'; Descending = $true },
  @{ Expression = { $_.record.template_index_id }; Descending = $false })
$selectedTemplateRanks = @(Select-UniqueRecords $rankedTemplates { param($item) $item.record.template } 5)

$allowedStyleTypes = @('expression_phrase', 'writing_method', 'rhetorical_device')
$rankedStyles = @($styles | ForEach-Object {
  if ($allowedStyleTypes -notcontains $_.expression_type) { return }
  $isPrimary = $selectedIdSet.Contains([string]$_.article_id)
  $typeMatches = @(Get-ExactMatches $_.article_types $queryArticleTypes)
  if ($isPrimary -or $typeMatches.Count -gt 0) {
    [pscustomobject]@{ record = $_; primary = [int]$isPrimary; type_score = $typeMatches.Count }
  }
} | Sort-Object `
  @{ Expression = 'primary'; Descending = $true },
  @{ Expression = 'type_score'; Descending = $true },
  @{ Expression = { $_.record.style_index_id }; Descending = $false })
$selectedStyleRanks = @(Select-UniqueRecords $rankedStyles { param($item) "$($item.record.expression_type)|$($item.record.phrase)" } 20)

$candidateVisuals = @($visuals | Where-Object {
  $selectedIdSet.Contains([string]$_.article_id) -or (Test-AnyOverlap $_.article_types $queryArticleTypes)
})
$visualPatterns = @($candidateVisuals |
  Group-Object -Property image_type, narrative_function |
  ForEach-Object {
    $groupRecords = @($_.Group)
    $primaryCount = @($groupRecords | Where-Object { $selectedIdSet.Contains([string]$_.article_id) }).Count
    $sourceIds = @($groupRecords.article_id | Sort-Object -Unique | Select-Object -First 3)
    $sourceTitles = @($groupRecords.title | Where-Object { $_ } | Sort-Object -Unique | Select-Object -First 3)
    [pscustomobject]@{
      image_type = $groupRecords[0].image_type
      narrative_function = $groupRecords[0].narrative_function
      count = $groupRecords.Count
      representative_article_ids = $sourceIds
      representative_titles = $sourceTitles
      _primary_count = $primaryCount
    }
  } |
  Sort-Object `
    @{ Expression = '_primary_count'; Descending = $true },
    @{ Expression = 'count'; Descending = $true },
    @{ Expression = 'image_type'; Descending = $false },
    @{ Expression = 'narrative_function'; Descending = $false } |
  Select-Object -First 10 |
  Select-Object image_type, narrative_function, count, representative_article_ids, representative_titles)

$rankedConstraints = @($constraints | ForEach-Object {
  $isPrimary = $selectedIdSet.Contains([string]$_.article_id)
  $typeMatches = @(Get-ExactMatches $_.applicable_article_types $queryArticleTypes)
  if ($isPrimary -or $typeMatches.Count -gt 0) {
    [pscustomobject]@{
      record = $_
      primary = [int]$isPrimary
      must_check = [int][bool]$_.must_check
      risk_score = if ($_.risk_level -eq 'high') { 2 } else { 1 }
      type_score = $typeMatches.Count
    }
  }
} | Sort-Object `
  @{ Expression = 'primary'; Descending = $true },
  @{ Expression = 'must_check'; Descending = $true },
  @{ Expression = 'risk_score'; Descending = $true },
  @{ Expression = 'type_score'; Descending = $true },
  @{ Expression = { $_.record.constraint_category }; Descending = $false },
  @{ Expression = { $_.record.rule }; Descending = $false })
$selectedConstraintRanks = @(Select-UniqueRecords $rankedConstraints { param($item) "$($item.record.constraint_category)|$($item.record.rule)|$($item.record.risk_level)" } 20)

$warnings = [Collections.Generic.List[string]]::new()
if ($unknownArticleTypes.Count -gt 0) {
  $warnings.Add("Unknown article type(s): $($unknownArticleTypes -join ', '). Run ./scripts/list-article-types.ps1 -Root . to inspect available types.")
}
if ($selectedArticleRanks.Count -lt 3) {
  $warnings.Add("Only $($selectedArticleRanks.Count) reference article(s) found; the target minimum is 3.")
}
if ($selectedTemplateRanks.Count -lt 3) {
  $warnings.Add("Only $($selectedTemplateRanks.Count) structure template(s) found; the target minimum is 3.")
}

$referenceArticles = @($selectedArticleRanks | ForEach-Object {
  [ordered]@{
    article_id = $_.record.article_id
    title = $_.record.title
    publish_time = $_.record.publish_time
    article_types = @($_.record.article_types)
    keywords = @($_.record.keywords)
    matched_article_types = @($_.type_matches)
    matched_keywords = @($_.keyword_matches)
    summary = $_.record.summary
    communication_goal = $_.record.communication_goal
    structure_summary = $_.record.structure_summary
    source_url = $_.record.source_url
  }
})

$structureTemplates = @($selectedTemplateRanks | ForEach-Object {
  [ordered]@{
    template_index_id = $_.record.template_index_id
    template_type = $_.record.template_type
    template = $_.record.template
    cluster_signature = $_.record.cluster_signature
    applicable_scenarios = @($_.record.applicable_scenarios)
    not_applicable_scenarios = @($_.record.not_applicable_scenarios)
    required_facts = @($_.record.required_facts)
    risk_notes = @($_.record.risk_notes)
    source_article_ids = @($_.record.source_article_ids)
    source_titles = @($_.record.source_titles)
  }
})

$reusableStyles = @($selectedStyleRanks | ForEach-Object {
  [ordered]@{
    style_index_id = $_.record.style_index_id
    expression_type = $_.record.expression_type
    phrase = $_.record.phrase
    style_label = $_.record.style_label
    usage_note = $_.record.usage_note
    applicable_scenarios = @($_.record.applicable_scenarios)
    risk_notes = @($_.record.risk_notes)
    source_article_id = $_.record.article_id
    source_title = $_.record.source_title
  }
})

$riskChecklist = @($selectedConstraintRanks | ForEach-Object {
  [ordered]@{
    constraint_category = $_.record.constraint_category
    constraint_scope = $_.record.constraint_scope
    rule = $_.record.rule
    risk_level = $_.record.risk_level
    must_check = [bool]$_.record.must_check
    source_article_id = $_.record.article_id
    source_title = $_.record.source_title
  }
})

$pack = [ordered]@{
  query = [ordered]@{
    root = $repo
    article_types = $queryArticleTypes
    keywords = $queryKeywords
  }
  generated_at = [DateTimeOffset]::Now.ToString('o')
  result_counts = [ordered]@{
    reference_articles = $referenceArticles.Count
    structure_templates = $structureTemplates.Count
    reusable_styles = $reusableStyles.Count
    visual_patterns = $visualPatterns.Count
    risk_checklist = $riskChecklist.Count
  }
  warnings = $warnings.ToArray()
  reference_articles = $referenceArticles
  structure_templates = $structureTemplates
  reusable_styles = $reusableStyles
  visual_patterns = $visualPatterns
  risk_checklist = $riskChecklist
}

$outputPath = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $repo $Output }
$outputPath = [IO.Path]::GetFullPath($outputPath)
$outputDir = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
  [void](New-Item -ItemType Directory -Path $outputDir -Force)
}
[IO.File]::WriteAllText($outputPath, ($pack | ConvertTo-Json -Depth 12), $utf8NoBom)

Write-Host "WRITING CONTEXT PASS"
Write-Host "Output: $outputPath"
Write-Host "Articles=$($referenceArticles.Count) Templates=$($structureTemplates.Count) Styles=$($reusableStyles.Count) VisualPatterns=$($visualPatterns.Count) Risks=$($riskChecklist.Count)"
