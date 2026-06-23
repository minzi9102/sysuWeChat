[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $SourcePath
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $SourcePath).Path
$source = [IO.File]::ReadAllText($resolved)

function Get-Boundary {
  param([string] $Text)

  $candidates = [Collections.Generic.List[object]]::new()
  $patterns = @(
    @{ Reason = 'recommendation_arrow'; Pattern = '(?m)^\s*(?:\*+\s*)?▼.*$' },
    @{ Reason = 'recommendation_heading'; Pattern = '(?mi)^\s*(?:#+\s*)?(?:\*+\s*)?(?:推荐阅读|相关阅读|往期推荐)(?:\s*\*+)?\s*$' },
    @{ Reason = 'isysu_footer'; Pattern = '(?mi)^.*iSYSU.*$' },
    @{ Reason = 'selected_comments'; Pattern = '(?mi)^\s*(?:#+\s*)?(?:精选留言|精选评论|留言区)(?:\s*\*+)?\s*$' }
  )
  foreach ($entry in $patterns) {
    $match = [regex]::Match($Text, $entry.Pattern)
    if ($match.Success) {
      $candidates.Add([pscustomobject]@{ Offset = $match.Index; Reason = $entry.Reason; Text = $match.Value.Trim() })
    }
  }
  if (-not $candidates.Count) {
    return [pscustomobject]@{ Offset = $Text.Length; Reason = 'end_of_file'; Text = '' }
  }
  return $candidates | Sort-Object Offset | Select-Object -First 1
}

function Get-ImageNodes {
  param([string] $Text)

  $nodes = [Collections.Generic.List[object]]::new()
  foreach ($match in [regex]::Matches($Text, '!\[([^\]]*)\]\(([^)]+)\)')) {
    if ($match.Groups[1].Value -eq 'cover_image') { continue }
    $nodes.Add([pscustomobject]@{
      Index = $match.Index
      Url = $match.Groups[2].Value
    })
  }
  return @($nodes)
}

function Get-EffectiveLines {
  param([string] $Text)

  $results = [Collections.Generic.List[string]]::new()
  foreach ($line in ($Text -split "`r?`n")) {
    $value = $line
    $value = $value -replace '!\[[^\]]*\]\([^)]+\)', ' '
    $value = $value -replace '\[[^\]]*\]\([^)]+\)', ' '
    $value = $value -replace '[#*_>`\[\]()]', ' '
    $value = ($value -replace '\s+', ' ').Trim()
    if (-not $value) { continue }
    if ($value -match 'https?://') { continue }
    if (($value -replace '[^\p{L}\p{N}]', '').Length -lt 4) { continue }
    if ($value -match '^(?:中山大学|在小说阅读器读本章|去阅读)$') { continue }
    if ($value -match '^\d{4}年\d{1,2}月\d{1,2}日.*(?:广东|北京|上海)?$') { continue }
    if ($value -match '^javascript:void') { continue }
    $results.Add($value)
  }
  return @($results)
}

$boundary = Get-Boundary -Text $source
$bounded = $source.Substring(0, $boundary.Offset)
$titleMatch = [regex]::Match($bounded, '(?m)^#\s+.*$')
$titleOffset = if ($titleMatch.Success) { $titleMatch.Index } else { 0 }
$bodyAfterTitle = if ($titleMatch.Success) { $bounded.Substring($titleMatch.Index + $titleMatch.Length) } else { $bounded }
$images = Get-ImageNodes -Text $bounded
$preTitle = @($images | Where-Object { $_.Index -lt $titleOffset })
$postTitle = @($images | Where-Object { $_.Index -ge ($titleOffset + $titleMatch.Length) })
$effectiveLines = Get-EffectiveLines -Text $bodyAfterTitle
$effectiveCharacters = (($effectiveLines -join '') -replace '\s+', '').Length
$uniqueImages = @($images.Url | Sort-Object -Unique)
$uniquePreTitle = @($preTitle.Url | Sort-Object -Unique)

$mode = 'text'
$matchedRule = 'text_article'
if ($preTitle.Count -ge 2 -and $uniquePreTitle.Count -ge 2 -and $postTitle.Count -eq 0) {
  $mode = 'pasted_image'
  $matchedRule = 'pre_title_images_without_post_title_images'
} elseif ($effectiveLines.Count -lt 6 -and $images.Count -gt 20) {
  $mode = 'long_image'
  $matchedRule = 'few_paragraphs_many_images'
} elseif ($effectiveCharacters -lt 80 -and $uniqueImages.Count -ge 5) {
  $mode = 'long_image'
  $matchedRule = 'sparse_text_multiple_unique_images'
}

[ordered]@{
  source_path = $resolved
  content_mode = $mode
  body_boundary = [ordered]@{
    offset = $boundary.Offset
    reason = $boundary.Reason
    matched_text = $boundary.Text
  }
  evidence = [ordered]@{
    effective_paragraphs = $effectiveLines.Count
    effective_characters = $effectiveCharacters
    body_image_nodes = $images.Count
    unique_body_image_urls = $uniqueImages.Count
    pre_title_image_nodes = $preTitle.Count
    pre_title_unique_urls = $uniquePreTitle.Count
    post_title_image_nodes = $postTitle.Count
    matched_rule = $matchedRule
  }
} | ConvertTo-Json -Depth 5
