# 域名审核期间的服务器准备

日期：2026-09-07。此文件不含密码、云 AK/SK、会话令牌或 APP 签名材料。

## 边界与部署

上海 ECS，经济型 e，2 核/2 GiB/40 GiB，固定公网带宽 3 Mbps，Alibaba Cloud Linux 3，包年到期 2027-09-07，手动续费。

使用已获用户授权的 Workbench 官方服务关联角色进入 Shell；不新增 SSH 密钥、不改密码、不关闭 SELinux、不修改安全组。确认已有服务后，仅新机器运行 `sudo bash scripts/prepare-resource-server.sh --apply`。脚本遇到既有项目目录/服务会拒绝覆盖，失败后先查日志，不盲目重跑或删除用户数据。

- 使用系统现有软件源安装 Nginx/curl/tar，不安装数据库、Docker、宝塔或付费扩展。
- 独立 systemd 服务 `skyinstrument-resources`，以无登录服务用户 nginx 运行，只有 `/run/skyinstrument` 可写。
- Nginx 独立配置 `/etc/skyinstrument/nginx.conf`，不改发行版默认配置、不启动默认 nginx 服务。
- **只监听服务器自身 `127.0.0.1:8080`**；`/healthz` 返回准备中，其他路径 404。没有公网网站或资源下载入口。
- `/srv/skyinstrument/staging` 为 root 私有暂存；`releases` 为后续审核后的版本目录，当前为空，不映射到 HTTP。
- 访问日志关闭，错误日志进入系统 journal；公网开放前须单独审核日志合规、留存和容量。
- `/var/backups/skyinstrument` 保存一次配置压缩包与 SHA-256。只是同机恢复点，不是异地灾备，也没有购买云快照或启用定时备份。

## 检查与恢复

```sh
systemctl status skyinstrument-resources --no-pager
journalctl -u skyinstrument-resources -n 50 --no-pager
curl --fail http://127.0.0.1:8080/healthz
ss -lntp
```

停止准备服务：`sudo systemctl disable --now skyinstrument-resources`，不会删除备份或改动 SSH。配置恢复先对指定备份执行 `sha256sum -c` 与 `tar -tzf`，解压到独立临时目录审阅，再恢复必要文件并测试 Nginx 配置，不自动覆盖整机。

## 上线前仍需完成

1. 域名实名认证/审核与 APP 备案、实际服务范围、隐私政策和备案展示；域名审核通过不等于 APP 备案通过。
2. 核验账号和服务器安全设置、SSH 入口范围；任何新建管理凭据、开放安全组和公网监听需用户确认。
3. 确定 API/资源域名与 DNS，再办理可信 HTTPS 证书及续期测试；没有域名时不生成用于正式上线的自签证书。
4. 资源许可、当前 TLE 清单哈希不匹配、独立资源签名与客户端校验、不可变发布/回滚均须完成，不能先公开目录。
5. 大资源后续评估 OSS/CDN。3 Mbps 理论上限约 0.375 MB/s，由所有下载共享，不适合大量并发高清包；不因此降画质。
6. 配置异地备份与恢复演练、磁盘/可用性告警及留存策略，按实际费用单独确认。服务器不定时回源，APP 仍为离线版本。

## 官方依据

- [阿里云 Workbench 与服务关联角色](https://help.aliyun.com/zh/ecs/user-guide/workbench-overview/)
- [Nginx 配置与校验](https://nginx.org/en/docs/beginners_guide.html)
- [Nginx listen 地址范围](https://nginx.org/en/docs/http/ngx_http_core_module.html#listen)

## 实际验证

2026-09-07 已在目标服务器执行，部署退出码 0。最终脚本 SHA-256 为 `b82a2f4fd57696400df3513daf147598fef503f7dc7282c6818a8b9d3cb9ad5c`，本机与远端一致。

- Nginx 1.24.0（阿里云发行版包）安装成功；依赖处理升级了 curl/libcurl，未全量更新系统或重启服务器。
- 独立服务 enabled/active；重启测试退出码 0，默认 nginx 服务 inactive/disabled。
- GET `/healthz` 返回 200、`status=staging`、`publicService=false`；POST 返回 405；根路径 404。
- `ss -lntp` 只新增 `127.0.0.1:8080`；没有 80/443/公网 8080。已有 SSH 保持不变，未核验云安全组具体规则，不能宣称整机已完成安全加固。
- 主/工作进程均为 nginx 用户，不能写配置；测试时服务占用 1,359,872 字节约 1.30 MiB，NRestarts=0（瞬时样本，不代表负载测试）。
- 时间同步 `NTPSynchronized=yes`；SELinux 当前 Disabled，原有状态保持未变，公网上线前须另行评估，不擅自启用导致重启或服务中断。
- 最终配置备份 `config-20260907T103506Z-verified.tar.gz` 的 SHA-256 校验与隔离目录解压后的逐文件 cmp 均通过。没有购买快照或异地备份，未做整机重启测试。

## Workbench CLI 与官方 Skill

本机已安装 `/Users/jiexuanyang/.local/bin/workbench`，版本 1.0.1（86c0aff），现有 PATH 能找到，不改 shell 配置、不占用 Homebrew 管理目录。安装包 SHA-256 `bffb260723fd970e23278cc578535148bda17b17ff6788ce72e9781596525e2d` 与官方校验清单一致；直接安装已校验二进制，没有执行安装脚本中的重新签名或移除隔离属性步骤。

用户提供 [阿里云官方 Skill](https://skills.aliyun.com/skills/alibabacloud-workbench-cli)，已检查对应官方仓库的 `skills/developertools/solutions/alibabacloud-workbench-cli/SKILL.md` 和 `references/ram-policies.md`。固定源码提交 `1f409b578d95092382b595402ea70e79b279742f`，不安装整个云技能集合。

官方 Skill 已通过 Codex 技能安装器装入 `/Users/jiexuanyang/.codex/skills/alibabacloud-workbench-cli`，下一轮可加载。适合部署、状态、日志和文件传输；不是登录凭据，也不代替本应用业务 CLI。CLI 安装、version/help 通过，实际 `exec` 尝试以退出码 4 返回未配置凭据，**远程 CLI 尚未打通**；本轮服务器部署和验证使用已授权 Workbench 网页 Shell。

后续工作流：

1. 优先 Workbench CLI 的显式实例 ID、上海地域和 JSON 输出；命令参数以已装版本 `--help` 为准。区分 CLI 错误 `code` 与远端 `exit_code`，两者均不得忽略。
2. 用户本机交互配置最小权限 RAM/STS 凭据；不得读取浏览器 Cookie/会话令牌来绕过凭据配置，不索要聊天中的 AK/SK，不运行会展示凭据的 `config get`。新建用户、角色、密钥和授权必须另行确认。
3. 官方 Skill 的全局通配权限不能直接照抄。Skill 与产品文档对 `ChatMessages`、实例 ARN 的说明存在差异，先按每个 API 的授权表核实后制定单实例策略，并做允许/拒绝验证；不以“官方最小权限”代替实际收敛。
4. Skill 中“每次 exec 独立 shell”仅指工作目录/环境变量不继承，不代表文件/系统修改会自动回滚。它所述毫秒执行/1 GB 传输是能力说明，不是本机实测结果。
5. upload/download 经 OSS 中转，不上传 APP 签名材料、云密钥或私人数据。上传配置前检查目标存在性并校验哈希；备份、修改、验证、回退均留记录。
6. 原有 App 离线权限保持不变；未取得凭据前才使用网页 Shell 回退，不把截图当成日常云运维主通道。

凭据参考：[官方安装和凭据说明](https://help.aliyun.com/zh/ecs/user-guide/install-and-configure-workbench-cli-credentials)。

### 单实例 CLI 授权准备（2026-09-07）

用户已创建 `skyinstrument-cli`（显示名称“星象仪服务器运维”），并明确允许单台上海 ECS 运维授权。候选策略见 [JSON 模板](../workbuddy/workbench-single-instance-policy.template.json)；替换地域、账号 ID 和实例 ID 后才可提交。当前模板不包含密钥、通配资源或全管理权限。

- **校正：四个动作均使用 `acs:ecs:地域:账号:instance/实例`。** 2026-09-07 用户绑定策略后，摘要把 `LoginECSInstance` 判为无效授权。实查 RAM 可视化编辑器，该动作所需资源类型为 ECS Instance，必要 ARN 是 `acs:ecs:{#regionId}:{#accountId}:instance/{#instanceId}`；旧 `ecs/实例` 被明确列入“未识别资源”。[英文凭据指南](https://www.alibabacloud.com/help/en/ecs/user-guide/install-and-configure-workbench-cli-credentials) 与已安装 Skill 的 `ecs/` 示例不适用于本次控制台定义，不再作为可直接提交的模板；ECS 查询另参见 [DescribeInstances 授权表](https://help.aliyun.com/zh/ecs/developer-reference/api-ecs-2014-05-26-describeinstances)。
- 此策略允许在指定服务器内执行命令，不是只读系统账户；RAM 的实例限制不能替代 Linux 用户和 sudo 权限。不得据此宣称服务器内只可操作资源目录。
- 已有 Workbench 服务关联角色，不再给专用用户创建角色的权限；普通 exec 暂不授予 AI `ChatMessages`。`EndSessions` 的资源范围尚未核实，暂不添加全局权限；后续以实际拒绝信息核实，不把整项 `ecs-workbench:*` 加回来。
- 首次 CLI 连接可能由 Workbench 自动添加 `100.104.0.0/16 → TCP 22` 内网安全组规则，见 [官方连接限制](https://help.aliyun.com/zh/ecs/user-guide/connect-to-an-instance-through-workbench-cli/)。首次有效连接前先核对现有规则；缺失时另行确认，不擅自修改安全组或开放公网。
- 用户亲自创建专用 AccessKey，并在自己的终端执行 `workbench config --profile skyinstrument --mode AK` 输入；不经聊天、命令参数或仓库传递秘密，不读取 `config get`。以后改为 STS/角色仍要核对源凭据保存方式，不能把自动刷新描述为完全没有长期密钥。
- 用户随后要求由 Agent 继续：已保存云端修正版为当前 v2，RAM 摘要的 ECS 与 ecs-workbench 两行均识别到同一目标实例，无“无效授权”；授权管理确认仍绑定 `skyinstrument-cli`。随后用户已配置本机凭据，CLI 连通结果见下节；完整非目标授权诊断、会话清理及文件传输仍待验证。

### CLI 实际连通（2026-09-07 19:29）

后续 19:42 已收紧安全组、部署关键配置审计和普通运维身份；以下为连通时历史记录，最新基线和未解决边界以 `server/SERVER-SECURITY.md` 为准。

- 凭据文件权限 0600，不读取或记录密钥值。`workbench config switch --profile skyinstrument` 后两次指定实例 exec 均成功，远端退出码 0。
- 1.0.1 后台启动曾超时且没有日志；前台启动提示 `profile "default" not found`。虽然 exec 显式传了 profile，后台仍受当前配置影响；切换当前 profile 后解决，不必重建密钥。
- `list ecs` 私网 IP 过滤返回 DescribeInstances 的 403/ImplicitDeny；此入口没有 InstanceIds 参数。指定实例 exec 成功，不为列表便利扩大授权；也不把列表拒绝等同完整非目标权限验证。
- 服务 active、运行用户 nginx、NRestarts=0，健康接口 200、publicService=false；仅本机 8080 及原有 SSH 22 在监听。CLI 远程用户为 root，破坏性操作仍需单独确认。
- 连接前控制台确认原有系统安全组允许 `0.0.0.0/0 → TCP 22`、TCP 3389 和 ICMP，SSH 已覆盖 Workbench 来源；Agent 未修改规则。公网 SSH/RDP 过宽，后续确认备用登录路径后再收紧，不宣称整机已加固。
- 日常运维改用指定实例 CLI，资源服务仍处于备案前本机准备阶段。
