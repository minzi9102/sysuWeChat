# 中山大学微信公众号知识库

本仓库用于整理、分析和索引中山大学微信公众号文章，将原始 Markdown 转换为可追溯的结构化写作素材与 JSONL 检索索引。主要能力包括文章内容模式识别、正文去噪、段落与事实抽取、写作风格和模板分析、图片信息整理，以及面向检索的索引构建与修复。

## 当前数据概况

仓库当前包含 240 篇原始 Markdown。已完成的产物包括：

- 45 篇文本型文章的清洗 Markdown、分析文档和结构化 JSON；
- 17 篇长图或粘贴图片型文章的跳过 marker；
- 45 篇文本型文章的多维检索索引。

当前修复后索引规模以 [`indexed_data/index_manifest.json`](indexed_data/index_manifest.json) 为准：

| 索引 | 记录数 | 用途 |
| --- | ---: | --- |
| article | 45 | 文章级主题、类型、结构和传播目标检索 |
| paragraph | 918 | 段落功能、写法和正文片段检索 |
| fact | 825 | 带原文回链、风险和核验标记的事实检索 |
| template | 44 | 去重后的结构模板及模板聚类 |
| style | 713 | 可复用表达、修辞手法和写作方法检索 |
| visual | 816 | 图片类型、说明、叙事功能及来源链接检索 |
| constraint | 712 | 事实完整性、强断言、引用和场景边界约束 |

## 核心功能

### 新稿写作

[`新稿写作流程`](docs/writing-workflow.md) 说明如何用活动原始材料和 context pack 完成公众号新稿，包括任务分类、参考选择、事实清单、起草、风格改写、风险校验与发布检查。

写作时必须遵守事实边界：参考库只提供结构、语气、句式、图文节奏和风险约束；本次稿件的人名、时间、地点、数字、项目、直接引语和结论只能来自用户提供的活动材料。

### 文章分析

[`sysu-wechat-article-analysis`](skills/sysu-wechat-article-analysis/SKILL.md) 负责处理单篇公众号文章：

- 区分文本、长图和粘贴图片内容；
- 清除推荐阅读、页脚、交互残留等噪音；
- 为正文段落和图片生成连续锚点；
- 抽取可回链到原段落的事实；
- 分析段落功能、文章结构、价值主题、主题实体和写作风格；
- 生成标题、开头、结构、过渡、结尾等可复用模板；
- 标记首例、首次、最大、最高等需要核验的强断言。

文本型文章生成三类产物：清洗 Markdown、分析 Markdown 和结构化 JSON。图片主导型文章只生成 marker，不推断图片中的正文、事实或模板。

### 检索索引

[`sysu-wechat-index-builder`](skills/sysu-wechat-index-builder/SKILL.md) 负责校验完整的文章产物并生成多类 JSONL 索引。索引记录包含稳定 ID、文章来源、检索字段和 `text_for_embedding`，可用于关键词检索、向量化或后续知识库导入。

[`make-writing-context.ps1`](scripts/make-writing-context.ps1) 提供面向新稿准备的轻量检索入口。脚本直接按文章类型和关键词筛选现有 JSONL，不依赖向量数据库、网页 UI、多 agent 流水线或自动评分模型；它只负责把可用参考材料整理成紧凑的 context pack，不负责自动写作。

索引修复是独立的构建后步骤，主要处理旧分析产物中的字段和分类问题：

- 重构约束分类与适用范围；
- 删除风格索引中的实体词、长事实段和图片残留；
- 将混入价值主题的实体迁移到 `topic_entities`；
- 对事实执行强断言二次检测；
- 根据文本元数据细分通用“正文图片”；
- 全局去重结构模板并聚合来源、生成稳定聚类。

修复规则和统计结果见 [`indexed_data/index_repair_report.json`](indexed_data/index_repair_report.json)。

## 仓库结构

```text
.
├── md/                         # 原始公众号 Markdown，主要证据来源
├── 中山大学/                   # 原始资料的参考副本，不作为分析主证据
├── clean_md/                   # 去噪正文及段落、图片锚点
├── article_analysis_md/        # 面向人工阅读的分析报告
├── article_json/               # 面向程序处理的结构化分析结果
├── article_markers/            # 长图或粘贴图片文章的跳过记录
├── indexed_data/               # 生成的检索索引、质量报告和 manifest
├── docs/
│   └── writing-workflow.md      # 使用索引辅助新稿写作的一页流程
├── skills/
│   ├── sysu-wechat-article-analysis/  # 文章分析规范、schema、检查表和脚本
│   └── sysu-wechat-index-builder/     # 索引构建、修复和验证流程
├── scripts/
│   ├── build-indexes.ps1       # 索引构建兼容入口
│   ├── lint-draft-style.ps1     # 新稿风格风险轻量提醒
│   ├── list-article-types.ps1   # 列出索引中真实文章类型
│   ├── make-writing-context.ps1 # 生成新稿参考 context pack
│   └── repair-indexes.ps1      # 旧索引修复兼容入口
├── AGENTS.md                   # 仓库协作、提交和环境规则
└── README.md
```

同一篇文本型文章在 `md`、`clean_md`、`article_analysis_md` 和 `article_json` 中使用相同的 `[时间戳]标题` 基名，便于跨产物追踪。

## 数据处理流程

1. 从 `md/` 读取原始文章并识别内容模式。
2. 图片主导型文章写入 `article_markers/` 后停止处理。
3. 文本型文章清除正文外噪音，写入 `clean_md/`。
4. 根据清洗正文生成分析 Markdown 和结构化 JSON。
5. 校验文章三件套、锚点、事实引文和图片统计。
6. 构建文章、段落、事实、模板、风格、视觉和约束索引。
7. 对 legacy 索引执行独立修复，得到最终 `indexed_data/`。
8. 写作前按需从修复后的索引生成 context pack；该文件是可重复生成的派生产物，不属于索引构建结果。

语义判断在文章分析阶段完成；索引阶段只负责字段归一化、检索友好化和确定性兜底，不凭空补造文章事实或写作语义。

## 常用命令

以下命令均在仓库根目录的 PowerShell 中执行。

### 查看可用文章类型

```powershell
./scripts/list-article-types.ps1 -Root .
```

可用 `Filter` 先做类型名称的模糊筛选：

```powershell
./scripts/list-article-types.ps1 -Root . -Filter 'AI'
./scripts/list-article-types.ps1 -Root . -Filter '青年'
```

建议先查看 `article_index.jsonl` 中真实存在的文章类型及数量，再填写 `make-writing-context.ps1` 的 `ArticleTypes` 参数，避免用不存在或拼写不一致的类型名检索。

### 生成新稿写作参考

```powershell
./scripts/make-writing-context.ps1 `
  -Root . `
  -ArticleTypes '人工智能类,科创育人类,青年成长类,校园纪实类' `
  -Keywords 'AI,学生,项目,实践,创新,培训' `
  -Output 'writing_context/vibecoding.context.json'
```

`ArticleTypes` 和 `Keywords` 均接受英文或中文逗号分隔的值，并自动去除空白和重复项。文章采用宽召回：命中任一类型或关键词即可进入候选，再依次按类型命中数、关键词命中数、发布时间和文章 ID 确定顺序。

输出 JSON 包含：

- `reference_articles`：最多 5 篇参考文章；
- `structure_templates`：最多 5 个结构模板；
- `reusable_styles`：最多 20 条表达、写作方法和修辞手法；
- `visual_patterns`：最多 10 类按图片类型和叙事功能聚合的图文模式，不包含图片 URL；
- `risk_checklist`：最多 20 条去重后的高优先级风险约束。

模板、风格、视觉和约束优先取自入选文章，不足时再按命中的文章类型补足。生成后按 [`新稿写作流程`](docs/writing-workflow.md) 使用这些材料；context pack 只能作为结构、风格和风险参考，不得作为本次活动的事实来源。

### 检查新稿风格

```powershell
./scripts/lint-draft-style.ps1 -Path 'drafts/current.md'
```

脚本逐行提示先否定后肯定句式、空泛强调词和需要证据的强断言。命中只表示需要作者复核，不会自动改写草稿或返回失败。

### 识别单篇文章模式

```powershell
./skills/sysu-wechat-article-analysis/scripts/classify-article.ps1 `
  -SourcePath 'md/[时间戳]文章标题.md'
```

### 校验单篇分析产物

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 `
  -Root . `
  -ArticleBaseName '[时间戳]文章标题'
```

校验所有 legacy 分析产物：

```powershell
./skills/sysu-wechat-article-analysis/scripts/validate-artifacts.ps1 -Root . -All
```

### 构建索引

```powershell
./scripts/build-indexes.ps1 -Root .
```

构建成功时输出 `INDEX BUILD PASS`。不要直接手工修改 `indexed_data/*.jsonl`；应修改来源产物或构建逻辑后重新生成。

### 修复 legacy 索引

先预览，不写文件：

```powershell
./scripts/repair-indexes.ps1 -Root . -DryRun
```

确认后执行原位修复：

```powershell
./scripts/repair-indexes.ps1 -Root .
```

索引构建器不会自动调用 repair。每次重新运行 builder 后，如仍使用当前 legacy 文章 JSON，需要再次手动运行 repair。

## 索引文件说明

`indexed_data/` 中的主要文件如下：

- `quality_report.jsonl`：每篇文章的解析、三件套完整性、schema 和噪音检查结果；
- `article_index.jsonl`：文章级摘要、类型、主题、实体、结构和风格；
- `paragraph_index.jsonl`：段落正文、功能标签、写作方法和复用价值；
- `fact_index.jsonl`：事实、实体、来源段落、来源引文、置信度和核验风险；
- `template_index.jsonl`：去重模板、聚类签名、适用场景和聚合来源；
- `style_index.jsonl`：表达短语、修辞手法和写作方法；
- `visual_index.jsonl`：图片 URL、分类、图注、叙事功能和分类依据；
- `constraint_index.jsonl`：约束分类、范围、规则和风险等级；
- `index_manifest.json`：索引版本、生成时间和各索引记录数；
- `index_repair_report.json`：索引修复动作、最终规模和验证结果。

JSONL 文件每行都是一个独立 JSON 对象，便于流式读取和增量导入。各子索引通过 `article_id` 或模板的 `source_article_ids` 回链到文章索引；事实还通过 `source_paragraph_id` 回链到段落。

## 质量与维护约定

- `md/` 是文章分析的主要事实来源，`中山大学/` 只作参考。
- 图片主导型文章不得从图片中臆测正文、事实、图注或模板。
- 每条事实必须保留段落级 `source_quote`，强断言必须标记核验风险。
- `value_themes` 只表达抽象价值，人物、机构、项目和设备进入 `topic_entities`。
- 全量构建要求 `review_article_count` 和 `excluded_article_count` 均为 0。
- 修复脚本必须幂等；连续执行两次应产生逐字节一致的结果。
- 开始修改前请先阅读 [`AGENTS.md`](AGENTS.md)，遵守 Git 历史、虚拟环境、微提交和完成通知规则。

本仓库当前仍包含尚未完成结构化分析的原始文章。新增文章时应遵循最新分析 schema；当前索引修复脚本只针对已有 legacy 索引，不能替代新文章的语义分析。
