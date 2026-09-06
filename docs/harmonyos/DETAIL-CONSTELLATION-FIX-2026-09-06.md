# 星体详情星座名称修复

详情接口此前直接将 iauConstellation 三字母缩写赋给 constellation。现改为 ConstellationMgr::getIAUconstellationName 的当前语言全名，复用上游 IAU constellation name 翻译域，不受当前天空文化的星官命名影响。原始缩写通过 constellationAbbreviation 保留；无法匹配时回退原缩写。

验证：C++ stellarium 目标构建成功，官方语言资源审计通过，生成工程源码与原生库已同步，git diff --check 通过。未重新生成 HAP 或安装到设备；本轮无真机显示验证。签名配置未修改。
