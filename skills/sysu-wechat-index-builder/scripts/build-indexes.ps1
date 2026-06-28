[CmdletBinding()]
# Canonical implementation for the sysu-wechat-index-builder skill.
param(
  [string] $Root = '.'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $Root).Path
$jsonDir = Join-Path $repo 'article_json'
$cleanDir = Join-Path $repo 'clean_md'
$analysisDir = Join-Path $repo 'article_analysis_md'
$outputDir = Join-Path $repo 'indexed_data'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

$requiredTop = @(
  'article_id','title','publish_time','account','publish_location','article_types','keywords','summary',
  'communication_goal','facts','structure','paragraph_functions','style','value_narrative','visuals',
  'image_stats','templates','generation_constraints'
)
$requiredConstraints = @(
  'must_not_invent','strong_claims_require_source','quote_handling','scenario_boundaries',
  'recommended_writer_use','type_specific_constraints'
)
$baseStyleLabels = @('事实驱动','分章节叙事','校媒报道')
$strongClaimPattern = '全球首例|全国首个|全国最大|首次|唯一|最高水平|重大突破|国际领先|填补空白|首批|典型案例|重磅发布'
$noisePattern = '在小说阅读器读本章|去阅读|javascript:void|预览时标签不可点|微信扫一扫|iSYSU|(?m)^\s*(?:\*+\s*)?▼'

function Normalize-Text {
  param([AllowNull()][object] $Value)
  if ($null -eq $Value) { return '' }
  return (([string]$Value -replace '\*\*|_', '' -replace '\s+', ' ').Trim())
}

function As-Array {
  param([AllowNull()][object] $Value)
  if ($null -eq $Value) { return @() }
  return @($Value)
}

function Join-Values {
  param([AllowNull()][object] $Value, [string] $Separator = '、')
  return ((As-Array $Value | ForEach-Object { Normalize-Text $_ } | Where-Object { $_ }) -join $Separator)
}

function New-List { return ,([Collections.Generic.List[object]]::new()) }

function Write-JsonLines {
  param([string] $Path, [Collections.IEnumerable] $Records)
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($record in $Records) {
    $lines.Add(($record | ConvertTo-Json -Depth 20 -Compress))
  }
  [IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

function Get-Templates {
  param([AllowNull()][object] $Templates)
  if ($null -eq $Templates) { return @() }

  # Map source JSON property names to canonical template_type values
  $typeKeyMap = @{
    'title_templates'          = 'title'
    'opening_templates'        = 'opening'
    'structure_templates'      = 'structure'
    'transition_templates'     = 'transition'
    'ending_templates'         = 'ending'
    'visual_caption_templates' = 'visual_caption'
    'notice_flow_templates'    = 'notice_flow'
  }

  if ($Templates -is [array]) {
    # Flat array (legacy): use per-item template_type if present, else default to 'structure'
    return @($Templates | ForEach-Object {
      $type = if ($_.template_type) { [string]$_.template_type } else { 'structure' }
      [pscustomobject]@{ Item = $_; Type = $type }
    })
  }

  # Dict with named property arrays: map property name to canonical type
  $result = [Collections.Generic.List[object]]::new()
  foreach ($prop in $Templates.PSObject.Properties) {
    if ($prop.Value -is [array] -and $prop.Value.Count -gt 0) {
      $type = if ($typeKeyMap.ContainsKey($prop.Name)) { $typeKeyMap[$prop.Name] } else { $prop.Name -replace '_templates$', '' }
      foreach ($item in $prop.Value) {
        $result.Add([pscustomobject]@{ Item = $item; Type = $type })
      }
    }
  }
  return @($result)
}

function Get-ParagraphLabel {
  param([object] $Paragraph)
  $value = (Join-Values $Paragraph.function_tags ' ') + ' ' + (Normalize-Text $Paragraph.summary)
  $rules = @(
    @('风险|安全|预警|防御|提醒','风险提醒'),
    @('流程|操作|报名|投稿|资格|规则|通知','流程指引'),
    @('通知|公告','通知说明'),
    @('温情|祝福|情感收束|金句收束|意象收束','温情收束'),
    @('未来|愿景|规划|展望|倡议','未来展望'),
    @('价值升华|主题升华|使命升华|总结升华|共同体升华','价值升华'),
    @('情感|情绪|氛围营造','情感铺垫'),
    @('学生反馈|学生评价|用户反馈','学生反馈'),
    @('指南|方法清单|防御建议','操作指南'),
    @('科普|科学解释|专业知识','科普解释'),
    @('机制|制度|体系','机制展开'),
    @('图文|图注|视觉','图文支撑'),
    @('现场|纪实|场景','现场描写'),
    @('校史连接|校史|建校|迁校','校史连接'),
    @('历史|史实|史料|纪念节点','历史回溯'),
    @('人物故事|人物成长|人物经历|人物个案','人物故事'),
    @('人物引语|直接引语|受助者引语|学生观点','人物引语'),
    @('专家|权威引语|领导观点|负责人引语','专家背书'),
    @('数据|数字|规模|排名','数据支撑'),
    @('技术|研发|方法说明','技术解释'),
    @('背景|缘起|语境|问题提出','背景交代'),
    @('新闻导语|新闻导入|核心消息|权威导入','新闻导语'),
    @('标题|设问|悬念','标题钩子')
  )
  foreach ($rule in $rules) { if ($value -match $rule[0]) { return $rule[1] } }
  return '核心事实'
}

function Get-FactType {
  param([AllowNull()][object] $Type)
  $value = Normalize-Text $Type
  $rules = @(
    @('风险|安全|预警|防御','风险提醒'),
    @('条件|资格|规则|要求','条件事实'),
    @('流程|报名|投稿','流程事实'),
    @('未来|计划|规划|愿景|目标|倡议','未来计划'),
    @('引语|观点|表态','引语事实'),
    @('历史|校史|创校|迁校|抗战','历史事实'),
    @('项目','项目事实'),
    @('荣誉|获奖|入选|评奖|首例|首创|首次','荣誉事实'),
    @('成果|成效|贡献|突破|论文|出版|转化','成果事实'),
    @('数据|数字|人数|规模|距离|排名|周期','数字事实'),
    @('人物|履历|职务|学生|教师|运动员|志愿者','人物事实'),
    @('机构|组织|平台|团队|部门','机构事实'),
    @('地点|区域|城市|校园','地点事实'),
    @('时间|日期|节点|截止','时间事实')
  )
  foreach ($rule in $rules) { if ($value -match $rule[0]) { return $rule[1] } }
  return '事件事实'
}

function Get-ExpressionType {
  param([string] $SourceType, [string] $FunctionLabel = '')
  if ($SourceType -eq 'ending_method' -or $FunctionLabel -eq '温情收束') { return '温情收束' }
  if ($FunctionLabel -in @('标题钩子','新闻导语')) { return '开头表达' }
  if ($FunctionLabel -in @('专家背书','人物引语','人物故事')) { return '人物表达' }
  if ($FunctionLabel -eq '价值升华') { return '价值升华' }
  if ($FunctionLabel -in @('背景交代','机制展开','历史回溯','校史连接')) { return '过渡表达' }
  if ($SourceType -eq 'rhetorical_devices') { return '价值升华' }
  if ($SourceType -eq 'sentence_features') { return '过渡表达' }
  return '成果表达'
}

function Get-VisualType {
  param([object] $Visual)
  $value = "$(Normalize-Text $Visual.type) $(Normalize-Text $Visual.caption)"
  $rules = @(
    @('封面','封面图'), @('开场动图|开篇动图|动态视觉','开场动图'),
    @('二维码','二维码图'), @('海报','活动海报'), @('证书|奖项|荣誉','证书奖项图'),
    @('数据|图表|信息图','数据图表'), @('设备','科研设备图'), @('医学|医疗|手术|临床','医学场景图'),
    @('新旧|对比','新旧对照图'), @('历史|史料|文献','历史照片'), @('校园|建筑|风景','校园风景图'),
    @('群像|合影|团队','群像图'), @('人物|肖像','人物图'), @('现场|活动|纪实|实践','现场图'),
    @('分隔|章节装饰|视觉分隔','章节分隔图'), @('尾图|收束图|结尾','尾图')
  )
  foreach ($rule in $rules) { if ($value -match $rule[0]) { return $rule[1] } }
  return (Normalize-Text $Visual.type)
}

function Get-NarrativeFunction {
  param([object] $Visual, [string] $ImageType)
  $value = "$ImageType $(Normalize-Text $Visual.function) $(Normalize-Text $Visual.caption)"
  $rules = @(
    @('安全|预警|防范','安全提醒'), @('二维码|流程|操作|指南','流程说明'),
    @('尾图|结尾|号召|收束','结尾召唤'), @('分隔|装饰|阅读节奏','视觉休息'),
    @('新旧','新旧对照'), @('历史|史料|回望','历史回望'),
    @('人物|肖像|群像|合影','人物具象化'), @('成果|设备|证书|奖项|荣誉|平台','成果展示'),
    @('现场|活动|纪实|氛围','增强现场感'), @('封面|开场|开篇|主题|视觉入口','开场定调'),
    @('证明|事实|数据','证明事实'), @('情绪|温情','情绪铺垫')
  )
  foreach ($rule in $rules) { if ($value -match $rule[0]) { return $rule[1] } }
  return (Normalize-Text $Visual.function)
}

function Get-ConstraintType {
  param([string] $SourceCategory, [string] $Rule)
  if ($Rule -match '隐私|个人信息') { return 'privacy' }
  if ($Rule -match '招生|报名|录取|报考') { return 'admissions' }
  if ($Rule -match '医学|医疗|患者|临床|手术') { return 'medical' }
  if ($Rule -match '政治|政策|会议精神|职务') { return 'political' }
  if ($Rule -match '安全|预警|风险|应急') { return 'safety' }
  if ($Rule -match '荣誉|奖项|入选') { return 'honor' }
  if ($Rule -match '数字|日期|数据|比例|排名') { return 'data' }
  switch ($SourceCategory) {
    'strong_claims_require_source' { return 'strong_claim' }
    'quote_handling' { return 'quote' }
    'scenario_boundaries' { return 'scenario_boundary' }
    'quote_handling_item' { return 'quote' }
    'scenario_boundary_item' { return 'scenario_boundary' }
    'strong_claim_item' { return 'strong_claim' }
    default { return 'identity' }
  }
}

function Get-ImageUrlMap {
  param([string] $Clean)
  $map = @{}
  $pendingImageId = $null
  foreach ($line in ($Clean -split "`r?`n")) {
    if ($line -match '<!--\s*(cover|img\d+)\s*-->') {
      $pendingImageId = $Matches[1]
      continue
    }
    if ($line -match '<!--\s*p\d+\s*-->') {
      $pendingImageId = $null
      continue
    }
    if ($pendingImageId -and $line -match '!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)') {
      $map[$pendingImageId] = $Matches[1]
      $pendingImageId = $null
    }
  }
  return $map
}

if (-not (Test-Path -LiteralPath $jsonDir)) { throw "Missing input directory: $jsonDir" }
[IO.Directory]::CreateDirectory($outputDir) | Out-Null

$sources = New-List
foreach ($file in Get-ChildItem -LiteralPath $jsonDir -Filter '*.json' | Sort-Object Name) {
  $baseName = $file.BaseName
  $cleanPath = Join-Path $cleanDir "$baseName.clean.md"
  $analysisPath = Join-Path $analysisDir "$baseName.analysis.md"
  $issues = [Collections.Generic.List[string]]::new()
  $schemaIssues = [Collections.Generic.List[string]]::new()
  $json = $null
  $clean = ''
  $parseOk = $true

  try { $json = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json } catch { $parseOk = $false; $issues.Add('json_parse') }
  $tripletComplete = (Test-Path -LiteralPath $cleanPath) -and (Test-Path -LiteralPath $analysisPath)
  if (-not $tripletComplete) { $issues.Add('triplet_incomplete') }
  if (Test-Path -LiteralPath $cleanPath) { $clean = [IO.File]::ReadAllText($cleanPath) }

  if ($json) {
    foreach ($key in $requiredTop) {
      if ($key -notin $json.PSObject.Properties.Name -or $null -eq $json.$key) { $schemaIssues.Add("top_level:$key") }
    }
    if (-not (Normalize-Text $json.article_id)) { $schemaIssues.Add('article_id') }
    if (-not (Normalize-Text $json.title)) { $schemaIssues.Add('title') }
    foreach ($fact in As-Array $json.facts) {
      foreach ($key in @('source_paragraph_id','source_quote','confidence')) {
        if (-not (Normalize-Text $fact.$key)) { $schemaIssues.Add("fact:$($fact.id):$key") }
      }
    }
    foreach ($paragraph in As-Array $json.paragraph_functions) {
      foreach ($key in @('paragraph_id','display_text','normalized_text')) {
        if (-not (Normalize-Text $paragraph.$key)) { $schemaIssues.Add("paragraph:$($paragraph.paragraph_id):$key") }
      }
    }
    foreach ($visual in As-Array $json.visuals) {
      if (-not (Normalize-Text $visual.image_id)) { $schemaIssues.Add('visual:image_id') }
    }
    foreach ($key in $requiredConstraints) {
      if ($key -notin $json.generation_constraints.PSObject.Properties.Name) { $schemaIssues.Add("generation_constraints:$key") }
    }
    if ($null -eq $json.image_stats) { $schemaIssues.Add('image_stats') }

    $paragraphMap = @{}
    foreach ($paragraph in As-Array $json.paragraph_functions) { $paragraphMap[$paragraph.paragraph_id] = Normalize-Text $paragraph.normalized_text }
    foreach ($fact in As-Array $json.facts) {
      $quote = Normalize-Text $fact.source_quote
      if (-not $paragraphMap.ContainsKey($fact.source_paragraph_id) -or -not $paragraphMap[$fact.source_paragraph_id].Contains($quote)) {
        $schemaIssues.Add("fact_quote:$($fact.id)")
      }
    }
    foreach ($visual in As-Array $json.visuals) {
      $anchor = [regex]::Escape([string]$visual.image_id)
      if ($clean -notmatch "<!--\s*$anchor\s*-->") { $schemaIssues.Add("visual_anchor:$($visual.image_id)") }
    }
    $urls = @([regex]::Matches($clean, '!\[[^\]]*\]\(([^)\s]+)') | ForEach-Object { $_.Groups[1].Value })
    if ($json.image_stats.total_image_nodes_in_clean -ne $urls.Count) { $schemaIssues.Add('image_count') }
    if ($json.image_stats.unique_image_urls -ne @($urls | Sort-Object -Unique).Count) { $schemaIssues.Add('unique_image_count') }
  }

  $sources.Add([pscustomobject]@{
    File = $file
    BaseName = $baseName
    Json = $json
    Clean = $clean
    ParseOk = $parseOk
    TripletComplete = $tripletComplete
    NoiseDetected = [bool]($clean -match $noisePattern)
    Issues = $issues
    SchemaIssues = $schemaIssues
  })
}

$idGroups = @($sources | Where-Object Json | Group-Object { $_.Json.article_id })
foreach ($group in $idGroups | Where-Object Count -gt 1) {
  foreach ($source in $group.Group) { $source.SchemaIssues.Add("duplicate_article_id:$($group.Name)") }
}

$qualityRecords = New-List
$articleRecords = New-List
$paragraphRecords = New-List
$factRecords = New-List
$templateRecords = New-List
$styleRecords = New-List
$visualRecords = New-List
$constraintRecords = New-List
$readySources = New-List

foreach ($source in $sources) {
  $schemaConsistent = $source.SchemaIssues.Count -eq 0
  $ready = $source.ParseOk -and $source.TripletComplete -and $schemaConsistent -and -not $source.NoiseDetected
  $action = if (-not $source.ParseOk -or -not $source.TripletComplete) { 'exclude' } elseif (-not $ready) { 'review' } else { 'pass' }
  $allIssues = @($source.Issues) + @($source.SchemaIssues)
  if ($source.NoiseDetected) { $allIssues += 'clean_md_noise' }
  $qualityRecords.Add([ordered]@{
    article_id = if ($source.Json) { [string]$source.Json.article_id } else { '' }
    title = if ($source.Json) { [string]$source.Json.title } else { $source.BaseName }
    json_parse_ok = $source.ParseOk
    triplet_complete = $source.TripletComplete
    schema_consistent = $schemaConsistent
    clean_md_noise_detected = $source.NoiseDetected
    ready_for_indexing = $ready
    recommended_action = $action
    issues = @($allIssues)
  })
  if ($ready) { $readySources.Add($source) }
}

foreach ($source in $readySources) {
  $j = $source.Json
  $articleId = [string]$j.article_id
  $articleTypes = @(As-Array $j.article_types)
  $keywords = @(As-Array $j.keywords)
  $styleLabels = @(if ($j.style.labels) { As-Array $j.style.labels } elseif ($j.style.style_labels) { As-Array $j.style.style_labels } else { @() })
  $valueThemes = @(if ($j.value_narrative.themes) { As-Array $j.value_narrative.themes } elseif ($j.value_themes) { As-Array $j.value_themes } else { @() })
  $schoolImage = @(As-Array $j.value_narrative.school_image)
  $structureSummary = ((As-Array $j.structure | ForEach-Object {
    $parts = @((Normalize-Text $_.section), (Normalize-Text $_.function), (Normalize-Text $_.summary)) | Where-Object { $_ }
    $parts -join '：'
  }) -join '；')
  $flatTemplates = Get-Templates $j.templates
  $scenes = @($flatTemplates | ForEach-Object { As-Array $_.Item.applicable_scenarios } | Select-Object -Unique)
  $articleEmbedding = @(
    "标题：$($j.title)", "文章类型：$(Join-Values $articleTypes)", "关键词：$(Join-Values $keywords)",
    "摘要：$($j.summary)", "传播目的：$($j.communication_goal)", "文章结构：$structureSummary",
    "风格标签：$(Join-Values $styleLabels)", "价值主题：$(Join-Values $valueThemes)", "适合参考场景：$(Join-Values $scenes)"
  ) -join "`n"
  $articleRecords.Add([ordered]@{
    article_id = $articleId; title = [string]$j.title; publish_time = [string]$j.publish_time
    account = [string]$j.account; publish_location = [string]$j.publish_location
    article_types = $articleTypes; keywords = $keywords; summary = [string]$j.summary
    communication_goal = $j.communication_goal; structure_summary = $structureSummary
    style_labels = $styleLabels; value_themes = $valueThemes; school_image = $schoolImage
    image_stats = $j.image_stats; quality_status = 'ready'; source_url = ''; text_for_embedding = $articleEmbedding
  })

  foreach ($paragraph in As-Array $j.paragraph_functions) {
    $label = Get-ParagraphLabel $paragraph
    $paragraphRecords.Add([ordered]@{
      paragraph_index_id = "$articleId::$($paragraph.paragraph_id)"; article_id = $articleId; title = [string]$j.title
      paragraph_id = [string]$paragraph.paragraph_id; display_text = [string]$paragraph.display_text
      normalized_text = [string]$paragraph.normalized_text; function_label = $label
      writing_method = [string]$paragraph.writing_method; article_types = $articleTypes; style_labels = $styleLabels
      value_themes = $valueThemes; reuse_value = [string]$paragraph.reuse_value
      text_for_embedding = "段落功能：$label`n写作方法：$($paragraph.writing_method)`n段落内容：$($paragraph.normalized_text)`n文章类型：$(Join-Values $articleTypes)`n风格标签：$(Join-Values $styleLabels)"
    })
  }

  foreach ($fact in As-Array $j.facts) {
    $factType = Get-FactType $fact.type
    $entities = [Collections.Generic.List[string]]::new()
    $subject = Normalize-Text $fact.subject
    $object = Normalize-Text $fact.object
    if ($subject) { $entities.Add($subject) }
    if ($object -and $object.Length -le 30 -and $object -notmatch '[。！？；：]$' -and $object -notin $entities) { $entities.Add($object) }
    $verify = [bool]("$($fact.fact) $($fact.source_quote)" -match $strongClaimPattern)
    $factRecords.Add([ordered]@{
      fact_index_id = "$articleId::$($fact.id)"; article_id = $articleId; title = [string]$j.title
      fact = [string]$fact.fact; fact_type = $factType; entities = @($entities)
      source_paragraph_id = [string]$fact.source_paragraph_id; source_quote = [string]$fact.source_quote
      confidence = [string]$fact.confidence; risk = [string]$fact.risk; requires_verification = $verify
      article_types = $articleTypes; keywords = $keywords
      text_for_embedding = "事实：$($fact.fact)`n事实类型：$factType`n实体：$(Join-Values $entities)`n来源引文：$($fact.source_quote)`n文章类型：$(Join-Values $articleTypes)`n关键词：$(Join-Values $keywords)"
    })
  }

  $templateNumber = 0
  foreach ($template in $flatTemplates) {
    $templateNumber++
    $typeValue = $template.Type
    $typeDisplayName = @{
      'title'          = '标题模板'
      'opening'        = '开头模板'
      'structure'      = '结构模板'
      'transition'     = '过渡模板'
      'ending'         = '结尾模板'
      'visual_caption' = '视觉图注模板'
      'notice_flow'    = '通知流程模板'
    }[$typeValue]
    if (-not $typeDisplayName) { $typeDisplayName = "$typeValue模板" }
    $applicable = @(As-Array $template.Item.applicable_scenarios)
    $notApplicable = @(As-Array $template.Item.not_applicable_scenarios)
    $templateRecords.Add([ordered]@{
      template_index_id = ('{0}::template_{1}_{2:d3}' -f $articleId,$typeValue,$templateNumber)
      article_id = $articleId; source_title = [string]$j.title; template_type = $typeValue
      template = [string]$template.Item.template; applicable_scenarios = $applicable; not_applicable_scenarios = $notApplicable
      required_facts = @(); risk_notes = @(); article_types = $articleTypes; style_labels = $styleLabels; value_themes = $valueThemes
      text_for_embedding = "模板类型：$typeDisplayName`n模板内容：$($template.Item.template)`n适用场景：$(Join-Values $applicable)`n不适用场景：$(Join-Values $notApplicable)`n所需事实：`n风险提示：`n来源文章：$($j.title)"
    })
  }

  $primaryStyle = @($styleLabels | Where-Object { $_ -notin $baseStyleLabels } | Select-Object -First 1)
  $primaryStyleLabel = if ($primaryStyle.Count) { [string]$primaryStyle[0] } elseif ($styleLabels.Count) { [string]$styleLabels[0] } else { '' }
  $styleCandidates = New-List
  foreach ($sourceType in @('common_phrases','reusable_phrases','sentence_features','rhetorical_devices','writing_methods')) {
    foreach ($phrase in As-Array $j.style.$sourceType) {
      $styleCandidates.Add([pscustomobject]@{ SourceType=$sourceType; Phrase=(Normalize-Text $phrase); Usage=''; FunctionLabel='' })
    }
  }
  if (Normalize-Text $j.value_narrative.ending_method) {
    $styleCandidates.Add([pscustomobject]@{ SourceType='ending_method'; Phrase=(Normalize-Text $j.value_narrative.ending_method); Usage='结尾方式'; FunctionLabel='温情收束' })
  }
  foreach ($paragraph in As-Array $j.paragraph_functions | Where-Object { $_.reuse_value -in @('高','high') }) {
    $label = Get-ParagraphLabel $paragraph
    $styleCandidates.Add([pscustomobject]@{ SourceType='high_reuse_paragraph'; Phrase=(Normalize-Text $paragraph.normalized_text); Usage=(Normalize-Text $paragraph.writing_method); FunctionLabel=$label })
  }
  $seenStyles = @{}
  $styleNumber = 0
  foreach ($candidate in $styleCandidates) {
    if (-not $candidate.Phrase) { continue }
    $dedupeKey = "$($candidate.SourceType)|$($candidate.Phrase)"
    if ($seenStyles.ContainsKey($dedupeKey)) { continue }
    $seenStyles[$dedupeKey] = $true
    $styleNumber++
    $expressionType = Get-ExpressionType $candidate.SourceType $candidate.FunctionLabel
    $riskNotes = if ($candidate.SourceType -eq 'high_reuse_paragraph') { @('涉及具体事实时必须替换并核验') } else { @() }
    $styleRecords.Add([ordered]@{
      style_index_id = ('{0}::style_{1:d3}' -f $articleId,$styleNumber); article_id = $articleId
      source_title = [string]$j.title; style_label = $primaryStyleLabel; expression_type = $expressionType
      phrase = $candidate.Phrase; usage_note = $candidate.Usage; applicable_scenarios = $articleTypes
      risk_notes = $riskNotes; article_types = $articleTypes
      text_for_embedding = "风格标签：$primaryStyleLabel`n表达类型：$expressionType`n表达：$($candidate.Phrase)`n使用说明：$($candidate.Usage)`n适用场景：$(Join-Values $articleTypes)`n风险提示：$(Join-Values $riskNotes)"
    })
  }

  $urlMap = Get-ImageUrlMap $source.Clean
  foreach ($visual in As-Array $j.visuals) {
    $imageId = [string]$visual.image_id
    $imageType = Get-VisualType $visual
    $narrativeFunction = Get-NarrativeFunction $visual $imageType
    $related = @([regex]::Matches([string]$visual.position, 'p\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)
    $imageUrl = if ($urlMap.ContainsKey($imageId)) { [string]$urlMap[$imageId] } else { '' }
    $visualRecords.Add([ordered]@{
      visual_index_id = "$articleId::$imageId"; article_id = $articleId; title = [string]$j.title
      image_id = $imageId; image_url = $imageUrl; image_type = $imageType; caption = [string]$visual.caption
      caption_source = [string]$visual.caption_source; position = [string]$visual.position
      narrative_function = $narrativeFunction; related_paragraphs = $related
      article_types = $articleTypes; style_labels = $styleLabels
      text_for_embedding = "图片类型：$imageType`n图片说明：$($visual.caption)`n位置：$($visual.position)`n叙事功能：$narrativeFunction`n相关文章类型：$(Join-Values $articleTypes)"
    })
  }

  $constraintNumber = 0
  foreach ($sourceCategory in @('must_not_invent','strong_claims_require_source','quote_handling','scenario_boundaries')) {
    foreach ($rule in As-Array $j.generation_constraints.$sourceCategory) {
      $constraintNumber++
      $ruleText = Normalize-Text $rule
      $constraintType = Get-ConstraintType $sourceCategory $ruleText
      $riskLevel = if ($sourceCategory -eq 'scenario_boundaries') { 'medium' } else { 'high' }
      $constraintRecords.Add([ordered]@{
        constraint_index_id = ('{0}::constraint_{1:d3}' -f $articleId,$constraintNumber); article_id = $articleId
        source_title = [string]$j.title; constraint_type = $constraintType; term = $sourceCategory
        rule = $ruleText; risk_level = $riskLevel; applicable_article_types = $articleTypes; must_check = $true
        text_for_embedding = "约束类型：$constraintType`n约束项：$sourceCategory`n规则：$ruleText`n风险等级：$riskLevel`n适用文章类型：$(Join-Values $articleTypes)"
      })
    }
  }
  foreach ($item in As-Array $j.generation_constraints.type_specific_constraints) {
    $constraintNumber++
    $categoryAlias = switch ([string]$item.category) {
      'strong_claim' { 'strong_claim_item' }
      'quote_handling' { 'quote_handling_item' }
      'scenario_boundary' { 'scenario_boundary_item' }
      default { [string]$item.category }
    }
    $ruleText = Normalize-Text $item.constraint
    $constraintType = Get-ConstraintType $categoryAlias "$($item.term) $ruleText"
    $riskLevel = if ($item.category -eq 'scenario_boundary') { 'medium' } else { 'high' }
    $constraintRecords.Add([ordered]@{
      constraint_index_id = ('{0}::constraint_{1:d3}' -f $articleId,$constraintNumber); article_id = $articleId
      source_title = [string]$j.title; constraint_type = $constraintType; term = [string]$item.term
      rule = $ruleText; risk_level = $riskLevel; applicable_article_types = $articleTypes; must_check = $true
      text_for_embedding = "约束类型：$constraintType`n约束项：$($item.term)`n规则：$ruleText`n风险等级：$riskLevel`n适用文章类型：$(Join-Values $articleTypes)"
    })
  }
}

$recordsByFile = [ordered]@{
  'quality_report.jsonl' = $qualityRecords
  'article_index.jsonl' = $articleRecords
  'paragraph_index.jsonl' = $paragraphRecords
  'fact_index.jsonl' = $factRecords
  'template_index.jsonl' = $templateRecords
  'style_index.jsonl' = $styleRecords
  'visual_index.jsonl' = $visualRecords
  'constraint_index.jsonl' = $constraintRecords
}
foreach ($entry in $recordsByFile.GetEnumerator()) { Write-JsonLines (Join-Path $outputDir $entry.Key) $entry.Value }

$reviewCount = @($qualityRecords | Where-Object recommended_action -eq 'review').Count
$excludedCount = @($qualityRecords | Where-Object recommended_action -eq 'exclude').Count
$chinaZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
$generatedAt = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $chinaZone).ToString('yyyy-MM-ddTHH:mm:sszzz')
$manifest = [ordered]@{
  version = 'v0.1'; generated_at = $generatedAt; source_article_count = $sources.Count
  article_index_count = $articleRecords.Count; paragraph_index_count = $paragraphRecords.Count
  fact_index_count = $factRecords.Count; template_index_count = $templateRecords.Count
  style_index_count = $styleRecords.Count; visual_index_count = $visualRecords.Count
  constraint_index_count = $constraintRecords.Count; ready_article_count = $readySources.Count
  review_article_count = $reviewCount; excluded_article_count = $excludedCount
}
[IO.File]::WriteAllText((Join-Path $outputDir 'index_manifest.json'), ($manifest | ConvertTo-Json -Depth 10), $utf8NoBom)

$idChecks = @(
  @($articleRecords.article_id), @($paragraphRecords.paragraph_index_id), @($factRecords.fact_index_id),
  @($templateRecords.template_index_id), @($styleRecords.style_index_id), @($visualRecords.visual_index_id),
  @($constraintRecords.constraint_index_id)
)
foreach ($ids in $idChecks) {
  if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'Generated index contains duplicate record IDs.' }
}
$articleIdSet = @{}
foreach ($record in $articleRecords) { $articleIdSet[$record.article_id] = $true }
foreach ($collection in @($paragraphRecords,$factRecords,$templateRecords,$styleRecords,$visualRecords,$constraintRecords)) {
  foreach ($record in $collection) {
    if (-not $articleIdSet.ContainsKey($record.article_id)) { throw "Dangling article_id: $($record.article_id)" }
  }
}

Write-Output ('INDEX BUILD PASS source={0} ready={1} article={2} paragraph={3} fact={4} template={5} style={6} visual={7} constraint={8}' -f
  $sources.Count,$readySources.Count,$articleRecords.Count,$paragraphRecords.Count,$factRecords.Count,
  $templateRecords.Count,$styleRecords.Count,$visualRecords.Count,$constraintRecords.Count)
