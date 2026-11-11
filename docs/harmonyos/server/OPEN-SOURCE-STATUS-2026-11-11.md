# 服务端源码公开状态

本次通过 `gh repo view` 和远端分支目录核验。公开源码与生产部署是两件事，不表示 ECS 正在运行最新提交。

| 项目 | 公开位置 | 许可/状态 |
| --- | --- | --- |
| 星象仪网站和运维 | https://github.com/joinother/stellarium/tree/ohos-master/deploy | 仓库公开，根许可 GPL-2.0；文件自身许可证及第三方资源声明仍适用 |
| TLE 镜像抓取器 | `deploy/tle-mirror/` | 旧版本已在远端；本轮抓取安全和回归测试随备份 `edcfdd7a77` 推送，未据此宣称生产部署 |
| 内容通知服务契约 | `deploy/content-service/contracts.mjs` | 随 `edcfdd7a77` 公开；是协议/校验模块，不是已运行的完整 Push 服务 |
| 今夜星天气服务端 | https://github.com/joinother/nightwindow/tree/main/server | 仓库公开；根目录 GPL-3.0，**server/LICENSE 单独为 AGPL-3.0**；本轮服务端六文件备份为 `6718ad824ceab72580d69a1f7ebef143a543e3ad` |
| 星象仪仓库内旧天气 API | `deploy/server/nightwindow-api/` | 已在远端，属于另一份已有代码；不要与今夜星当前 server 目录或生产进程混为一谈 |

本次备份不包含签名私钥、证书私钥容器、Profile 二进制、生产邮件授权码、云凭证、用户数据库或安装包。提交前对新增/修改的暂存文件进行了常见密钥模式检查，但不将模式扫描宣称为完整安全审计。

今夜星备份合并了远端新增调用量统计，最终 13/13 测试通过、远端 SHA 一致。未部署；调用量统计不等于每日费用硬限额，跨实例限流、上游 429 退避及 systemd/nginx 迁移验证仍是后续工作。
