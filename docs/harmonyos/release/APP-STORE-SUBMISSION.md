# Stellarium HarmonyOS 上架规划

> 创建时间：2026-07-27
> 状态：规划中

---

## 1. 仓库处理策略

### 1.0 2026-07-27 离线候选策略

当前未备案个人上架优先走离线候选：

```
release/v1.0-offline-candidate
```

该分支的上架口径：

- 不申请 `ohos.permission.INTERNET`
- 不申请 `ohos.permission.GET_WIFI_INFO`
- 可申请 `ohos.permission.LOCATION` / `ohos.permission.APPROXIMATELY_LOCATION`，仅用于本机匹配天象，不上传
- 隐藏星表下载入口
- 隐藏 LX200 / TCP 望远镜控制入口
- 保留自动定位按钮；定位仅本机使用，不联网、不上传
- 保留离线城市库、手动经纬度、离线世界地图、陀螺仪、星图渲染、搜索、时间控制、图层/详情等本地功能

备案后再从 `feature/online-services` 或开发主线恢复在线地图、远程下载、账号/会员、云服务等能力。

### 1.1 当前仓库结构

```
origin  → Stellarium/stellarium      (上游，只读，不可推)
myfork  → joinother/stellarium       (个人 fork，可推可改)
分支    → openharmony-preview-v1     (HarmonyOS 移植分支)
```

### 1.2 上架要求

| 要求 | 当前状态 | 处理方案 |
|------|----------|----------|
| 源码公开（GPLv2） | 已在 GitHub fork 公开 | 保持 `myfork` 仓库公开，上架时在应用描述中附上源码链接 |
| 不推送到上游 | 已确认 `origin` 无推送权限 | 所有提交只推 `myfork`，不向上游提 PR |
| 分支管理 | 单分支 `openharmony-preview-v1` | 上架后新建 `harmonyos-release` 分支跟踪发布版本 |

### 1.3 推荐的仓库操作

```bash
# 1. 保持开发分支
git checkout openharmony-preview-v1  # 日常开发

# 2. 上架时创建发布分支（打 tag）
git checkout -b harmonyos-release-v1.0
git tag v1.0.0
git push myfork harmonyos-release-v1.0
git push myfork v1.0.0

# 3. 在 GitHub fork 仓库的 README 中说明这是 HarmonyOS 移植版
```

### 1.4 GPLv2 合规

- Stellarium 基于 GPLv2 许可证，衍生作品必须同样开源
- 在应用内"关于"页面显示 GPLv2 许可证文本（已有 `getAboutInfo` 命令）
- 在华为应用市场应用描述中注明"开源软件，源码地址：https://github.com/joinother/stellarium/tree/openharmony-preview-v1"
- 不需要额外申请许可，GPLv2 允许自由分发

---

## 2. 联网功能处理

### 2.1 当前联网功能清单

| 功能 | 是否联网 | 上架处理 |
|------|----------|----------|
| 星表下载（getStarCatalogs） | 是（下载额外星表数据） | **离线版隐藏**，备案后恢复 |
| 卫星 TLE 数据更新 | 是（从 celestrak.org 拉取） | **离线版隐藏/禁用远程更新**，备案后恢复 |
| 流星雨数据 | 否（本地计算） | 无需处理 |
| LX200 望远镜控制 | 是（局域网 TCP） | **离线版隐藏**，局域网通信也按网络能力处理 |
| 脚本下载/播放 | 否（本地脚本） | 无需处理 |
| 配置导入/导出 | 否（本地文件） | 无需处理 |
| 语音合成 | 否（当前未集成） | 无需处理 |
| GPS 定位 | 否（系统定位服务本身不访问本应用服务器） | **离线版保留**，仅本机用于匹配天象 |

### 2.2 隐私政策要求

上架华为应用市场需要提供隐私政策 URL。推荐方案：

1. **在 GitHub fork 仓库中创建隐私政策页面**：
   - 路径：`docs/PRIVACY-POLICY.md`
   - 使用 GitHub Pages 托管为网页：`https://joinother.github.io/stellarium/privacy`
   
2. **隐私政策需涵盖**：
   - 离线版不申请网络权限
   - 定位仅在用户主动点击自动定位时请求，用于本机天象匹配，不上传
   - 不收集任何用户个人信息
   - 不包含任何第三方追踪 SDK

### 2.3 权限精简

离线候选 `module.json5` 中的权限：

```json
"requestPermissions": [
  { "name": "ohos.permission.STORE_PERSISTENT_DATA" },
  { "name": "ohos.permission.FILE_ACCESS_PERSIST" },
  { "name": "ohos.permission.PREPARE_APP_TERMINATE" },
  { "name": "ohos.permission.APPROXIMATELY_LOCATION" },
  { "name": "ohos.permission.LOCATION" },
  { "name": "ohos.permission.ACCELEROMETER" },
  { "name": "ohos.permission.GYROSCOPE" }
]
```

离线上架候选：
- **移除 INTERNET**
- **移除 GET_WIFI_INFO**
- **保留 LOCATION / APPROXIMATELY_LOCATION**，仅用于本机天象匹配
- 保留本地存储与传感器权限

---

## 3. 应用包名规范化

### 3.1 上架应用标识

```
中文名：星象仪
英文名：Stellarium
包名：com.joinother.skyinstrument
```

### 3.2 包名注意事项

1. `com.joinother.skyinstrument` 是上架候选包名，提交到 AppGallery Connect 后不可更改。
2. 本地调试须使用为该包名重新生成的调试签名；此前的 Qt 示例包调试签名不可复用。
3. 发布证书和 Profile 必须由 AppGallery Connect 为这个包名签发，私钥和密码只保存在本机安全存储中。

> **注意**：包名一旦上架不可更改，请在首次发布前确定。

---

## 4. 签名切换

### 4.1 当前签名状态

| 场景 | 签名类型 | 状态 |
|------|----------|------|
| 模拟器调试 | OpenHarmony 调试 CA | 可用 |
| 真机调试 | DevEco 自动签名 | 可用 |
| 上架发布 | 华为发布签名 | **未配置** |

### 4.2 发布签名流程

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/agconnect/)
2. 创建 HarmonyOS 应用
3. 申请发布证书和 Profile：
   - "用户与访问" → "证书管理" → "新增证书"
   - "HarmonyOS 应用" → "HAR" → "创建 Profile"
4. 下载 `.cer` 和 `.p7b` 文件
5. 在 `build-profile.json5` 中配置发布签名：

```json5
"signingConfigs": [
  {
    "name": "release",
    "type": "HarmonyOS",
    "material": {
      "certPath": "path/to/release.cer",
      "storePassword": "***",
      "keyAlias": "stellarium",
      "keyPassword": "***",
      "profilePath": "path/to/releaseProfile.p7b",
      "signAlg": "SHA256withECDSA",
      "storeFile": "path/to/release.p12"
    }
  }
]
```

6. 构建 Release 包：
```bash
hvigorw assembleHap --mode module -p product=release --no-daemon
```

---

## 5. 应用体积优化

### 5.1 当前体积

HAP 包约 **460MB**，主要来自 `entry/libs/` 中的 `.so` 文件。

### 5.2 优化方案

| 方案 | 预计节省 | 实施难度 | 建议 |
|------|----------|----------|------|
| 星表数据按需下载 | ~200MB | 中 | **推荐**：将大数据文件从 HAP 中移除，首次使用时下载 |
| 裁剪不必要的 Qt 模块 | ~50MB | 高 | 可选：分析依赖树，移除未使用的模块 |
| 图片资源压缩 | ~5MB | 低 | 可选：使用 WebP 格式 |
| 分拆 ABI | 不适用 | - | 当前仅 arm64-v8a，已是最优 |

### 5.3 星表按需下载实现

已有命令桥支持：
- `getStarCatalogs`：获取可用星表列表
- `downloadStarCatalog`：下载指定星表
- `getStarCatalogStatus`：查询下载进度

上架前需确保：
1. 首次安装时不包含大星表数据
2. 用户在设置/星表面板中可手动下载
3. 下载进度有 UI 反馈
4. 下载失败可重试

---

## 6. 上架检查清单

- [x] 上架候选包名配置为 `com.joinother.skyinstrument`
- [ ] 隐私政策页面创建并托管
- [ ] 华为发布证书申请
- [ ] Release 签名配置
- [ ] 应用图标 216×216px（已完成）
- [ ] 至少 3 张截图（Pad 横屏 2340×1080）
- [ ] 应用描述（中英文）
- [ ] GPLv2 许可证声明
- [ ] 内容分级：所有人（天文教育类）
- [ ] 权限精简至最小必要
- [ ] 应用体积评估（当前 460MB，考虑星表按需下载）
- [ ] Release HAP 构建并签名
- [ ] 在 AppGallery Connect 提交审核

---

## 7. 截图准备

### 7.1 截图要求

- 尺寸：2340×1080（Pad 横屏）或 1080×2340（手机竖屏）
- 格式：PNG/JPEG
- 数量：至少 3 张，最多 5 张
- 内容：展示核心功能

### 7.2 推荐截图内容

1. **星图主界面**：展示完整星图 + 星座连线 + 行星标签
2. **天体详情**：选中一个天体（如木星），展示详细信息面板
3. **搜索/分类**：展示天体分类浏览面板
4. **时间控制**：展示时间设置面板
5. **今夜天象**：展示今晚天象面板

### 7.3 截图命令

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
$HDC -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/screenshot1.jpeg
$HDC -t 127.0.0.1:5555 file recv /data/local/tmp/screenshot1.jpeg /tmp/screenshot1.jpeg
```

---

## 8. 联网功能详细说明

### 8.1 星表下载

- **数据源**：Stellarium 官方星表服务器
- **触发方式**：用户在"星表"面板中手动点击下载
- **数据存储**：下载到应用沙箱目录
- **隐私影响**：仅访问公网下载星表数据，不传输用户信息

### 8.2 卫星 TLE 数据

- **数据源**：celestrak.org（公共卫星轨道数据）
- **触发方式**：用户在"卫星"面板中手动更新
- **隐私影响**：仅请求公开的卫星轨道数据

### 8.3 望远镜控制（LX200）

- **通信方式**：局域网 TCP/IP
- **触发方式**：用户手动输入望远镜 IP 和端口
- **隐私影响**：仅在用户局域网内通信，不经过互联网

### 8.4 GPS 定位

- **数据来源**：系统定位服务
- **触发方式**：用户在"位置"面板中点击"自动定位"
- **隐私影响**：获取设备地理位置用于匹配星图，不上传任何服务器
