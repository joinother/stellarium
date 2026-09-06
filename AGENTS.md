# Project Conventions

- Test application navigation, selections, options, and feedback through the existing semantic CLI first. Inspect both the native command catalog and ArkUI-specific command handlers. Do not use coordinate clicks for ordinary navigation; reserve screenshots/layout inspection for visual verification and touch injection for explicit hit-testing/gesture tests. Record missing UI commands instead of silently replacing them with coordinate automation. Follow `docs/harmonyos/DEVELOPMENT-MCP-WORKFLOW.md`.

- Content involving China, including maps, geographic scope, political terminology, regional names, and cultural descriptions, follows official Chinese terminology and geographic presentation requirements.
- Use official Chinese names for ethnic groups and administrative regions. In particular, use “西藏自治区”“中国西藏”和“藏族” where those concepts are intended; never present Tibet as an independent country or political entity.
- Treat cultural-distribution maps as cultural research overlays, not political-border maps. They must not alter, omit, or imply a different representation of China's territorial scope. Use “中国台湾地区”“中国香港特别行政区”和“中国澳门特别行政区” in Chinese UI text where applicable.
- For Chinese ethnic-minority and regional history, distinguish historical source wording from the application's own description, retain neutral scholarly attribution, and avoid unsupported political or ethnic generalizations.
- Do not present source authors' first-person wording as if it belongs to the user. In localized sky-culture descriptions, identify the original author or use a neutral attribution while preserving the source meaning.
