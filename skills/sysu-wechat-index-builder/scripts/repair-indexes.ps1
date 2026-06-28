[CmdletBinding()]
param(
  [string] $Root = '.',
  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $Root).Path
$indexDir = Join-Path $repo 'indexed_data'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$repairVersion = 'v1'

$requiredFiles = @(
  'article_index.jsonl','paragraph_index.jsonl','fact_index.jsonl','template_index.jsonl',
  'style_index.jsonl','visual_index.jsonl','constraint_index.jsonl','index_manifest.json'
)
foreach ($name in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $indexDir $name))) { throw "Missing index input: $name" }
}

function As-Array {
  param([AllowNull()][object] $Value)
  if ($null -eq $Value) { return @() }
  return @($Value)
}

function Normalize-Text {
  param([AllowNull()][object] $Value)
  if ($null -eq $Value) { return '' }
  return (([string]$Value -replace '\*\*|_', '' -replace '\s+', ' ').Trim())
}

function Get-UniqueValues {
  param([AllowNull()][object] $Values)
  $seen = @{}
  $result = [Collections.Generic.List[string]]::new()
  foreach ($value in As-Array $Values) {
    $normalized = Normalize-Text $value
    if (-not $normalized) { continue }
    $key = $normalized.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $result.Add($normalized)
  }
  return @($result)
}

function Get-SortedUniqueValues {
  param([AllowNull()][object] $Values)
  return @(Get-UniqueValues $Values | Sort-Object)
}

function Join-Values {
  param([AllowNull()][object] $Values, [string] $Separator = '、')
  return ((Get-UniqueValues $Values) -join $Separator)
}

function Read-JsonLines {
  param([string] $Name)
  $path = Join-Path $indexDir $Name
  $records = [Collections.Generic.List[object]]::new()
  $lineNumber = 0
  foreach ($line in [IO.File]::ReadLines($path)) {
    $lineNumber++
    if (-not $line.Trim()) { continue }
    try { $records.Add(($line | ConvertFrom-Json)) }
    catch { throw "Invalid JSONL in ${Name}:$lineNumber - $($_.Exception.Message)" }
  }
  return @($records)
}

function Write-JsonLines {
  param([string] $Path, [AllowNull()][object] $Records)
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($record in As-Array $Records) { $lines.Add(($record | ConvertTo-Json -Depth 30 -Compress)) }
  [IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

function Get-StableHash {
  param([string] $Value, [int] $Length = 16)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $hex = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    return $hex.Substring(0, [Math]::Min($Length, $hex.Length))
  }
  finally { $sha.Dispose() }
}

function Add-Count {
  param([hashtable] $Table, [string] $Key)
  if (-not $Table.ContainsKey($Key)) { $Table[$Key] = 0 }
  $Table[$Key]++
}

$articles = @(Read-JsonLines 'article_index.jsonl')
$paragraphs = @(Read-JsonLines 'paragraph_index.jsonl')
$facts = @(Read-JsonLines 'fact_index.jsonl')
$templates = @(Read-JsonLines 'template_index.jsonl')
$styles = @(Read-JsonLines 'style_index.jsonl')
$visuals = @(Read-JsonLines 'visual_index.jsonl')
$constraints = @(Read-JsonLines 'constraint_index.jsonl')
$manifest = Get-Content -Raw -LiteralPath (Join-Path $indexDir 'index_manifest.json') | ConvertFrom-Json
$previousReportPath = Join-Path $indexDir 'index_repair_report.json'
$previousReport = if (Test-Path -LiteralPath $previousReportPath) { Get-Content -Raw -LiteralPath $previousReportPath | ConvertFrom-Json } else { $null }
$alreadyRepaired = [string]$manifest.repair_version -eq $repairVersion

# Move concrete entities and operational topics out of value themes. Exact fact entities
# provide corpus evidence; the explicit table resolves known legacy ambiguities.
$factEntitySet = @{}
foreach ($fact in $facts) {
  foreach ($entity in As-Array $fact.entities) {
    $normalized = Normalize-Text $entity
    if ($normalized) { $factEntitySet[$normalized.ToLowerInvariant()] = $true }
  }
}
$explicitTopicTerms = @(
  '青年教师','高层次人才','医学生','小海豚志愿者','援疆医生','中大校园','校园建筑','三校区五校园',
  '网上报名','网上确认','预报名','报考条件','报名时间','招生计划','招生专业','考核录取','考生范围','材料上传',
  '阅读推荐','假期书单','大学音乐课','人文社科课程','美育公选课','全运会','马术赛事','世界粮食日',
  '习近平文化思想','古典吉他','物理学','帝企鹅','科摩罗','金奖','红楼','怀士堂','台风桦加沙','台风防御',
  '肖非','杨振宁','林泓','刘志伟','李治','Marwa','穆萨·穆里瓦'
)
$explicitTopicSet = @{}
foreach ($term in $explicitTopicTerms) { $explicitTopicSet[$term.ToLowerInvariant()] = $true }

function Test-TopicEntity {
  param([string] $Value)
  $key = $Value.ToLowerInvariant()
  if ($explicitTopicSet.ContainsKey($key) -or $factEntitySet.ContainsKey($key)) { return $true }
  if ($Value -match '[A-Za-z0-9+]|\d+(?:\.\d+)?米') { return $true }
  if ($Value -match '大学|学院|医院|中心|团队|工作站|平台|系统|计划|项目|课程|书单|校区|校园|天文台|望远镜|巡诊车|巨型稻|研究院|医疗队|大赛|论坛|赛事|账号|报考点|招生|报名|录取|确认|材料上传') { return $true }
  return $false
}

$topicMigrationCount = 0
$articleTopicMap = @{}
$repairedArticles = [Collections.Generic.List[object]]::new()
foreach ($article in $articles) {
  $before = @(Get-UniqueValues (@($article.value_themes) + @($article.topic_entities)))
  $keptValues = [Collections.Generic.List[string]]::new()
  $topics = [Collections.Generic.List[string]]::new()
  foreach ($topic in As-Array $article.topic_entities) {
    $normalized = Normalize-Text $topic
    if ($normalized) { $topics.Add($normalized) }
  }
  foreach ($theme in As-Array $article.value_themes) {
    $normalized = Normalize-Text $theme
    if (-not $normalized) { continue }
    if (Test-TopicEntity $normalized) { $topics.Add($normalized); $topicMigrationCount++ }
    else { $keptValues.Add($normalized) }
  }
  $finalValues = @(Get-UniqueValues $keptValues)
  $finalTopics = @(Get-UniqueValues $topics)
  $after = @(Get-UniqueValues (@($finalValues) + @($finalTopics)))
  $beforeKey = (Get-SortedUniqueValues $before) -join "`n"
  $afterKey = (Get-SortedUniqueValues $after) -join "`n"
  if ($beforeKey -ne $afterKey) {
    throw "Theme/topic conservation failed: $($article.article_id)"
  }
  $articleTopicMap[[string]$article.article_id] = [pscustomobject]@{ Values=$finalValues; Topics=$finalTopics }
  $embedding = @(
    "标题：$($article.title)", "文章类型：$(Join-Values $article.article_types)", "关键词：$(Join-Values $article.keywords)",
    "摘要：$($article.summary)", "传播目的：$($article.communication_goal)", "文章结构：$($article.structure_summary)",
    "风格标签：$(Join-Values $article.style_labels)", "价值主题：$(Join-Values $finalValues)", "主题实体：$(Join-Values $finalTopics)"
  ) -join "`n"
  $repairedArticles.Add([pscustomobject][ordered]@{
    article_id=$article.article_id; title=$article.title; publish_time=$article.publish_time; account=$article.account
    publish_location=$article.publish_location; article_types=@($article.article_types); keywords=@($article.keywords)
    summary=$article.summary; communication_goal=$article.communication_goal; structure_summary=$article.structure_summary
    style_labels=@($article.style_labels); value_themes=$finalValues; topic_entities=$finalTopics; school_image=@($article.school_image)
    image_stats=$article.image_stats; quality_status=$article.quality_status; source_url=$article.source_url; text_for_embedding=$embedding
  })
}

$repairedParagraphs = [Collections.Generic.List[object]]::new()
foreach ($paragraph in $paragraphs) {
  $topics = $articleTopicMap[[string]$paragraph.article_id]
  $repairedParagraphs.Add([pscustomobject][ordered]@{
    paragraph_index_id=$paragraph.paragraph_index_id; article_id=$paragraph.article_id; title=$paragraph.title
    paragraph_id=$paragraph.paragraph_id; display_text=$paragraph.display_text; normalized_text=$paragraph.normalized_text
    function_label=$paragraph.function_label; writing_method=$paragraph.writing_method; article_types=@($paragraph.article_types)
    style_labels=@($paragraph.style_labels); value_themes=@($topics.Values); topic_entities=@($topics.Topics)
    reuse_value=$paragraph.reuse_value; text_for_embedding=$paragraph.text_for_embedding
  })
}

# Source category wins over rule keywords so a generic constraint cannot become political,
# medical, or another domain merely because its text mentions that domain.
$allowedConstraintCategories = @('fact_integrity','strong_claim','quote','scenario_boundary','medical','admissions','safety')
$allowedConstraintScopes = @('general','medical','admissions','safety')
$constraintCategoryCounts = @{}
$repairedConstraints = [Collections.Generic.List[object]]::new()
foreach ($constraint in $constraints) {
  $sourceTerm = (([string]$(if ($constraint.source_term) { $constraint.source_term } else { $constraint.term })) -replace '\s+', ' ').Trim()
  $collapsedTerm = ($sourceTerm -replace '_', '').ToLowerInvariant()
  $sourceTerm = switch ($collapsedTerm) {
    'mustnotinvent' { 'must_not_invent' }
    'strongclaimsrequiresource' { 'strong_claims_require_source' }
    'quotehandling' { 'quote_handling' }
    'scenarioboundaries' { 'scenario_boundaries' }
    default { $sourceTerm }
  }
  $rule = Normalize-Text $constraint.rule
  $category = ''
  $scope = 'general'
  switch ($sourceTerm) {
    'must_not_invent' { $category='fact_integrity' }
    'strong_claims_require_source' { $category='strong_claim' }
    'quote_handling' { $category='quote' }
    'scenario_boundaries' { $category='scenario_boundary' }
  }
  if (-not $category -and $constraint.constraint_category -in $allowedConstraintCategories) {
    $category = [string]$constraint.constraint_category
    if ($constraint.constraint_scope -in $allowedConstraintScopes) { $scope = [string]$constraint.constraint_scope }
  }
  if (-not $category) {
    $evidence = "$sourceTerm $rule"
    if ($evidence -match '医学|医疗|患者|临床|手术|眼科|救治') { $category='medical'; $scope='medical' }
    elseif ($evidence -match '招生|报名|录取|报考|考试|考生') { $category='admissions'; $scope='admissions' }
    elseif ($evidence -match '安全|预警|应急|防御|台风|避险') { $category='safety'; $scope='safety' }
    elseif ($constraint.constraint_type -eq 'quote' -or $evidence -match '引语|引用|原话') { $category='quote' }
    elseif ($constraint.constraint_type -eq 'scenario_boundary' -or $evidence -match '边界|不得用于|仅适用') { $category='scenario_boundary' }
    elseif ($constraint.constraint_type -in @('strong_claim','honor','data') -or $evidence -match '首例|首个|首次|首批|最大|最高|唯一|入选|荣誉|排名') { $category='strong_claim' }
    else { $category='fact_integrity' }
  }
  Add-Count $constraintCategoryCounts $category
  $embedding = "约束分类：$category`n适用范围：$scope`n来源项：$sourceTerm`n规则：$rule`n风险等级：$($constraint.risk_level)`n适用文章类型：$(Join-Values $constraint.applicable_article_types)"
  $repairedConstraints.Add([pscustomobject][ordered]@{
    constraint_index_id=$constraint.constraint_index_id; article_id=$constraint.article_id; source_title=$constraint.source_title
    constraint_category=$category; constraint_scope=$scope; source_term=$sourceTerm; rule=$rule
    risk_level=$constraint.risk_level; applicable_article_types=@($constraint.applicable_article_types)
    must_check=[bool]$constraint.must_check; text_for_embedding=$embedding
  })
}

# Strictly retain reusable expressions, rhetorical-device names, and writing methods.
$rhetoricalDevices = @('排比','设问','反问','比喻','拟人','对偶','引用','反复','层递','首尾呼应','借代','双关')
$writingMethodPattern = '长短句|加粗|小标题|图文|数据前置|事实前置|场景导入|价值收束|情感收束|分章节|对比|转场|叙事|结构|写法|表达|说明|呈现|铺陈|递进'
$styleRemovalCounts = @{}
$styleSeen = @{}
$repairedStyles = [Collections.Generic.List[object]]::new()
foreach ($style in $styles) {
  $phrase = Normalize-Text $style.phrase
  $reason = ''
  if (-not $phrase) { $reason='empty' }
  elseif ($phrase -match 'https?://|<!--|-->|!\[|wxfmt=|repeatedimage|caption:') { $reason='markup_or_image_residue' }
  elseif ($phrase.Length -gt 80) { $reason='fact_bound_long_text' }
  elseif ($phrase -match '^(中山大学|中大)$') { $reason='entity_only' }
  elseif ($phrase.Length -le 24 -and $articleTopicMap[[string]$style.article_id].Topics -contains $phrase) { $reason='entity_only' }

  $kind = ''
  if (-not $reason) {
    if ($style.expression_type -in @('expression_phrase','rhetorical_device','writing_method')) { $kind=[string]$style.expression_type }
    elseif ($phrase -in $rhetoricalDevices) { $kind='rhetorical_device' }
    elseif ($phrase -match $writingMethodPattern) { $kind='writing_method' }
    else { $kind='expression_phrase' }
    if ($kind -eq 'expression_phrase' -and $phrase -match '\d{2,}|\d+%|\d+年|首例|首个|首次|最大|最高|入选|获奖|发布') { $reason='fact_bound_expression' }
  }
  if ($reason) { Add-Count $styleRemovalCounts $reason; continue }
  $dedupeKey = "$($style.article_id)|$kind|$($phrase.ToLowerInvariant())"
  if ($styleSeen.ContainsKey($dedupeKey)) { Add-Count $styleRemovalCounts 'duplicate'; continue }
  $styleSeen[$dedupeKey] = $true
  $embedding = "风格标签：$($style.style_label)`n表达类别：$kind`n内容：$phrase`n使用说明：$($style.usage_note)`n适用场景：$(Join-Values $style.applicable_scenarios)`n风险提示：$(Join-Values $style.risk_notes)"
  $repairedStyles.Add([pscustomobject][ordered]@{
    style_index_id=$style.style_index_id; article_id=$style.article_id; source_title=$style.source_title
    style_label=$style.style_label; expression_type=$kind; phrase=$phrase; usage_note=$style.usage_note
    applicable_scenarios=@(Get-UniqueValues $style.applicable_scenarios); risk_notes=@(Get-UniqueValues $style.risk_notes)
    article_types=@(Get-UniqueValues $style.article_types); text_for_embedding=$embedding
  })
}

# Strong claims are detected primarily in the normalized fact. A short local quote may
# supplement it, but long paragraph quotes are excluded to prevent collateral matches.
$strongClaimPattern = '(?:(?:全球|世界|全国|国内|广东|全疆|高校).{0,8})?(?:首例|首个|首次|首批|最大|最高|唯一|率先)|典型案例|国际领先|世界领先|国内领先|填补.{0,6}空白|最高水平|重大突破|重磅发布'
$factPromotedCount = 0
$repairedFacts = [Collections.Generic.List[object]]::new()
foreach ($fact in $facts) {
  $factText = Normalize-Text $fact.fact
  $quote = Normalize-Text $fact.source_quote
  $quoteIsLocal = $quote.Length -le 160 -and ($factText.Length -eq 0 -or $quote.Length -le [Math]::Max(80, $factText.Length * 3))
  $strong = [bool]($factText -match $strongClaimPattern -or ($quoteIsLocal -and $quote -match $strongClaimPattern))
  $verify = [bool]$fact.requires_verification -or $strong
  if ($verify -and -not [bool]$fact.requires_verification) { $factPromotedCount++ }
  $riskLevel = Normalize-Text $fact.risk_level
  if (-not $riskLevel) {
    $riskLevel = switch (Normalize-Text $fact.risk) { '高' {'high'} '中' {'medium'} '低' {'low'} default {'medium'} }
  }
  if ($verify) { $riskLevel='high' }
  $embedding = "事实：$factText`n事实类型：$($fact.fact_type)`n实体：$(Join-Values $fact.entities)`n来源引文：$quote`n需核验：$verify`n风险等级：$riskLevel`n文章类型：$(Join-Values $fact.article_types)`n关键词：$(Join-Values $fact.keywords)"
  $repairedFacts.Add([pscustomobject][ordered]@{
    fact_index_id=$fact.fact_index_id; article_id=$fact.article_id; title=$fact.title; fact=$factText
    fact_type=$fact.fact_type; entities=@($fact.entities); source_paragraph_id=$fact.source_paragraph_id; source_quote=$quote
    confidence=$fact.confidence; risk=$fact.risk; risk_level=$riskLevel; requires_verification=$verify
    article_types=@($fact.article_types); keywords=@($fact.keywords); text_for_embedding=$embedding
  })
}

$paragraphTextMap = @{}
foreach ($paragraph in $repairedParagraphs) { $paragraphTextMap[[string]$paragraph.paragraph_index_id] = Normalize-Text $paragraph.normalized_text }

function Get-VisualClassification {
  param([object] $Visual)
  if ((Normalize-Text $Visual.classification_confidence) -and (Normalize-Text $Visual.classification_basis)) {
    return [pscustomobject]@{
      Type=(Normalize-Text $Visual.image_type)
      Confidence=(Normalize-Text $Visual.classification_confidence)
      Basis=([string]$Visual.classification_basis).Trim()
    }
  }
  if ((Normalize-Text $Visual.image_type) -ne '正文图片') {
    return [pscustomobject]@{ Type=(Normalize-Text $Visual.image_type); Confidence='high'; Basis='existing_type' }
  }
  $caption = Normalize-Text $Visual.caption
  $narrative = Normalize-Text $Visual.narrative_function
  $metadata = "$caption $narrative"
  $paragraphText = ((As-Array $Visual.related_paragraphs | ForEach-Object { $paragraphTextMap["$($Visual.article_id)::$_"] }) -join ' ')
  $articleTypes = Join-Values $Visual.article_types ' '
  $sources = @(
    [pscustomobject]@{ Name='caption_and_function'; Text=$metadata; Confidence='high' },
    [pscustomobject]@{ Name='related_paragraph'; Text=$paragraphText; Confidence='medium' },
    [pscustomobject]@{ Name='article_types'; Text=$articleTypes; Confidence='low' }
  )
  $rules = @(
    @('医学|医疗|患者|临床|手术|眼科|医生','医学场景图'),
    @('望远镜|设备|仪器|实验室|实验|科研平台','科研设备图'),
    @('图表|数据|统计|比例|信息图','数据图表'),
    @('历史|史料|校史|旧照|文献|抗战','历史照片'),
    @('群像|合影|团队|师生校友','群像图'),
    @('人物|肖像|教授|教师|学生|校友|医生|志愿者','人物图'),
    @('校园|建筑|校区|风景|食堂|图书馆','校园风景图'),
    @('课堂|课程|教学|培养|学习','教学场景图'),
    @('比赛|赛事|运动|全运会|火炬','赛事图'),
    @('通知|公告|报名|流程|招生|规则','通知信息图'),
    @('会议|论坛|开幕|活动|现场|仪式|采访','现场图')
  )
  foreach ($source in $sources) {
    if (-not $source.Text -or $source.Text -match '^正文图片\d*\s*(辅助呈现正文事实和现场氛围)?$') { continue }
    foreach ($rule in $rules) {
      if ($source.Text -match $rule[0]) { return [pscustomobject]@{ Type=$rule[1]; Confidence=$source.Confidence; Basis=$source.Name } }
    }
  }
  return [pscustomobject]@{ Type='正文图片'; Confidence='low'; Basis='insufficient_metadata' }
}

$visualReclassifiedCount = 0
$visualTypeCounts = @{}
$repairedVisuals = [Collections.Generic.List[object]]::new()
foreach ($visual in $visuals) {
  $classification = Get-VisualClassification $visual
  if ((Normalize-Text $visual.image_type) -eq '正文图片' -and $classification.Type -ne '正文图片') { $visualReclassifiedCount++ }
  Add-Count $visualTypeCounts $classification.Type
  $embedding = "图片类型：$($classification.Type)`n图片说明：$($visual.caption)`n位置：$($visual.position)`n叙事功能：$($visual.narrative_function)`n分类置信度：$($classification.Confidence)`n分类依据：$($classification.Basis)`n相关文章类型：$(Join-Values $visual.article_types)"
  $repairedVisuals.Add([pscustomobject][ordered]@{
    visual_index_id=$visual.visual_index_id; article_id=$visual.article_id; title=$visual.title; image_id=$visual.image_id
    image_url=$visual.image_url; image_type=$classification.Type; caption=$visual.caption; caption_source=$visual.caption_source
    position=$visual.position; narrative_function=$visual.narrative_function; related_paragraphs=@($visual.related_paragraphs)
    classification_confidence=$classification.Confidence; classification_basis=$classification.Basis
    article_types=@($visual.article_types); style_labels=@($visual.style_labels); text_for_embedding=$embedding
  })
}

function Normalize-TemplateText {
  param([string] $Value)
  return ((Normalize-Text $Value) -replace '\s*(?:→|⇒|—>|->)\s*', ' -> ' -replace '\s+', ' ').Trim()
}

function Get-TemplateClusterSignature {
  param([string] $Template)
  $stages = [Collections.Generic.List[string]]::new()
  foreach ($rawStep in ($Template -split '\s*->\s*')) {
    $step = Normalize-Text $rawStep
    $stage = if ($step -match '导入|开篇|开场|标题|前置|起点|节点|场景') { '导入' }
      elseif ($step -match '背景|问题|需求|矛盾|缘起|痛点|理念') { '背景问题' }
      elseif ($step -match '数据|案例|人物|引语|证明|支撑|效果|成果|成绩|验证|事实') { '证据' }
      elseif ($step -match '拆解|展开|机制|路径|过程|章节|列举|内容|方法|介绍') { '展开' }
      elseif ($step -match '价值|使命|贡献|意义|国家|学校') { '价值' }
      elseif ($step -match '行动|号召|召唤|愿景|未来|收束|结尾|回扣|升华') { '收束' }
      else { '展开' }
    if (-not $stages.Count -or $stages[$stages.Count - 1] -ne $stage) { $stages.Add($stage) }
  }
  return ($stages -join ' -> ')
}

$templateGroups = @{}
foreach ($template in $templates) {
  $normalized = Normalize-TemplateText $template.template
  $type = if ([string]$template.template_type) { ([string]$template.template_type).Trim() } else { 'structure' }
  $key = "$type|$($normalized.ToLowerInvariant())"
  if (-not $templateGroups.ContainsKey($key)) {
    $templateGroups[$key] = [pscustomobject]@{
      Type=$type; Template=$normalized; ArticleIds=[Collections.Generic.List[string]]::new(); Titles=[Collections.Generic.List[string]]::new()
      Applicable=[Collections.Generic.List[string]]::new(); NotApplicable=[Collections.Generic.List[string]]::new()
      RequiredFacts=[Collections.Generic.List[string]]::new(); RiskNotes=[Collections.Generic.List[string]]::new()
      ArticleTypes=[Collections.Generic.List[string]]::new(); StyleLabels=[Collections.Generic.List[string]]::new()
    }
  }
  $group = $templateGroups[$key]
  foreach ($id in As-Array $(if ($template.source_article_ids) { $template.source_article_ids } else { $template.article_id })) {
    $sourceId = ([string]$id).Trim()
    if ($sourceId) { $group.ArticleIds.Add($sourceId) }
  }
  foreach ($title in As-Array $(if ($template.source_titles) { $template.source_titles } else { $template.source_title })) { if (Normalize-Text $title) { $group.Titles.Add((Normalize-Text $title)) } }
  foreach ($pair in @(@($template.applicable_scenarios,$group.Applicable),@($template.not_applicable_scenarios,$group.NotApplicable),@($template.required_facts,$group.RequiredFacts),@($template.risk_notes,$group.RiskNotes),@($template.article_types,$group.ArticleTypes),@($template.style_labels,$group.StyleLabels))) {
    foreach ($value in As-Array $pair[0]) { if (Normalize-Text $value) { $pair[1].Add((Normalize-Text $value)) } }
  }
}

$repairedTemplates = [Collections.Generic.List[object]]::new()
foreach ($key in @($templateGroups.Keys | Sort-Object)) {
  $group = $templateGroups[$key]
  $sourceIds = @($group.ArticleIds | Where-Object { $_ } | Sort-Object -Unique)
  $sourceTitles = @(Get-SortedUniqueValues $group.Titles)
  $signature = Get-TemplateClusterSignature $group.Template
  $clusterId = "$($group.Type)_cluster_$(Get-StableHash $signature 12)"
  $values = [Collections.Generic.List[string]]::new()
  $topics = [Collections.Generic.List[string]]::new()
  foreach ($id in $sourceIds) {
    foreach ($value in As-Array $articleTopicMap[$id].Values) { $values.Add($value) }
    foreach ($topic in As-Array $articleTopicMap[$id].Topics) { $topics.Add($topic) }
  }
  $valueThemes = @(Get-SortedUniqueValues $values)
  $topicEntities = @(Get-SortedUniqueValues $topics)
  $applicableScenarios = @(Get-SortedUniqueValues $group.Applicable)
  $notApplicableScenarios = @(Get-SortedUniqueValues $group.NotApplicable)
  $requiredFacts = @(Get-SortedUniqueValues $group.RequiredFacts)
  $riskNotes = @(Get-SortedUniqueValues $group.RiskNotes)
  $articleTypes = @(Get-SortedUniqueValues $group.ArticleTypes)
  $templateStyleLabels = @(Get-SortedUniqueValues $group.StyleLabels)
  $embedding = "模板类型：$($group.Type)`n模板内容：$($group.Template)`n结构聚类：$signature`n适用场景：$(Join-Values $applicableScenarios)`n不适用场景：$(Join-Values $notApplicableScenarios)`n来源文章：$(Join-Values $sourceTitles)"
  $repairedTemplates.Add([pscustomobject][ordered]@{
    template_index_id="template_$(Get-StableHash $key 16)"; template_type=$group.Type; template=$group.Template
    cluster_id=$clusterId; cluster_signature=$signature; source_article_ids=$sourceIds; source_titles=$sourceTitles
    applicable_scenarios=$applicableScenarios; not_applicable_scenarios=$notApplicableScenarios
    required_facts=$requiredFacts; risk_notes=$riskNotes
    article_types=$articleTypes; style_labels=$templateStyleLabels
    value_themes=$valueThemes; topic_entities=$topicEntities; text_for_embedding=$embedding
  })
}

function Assert-UniqueIds {
  param([AllowNull()][object] $Records, [string] $Property, [string] $Name)
  $ids = @(As-Array $Records | ForEach-Object { [string]$_.$Property })
  if ($ids -contains '') { throw "$Name contains an empty ID." }
  if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw "$Name contains duplicate IDs." }
}

Assert-UniqueIds $repairedArticles 'article_id' 'article_index'
Assert-UniqueIds $repairedParagraphs 'paragraph_index_id' 'paragraph_index'
Assert-UniqueIds $repairedFacts 'fact_index_id' 'fact_index'
Assert-UniqueIds $repairedTemplates 'template_index_id' 'template_index'
Assert-UniqueIds $repairedStyles 'style_index_id' 'style_index'
Assert-UniqueIds $repairedVisuals 'visual_index_id' 'visual_index'
Assert-UniqueIds $repairedConstraints 'constraint_index_id' 'constraint_index'

$articleIdSet = @{}
foreach ($article in $repairedArticles) { $articleIdSet[[string]$article.article_id] = $true }
foreach ($collection in @($repairedParagraphs,$repairedFacts,$repairedStyles,$repairedVisuals,$repairedConstraints)) {
  foreach ($record in $collection) { if (-not $articleIdSet.ContainsKey([string]$record.article_id)) { throw "Dangling article_id: $($record.article_id)" } }
}
foreach ($template in $repairedTemplates) {
  foreach ($id in $template.source_article_ids) { if (-not $articleIdSet.ContainsKey([string]$id)) { throw "Dangling template source_article_id: $id" } }
}
$paragraphIdSet = @{}
foreach ($paragraph in $repairedParagraphs) { $paragraphIdSet[[string]$paragraph.paragraph_index_id] = $true }
foreach ($fact in $repairedFacts) {
  if (-not $paragraphIdSet.ContainsKey("$($fact.article_id)::$($fact.source_paragraph_id)")) { throw "Dangling fact paragraph: $($fact.fact_index_id)" }
}
foreach ($visual in $repairedVisuals) { if (-not (Normalize-Text $visual.image_url)) { throw "Visual missing image_url: $($visual.visual_index_id)" } }
foreach ($constraint in $repairedConstraints) {
  if ($constraint.constraint_category -notin $allowedConstraintCategories) { throw "Invalid constraint category: $($constraint.constraint_category)" }
  if ($constraint.constraint_scope -notin $allowedConstraintScopes) { throw "Invalid constraint scope: $($constraint.constraint_scope)" }
  if ($constraint.source_term -eq 'must_not_invent' -and ($constraint.constraint_category -ne 'fact_integrity' -or $constraint.constraint_scope -ne 'general')) { throw "Generic must_not_invent misclassified: $($constraint.constraint_index_id)" }
}
foreach ($style in $repairedStyles) {
  if ($style.expression_type -notin @('expression_phrase','rhetorical_device','writing_method')) { throw "Invalid style type: $($style.style_index_id)" }
  if ((Normalize-Text $style.phrase).Length -gt 80 -or $style.phrase -match 'https?://|<!--|!\[') { throw "Style noise remains: $($style.style_index_id)" }
}
if (@($repairedTemplates.template | Select-Object -Unique).Count -ne $repairedTemplates.Count) { throw 'Template deduplication failed.' }

$actionStats = if ($alreadyRepaired -and $previousReport -and $previousReport.repair_actions) {
  $previousReport.repair_actions
} else {
  [pscustomobject][ordered]@{
    themes_migrated_to_topics=$topicMigrationCount
    style_records_removed=($styles.Count - $repairedStyles.Count)
    style_removal_reasons=[pscustomobject][ordered]@{
      empty=[int]$styleRemovalCounts['empty']; markup_or_image_residue=[int]$styleRemovalCounts['markup_or_image_residue']
      fact_bound_long_text=[int]$styleRemovalCounts['fact_bound_long_text']; entity_only=[int]$styleRemovalCounts['entity_only']
      fact_bound_expression=[int]$styleRemovalCounts['fact_bound_expression']; duplicate=[int]$styleRemovalCounts['duplicate']
    }
    facts_promoted_to_verification=$factPromotedCount
    visuals_reclassified=$visualReclassifiedCount
    templates_removed_as_duplicates=($templates.Count - $repairedTemplates.Count)
  }
}

$repairReport = [pscustomobject][ordered]@{
  repair_version=$repairVersion
  source_article_count=$repairedArticles.Count
  repair_actions=$actionStats
  final_counts=[pscustomobject][ordered]@{
    article_index=$repairedArticles.Count; paragraph_index=$repairedParagraphs.Count; fact_index=$repairedFacts.Count
    template_index=$repairedTemplates.Count; style_index=$repairedStyles.Count; visual_index=$repairedVisuals.Count
    constraint_index=$repairedConstraints.Count; unresolved_body_images=@($repairedVisuals | Where-Object image_type -eq '正文图片').Count
  }
  constraint_categories=[pscustomobject][ordered]@{
    fact_integrity=[int]$constraintCategoryCounts['fact_integrity']; strong_claim=[int]$constraintCategoryCounts['strong_claim']
    quote=[int]$constraintCategoryCounts['quote']; scenario_boundary=[int]$constraintCategoryCounts['scenario_boundary']
    medical=[int]$constraintCategoryCounts['medical']; admissions=[int]$constraintCategoryCounts['admissions']; safety=[int]$constraintCategoryCounts['safety']
  }
  validation=[pscustomobject][ordered]@{
    jsonl_parse='passed'; unique_ids='passed'; foreign_keys='passed'; fact_paragraph_links='passed'
    visual_urls='passed'; controlled_taxonomies='passed'; theme_topic_conservation='passed'; template_deduplication='passed'
  }
}

$repairedManifest = [pscustomobject][ordered]@{
  version=$manifest.version; repair_version=$repairVersion; generated_at=$manifest.generated_at
  source_article_count=$manifest.source_article_count; article_index_count=$repairedArticles.Count
  paragraph_index_count=$repairedParagraphs.Count; fact_index_count=$repairedFacts.Count
  template_index_count=$repairedTemplates.Count; style_index_count=$repairedStyles.Count
  visual_index_count=$repairedVisuals.Count; constraint_index_count=$repairedConstraints.Count
  ready_article_count=$manifest.ready_article_count; review_article_count=$manifest.review_article_count
  excluded_article_count=$manifest.excluded_article_count
}

Write-Output ('INDEX REPAIR {0} article={1} paragraph={2} fact={3} template={4} style={5} visual={6} constraint={7} unresolved_body={8}' -f
  $(if ($DryRun) {'DRY RUN PASS'} else {'PASS'}),$repairedArticles.Count,$repairedParagraphs.Count,$repairedFacts.Count,
  $repairedTemplates.Count,$repairedStyles.Count,$repairedVisuals.Count,$repairedConstraints.Count,
  @($repairedVisuals | Where-Object image_type -eq '正文图片').Count)

if ($DryRun) { return }

$tempDir = Join-Path $indexDir ".repair_tmp_$PID"
if (Test-Path -LiteralPath $tempDir) { Remove-Item -Recurse -Force -LiteralPath $tempDir }
[IO.Directory]::CreateDirectory($tempDir) | Out-Null
try {
  $outputs = [ordered]@{
    'article_index.jsonl'=$repairedArticles; 'paragraph_index.jsonl'=$repairedParagraphs; 'fact_index.jsonl'=$repairedFacts
    'template_index.jsonl'=$repairedTemplates; 'style_index.jsonl'=$repairedStyles; 'visual_index.jsonl'=$repairedVisuals
    'constraint_index.jsonl'=$repairedConstraints
  }
  foreach ($entry in $outputs.GetEnumerator()) { Write-JsonLines (Join-Path $tempDir $entry.Key) $entry.Value }
  [IO.File]::WriteAllText((Join-Path $tempDir 'index_manifest.json'), ($repairedManifest | ConvertTo-Json -Depth 20), $utf8NoBom)
  [IO.File]::WriteAllText((Join-Path $tempDir 'index_repair_report.json'), ($repairReport | ConvertTo-Json -Depth 20), $utf8NoBom)

  foreach ($entry in $outputs.GetEnumerator()) {
    $parsedCount = @([IO.File]::ReadLines((Join-Path $tempDir $entry.Key)) | ForEach-Object { $_ | ConvertFrom-Json }).Count
    if ($parsedCount -ne @(As-Array $entry.Value).Count) { throw "Written count mismatch: $($entry.Key)" }
  }
  foreach ($name in @($outputs.Keys) + @('index_manifest.json','index_repair_report.json')) {
    Move-Item -Force -LiteralPath (Join-Path $tempDir $name) -Destination (Join-Path $indexDir $name)
  }
}
finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -Recurse -Force -LiteralPath $tempDir }
}
