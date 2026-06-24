[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
  Write-Error "Draft file does not exist: $Path"
  exit 1
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
  Write-Error "Draft path is not a file: $Path"
  exit 1
}

try {
  $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
  $lines = [IO.File]::ReadAllLines($resolvedPath, [Text.Encoding]::UTF8)
}
catch {
  Write-Error "Unable to read draft file '$Path'. $($_.Exception.Message)"
  exit 1
}

$rules = @(
  [pscustomobject]@{ Name = '先否定后肯定：不是…而是'; Pattern = '(?<!并)不是.*而是' }
  [pscustomobject]@{ Name = '先否定后肯定：不只是…更是'; Pattern = '不只是.*更是' }
  [pscustomobject]@{ Name = '先否定后肯定：并不是…而是'; Pattern = '并不是.*而是' }
  [pscustomobject]@{ Name = '空泛强调词'; Pattern = '真的|非常|震撼|超级' }
  [pscustomobject]@{ Name = '强断言需证据'; Pattern = '首次|首个|最大|最高|重磅' }
)

$findingCount = 0
$findingLines = [Collections.Generic.HashSet[int]]::new()

for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
  foreach ($rule in $rules) {
    foreach ($match in [regex]::Matches($lines[$lineIndex], $rule.Pattern)) {
      $findingCount++
      [void]$findingLines.Add($lineIndex + 1)
      $matchedText = $match.Value.Replace('"', '""')
      Write-Output ('WARN line={0} rule="{1}" match="{2}"' -f ($lineIndex + 1), $rule.Name, $matchedText)
    }
  }
}

if ($findingCount -eq 0) {
  Write-Output 'STYLE LINT PASS findings=0'
  exit 0
}

Write-Output ('STYLE LINT WARN findings={0} lines={1}' -f $findingCount, $findingLines.Count)
exit 0
