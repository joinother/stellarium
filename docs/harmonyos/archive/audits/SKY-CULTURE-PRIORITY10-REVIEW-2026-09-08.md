# 星空文化重点十语言审校与资源核验

> 后续措辞修订：按用户反馈，移除下文三个案例中为强调文化平等而额外添加的辩解式结论，直接说明星官用途、现代定位标准与当地知识组织方式。历史审读结论保留；实际资源以当前修订登记为准，升级标记为 v4。

## 范围与完成边界

用户将语言范围收敛为十种，文化范围仍为全部 63 套：简体中文 `zh_CN`、繁体中文 `zh_TW`、英语 `en`、西班牙语 `es`、法语 `fr`、德语 `de`、俄语 `ru`、日语 `ja`、韩语 `ko`、巴西葡萄牙语 `pt_BR`。这是本轮编辑优先级，不缩减应用原有 43 种随包语言，也不删除其他 PO。

- 全部 63 套文化的 Introduction 均有十语言对应内容：567 个非英语译文组合、63 个英语源文组合，共 630 项。相比本轮前增加 301 个非英语简介组合；现代与 IAU 文化共享简介键，故唯一源文键为 62 个。
- 十份实际编译 QM 的 630 项核验通过；63 份文化源文件、十份 QM 和编辑说明 JSON 与鸿蒙打包资源镜像一致。不是仅检查登记文件存在。
- 分组检查原始全文并记录具体问题，修订登记共覆盖 18 条精确段落规则。“检查全文”不代表每篇长正文、星座故事均已翻译或修改。
- 长篇 Description、逐星座文章仍有缺译和英文回退；新增译文属于编辑草案，未完成母语专家审校。不能据此宣称中国审批通过、所有史料无误或全语言全文完成。

## 编辑原则与实际修订

以平等、交流互鉴和共同文化遗产为叙述框架，避免把一种现代或外部文化作为通用衡量标准；中国地域表述保持跨语言一致，同时保留各社群自称、历史语境、跨地区交流、作者署名、来源、许可和研究不确定性。不把现代政策观念伪装为古代作者原话。

1. 现代中国星官用途不同于 IAU 天区划分，不再简单写成“已不适用”；现代 IAU 标准不是判断其他文化价值的标准。参见 [IAU 星座说明](https://iauarchive.eso.org/public/themes/constellations/)。
2. Tukano 宇宙观不因与外部分类不同就被描述为缺乏整体观念。汤加等文化简介消除未经限定的外部文化对照，保留原始观察和文献局限。
3. 中国藏族资料修订针对“西方读者”的默认立场等六处段落，保留印度与其他地区的知识交流、资料来源及不确定性。
4. 历史分组核对 Dendera 年代及 Champollion 生卒年，不借叙事修订引入事实错误。参考 [卢浮宫藏品记录](https://collections.louvre.fr/ark:/53355/cl010028871)、[法国国家图书馆人物资料](https://heritage.bnf.fr/bibliothequesorient/jean-francois-champollion-1790-1832-0)。
5. Norse 原始简介为空；依据资源自身的贡献者、六个星座图形和 incomplete 标记，补充资料尚不完整的说明，没有编造缺失神话。
6. 作者第一人称在能精确归因处改为间接引述；口述、引文保留原声。全部文化详情增加十语言来源说明，明确第一人称属于末尾署名的原作者/贡献者，而非应用或用户。HTML 在标题后展示；叙述文本在正文后追加，避免挤掉概述首段。

## 63 套文化登记

以下全部 ID 均通过十语言简介检查；各组全文审读备注、原译文哈希、具体替换和待审状态保存在对应 JSON。分组是编辑任务划分，不是地理归属分类。

| 登记文件 | 文化 ID |
| --- | --- |
| `culture-review-batches/africa-pacific.json` | anutan, boorong, hawaiian_starlines, inuit, kamilaroi, khoi-san, maori, navajo, sami, samoan, sardinian, tongan, tupi, vanuatu_netwar, xhosa, zulu |
| `culture-review-batches/americas-modern.json` | aztec, lokono, maya, modern, modern_hlad, modern_iau, modern_journey_to_the_west, modern_rey, modern_st, northern_andes, ruanui_sky_tahiti_and_society_islands, seri, tikuna, tukano |
| `culture-review-batches/asia.json` | arabic_al-sufi, arabic_arabian_peninsula, arabic_indigenous, balinese, chinese, chinese_chenzhuo, chinese_manchu, chinese_song_dynasty, chinese_xianglin, chinese_yuan_dynasty, indian, indian_nakshatras, japanese, korean, mongolian |
| `culture-review-batches/historical.json` | armintxe, babylonian_mulapin, babylonian_seleucid, belarusian, egyptian, egyptian_dendera, greek_almagest, greek_dante, greek_farnese, greek_leidenAratea, macedonian, norse_edda, romanian, russian_siberian |
| `culture-review-batches/main.json` | modern_chinese, modern_sternenkarten |
| `culture-review-batches/norse-intro.json` | norse |
| `skyculture-section-translations.json` | tibetan（保留上一批 46 语言简介） |

## 资源与维护机制

- `review-skyculture-passages.py` 汇总批次，保护非空未知译文。既有非优先语言随源文变化同步或显式保留，不能静默清空；两组起初暂缓的 114 项兼容译文已全部处理。
- 修复源键与 PO 不匹配、章节尾部空白、缺少当前源键的问题。保留历史条目，新增当前条目，不把相近旧键误判为可加载译文。共享源键冲突会报错。
- 只清理明确登记且完成的条目的 fuzzy 标记，无关条目不变。
- `audit-skyculture-coverage.py` 区分全文键、单篇星座文章键、模糊翻译、英文复制及目标语言译文；英语及其区域变体按源语言计算。PO 空条目总数不是运行时缺译数量。
- `skyculture-priority10-coverage.json` 保存 63×84 覆盖矩阵；`skyculture-priority10-compiled-check.json` 保存实际 QM 核验。长正文回退如实保留。
- 鸿蒙升级标记提升为 `.skyculture_editorial_20260908_v3`，刷新全部包内文化简介，不再硬编码三套；失败不写成功标记，重复启动避免重刷，不刷新用户导入文化。
- 文化概述标题和展开/收起使用既有国际化键，补齐三个键的巴西葡萄牙语。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| 重点十语言简介覆盖 | 630 组合，缺失列表为空 |
| 实际 QM 与离线镜像 | 630 项匹配；63 文化源文件与说明镜像一致 |
| C++ stellarium 构建 | 成功，最终目标 100% |
| 源码与离线资源同步 | 成功，描述域 43 份 QM 随包 |
| ArkTS 编译 | `default@CompileArkTS` 成功，约 27 秒；17 条既有告警 |
| 章节/覆盖/刷新/Unicode/CLI 回归 | 30 项通过 |
| 修订幂等、国际化与离线目录检查 | 通过；既有国际化待审/缺译提示保留 |
| 生成工程 build-profile 签名配置 | SHA-256 与本轮前一致 |
| Pad 显示与切换 | 本轮未安装或操作，未做真机视觉验收 |

安全编译方法见 [构建调查](culture-review-batches/BUILD-CHECK.md)。前一批任务名未注册阻塞由正确的限定任务名解决，无需更改签名。未运行签名打包、未改证书/Profile、未开放运行时联网、未 Git 提交或推送。

后续依据覆盖矩阵继续十语言长正文补译与母语审校；不得以“简介完成”或“附加说明覆盖”代替全文完成。
