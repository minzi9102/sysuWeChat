[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Root,

  [string] $Filter = ''
)

$ErrorActionPreference = 'Stop'

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

$repo = (Resolve-Path -LiteralPath $Root).Path
$articleIndexPath = Join-Path (Join-Path $repo 'indexed_data') 'article_index.jsonl'
$articles = @(Read-JsonLines $articleIndexPath)

$counts = @{}
foreach ($article in $articles) {
  $articleTypeSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($articleType in @($article.article_types)) {
    $normalized = ([string]$articleType).Trim()
    if (-not $normalized) { continue }
    if (-not $articleTypeSet.Add($normalized)) { continue }
    if (-not $counts.ContainsKey($normalized)) {
      $counts[$normalized] = 0
    }
    $counts[$normalized]++
  }
}

$filterText = $Filter.Trim()
$rows = @($counts.GetEnumerator() | ForEach-Object {
  if ($filterText -and $_.Key.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    return
  }
  [pscustomobject]@{
    article_type = $_.Key
    count = [int]$_.Value
  }
} | Sort-Object `
  @{ Expression = 'count'; Descending = $true },
  @{ Expression = 'article_type'; Descending = $false })

if ($filterText -and $rows.Count -eq 0) {
  Write-Output "No article types matched filter: $filterText"
  exit 0
}

$rows
