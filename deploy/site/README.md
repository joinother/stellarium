# 站点根目录附加文件

这些文件不属于构建产物，但必须出现在站点根目录：

| 文件 | 作用 |
|---|---|
| robots.txt | 允许抓取，禁止 /status/，声明 sitemap 位置 |
| sitemap.xml | 列出对外页面，供搜索引擎发现 |
| favicon.ico | 浏览器标签页图标（由 1024 像素 app-icon 生成 16/32/48/64 多尺寸） |

服务器上对应位置是 `/srv/skyinstrument/seo/`，
`skyinstrument-publish` 每次发布时会把这些文件覆盖进新版本目录，
避免发布后被冲掉。修改后需同步到服务器：

```bash
scp deploy/site/robots.txt deploy/site/sitemap.xml deploy/site/favicon.ico \
    root@<服务器>:/srv/skyinstrument/seo/
```
