# 星表扩展：stars5 预置 + stars6~8 手动导入

> **状态：** 设计方案；2026-10-09 部分落地 —— P1 星表面板（统一 9 级只读列表 + 渠道标注 + 静态回退）已实现并在模拟器验证；stars5 **暂不打包**、下载渠道已验证（§8）。P0（预置 stars5）、P2（离线手动导入）、P3（卸载）未实施。
> **日期：** 2026-10-06（设计）；2026-10-09（P1 落地 + 渠道验证）
> **基线：** HEAD `c52a517961`；当前内置 stars0–stars4（约 12 等）

## 1. 目标

1. **预置 stars5**：将 `stars_5_1v0_6.cat`（245 MB，12.0–13.75 等，约 800 万星）打入 HAP rawfile，启动时落盘到 `filesDir/stellarium/stars/hip_gaia3/`，C++ 侧 `StarMgr` 自动发现并加载，极限星等从 12 提升到 **≈13.75**。
2. **星表面板改造**：始终显示 9 级星表列表，每级标注「已加载/未加载」，已加载项显示星等范围与星数，未加载项显示大小。
3. **离线手动导入 stars6~8**：在 `OFFLINE_APPGALLERY_BUILD` 模式下，用户可从设备本地路径（U 盘 / 内部存储 / 文件管理器导出）选择 `.cat` 文件导入到 `stars/hip_gaia3/`，`StarMgr` 在下次启动或运行时热加载检测到的新级。

## 2. 现状分析

### 2.1 C++ 星表加载机制

`StarMgr` 使用**逐级加载**：`defaultStarsConfig.json` 定义 9 级（stars0–stars8），`loadData()` 按 `catalogsDescription` 顺序调用 `checkAndLoadCatalog()`：

1. 读取 `fileName`，用 `StelFileMgr::findFile()` 在安装目录和用户目录搜索；
2. 找到文件但 `checked=false` → 计算 MD5，匹配则自动 `setCheckFlag(true)`；
3. `checked=true` → 创建 `ZoneArray` 并追加到 `gridLevels`；
4. **前置级守卫**：若某级文件缺失，其上级全部跳过（`return false`），日志 `"at least one of the lower levels is missing"`。

关键结论：**只需将 `.cat` 文件放到 `StelFileMgr` 可搜索的路径**，`StarMgr` 即可发现并加载。`StelFileMgr` 的搜索路径 = `STEL_USERDIR`（`filesDir/stellarium_userdir`）+ `STELLARIUM_DATA_ROOT`（`filesDir/stellarium`）。

### 2.2 现有资源落盘链

`StellariumResourceBootstrap.ets` 的 `prepareStellariumResourcesAsync()` 负责：
- 首次启动：全量解压 rawfile 树到 `filesDir/stellarium/`；
- 后续启动：刷新小文件（清单/翻译/深空索引/星表配置），以及**异步更新 stars4**（`DEEP_STAR_CATALOG` 常量 + `fileSize` 守卫）。

`stars4` 的落盘模式（53 MB，异步 `writeRawFileAsync`）可直接复用给 stars5（245 MB）。

### 2.3 现有 UI

`CatalogsPanel.ets` 当前行为：
- `OFFLINE_APPGALLERY_BUILD=true` → 显示 "所有星表已内置" 空态；
- `OFFLINE_APPGALLERY_BUILD=false` → 列表显示未下载项 + 下载按钮；
- `CatalogStore.startCatalogDownload()` → 桥调 `downloadStarCatalog` + 轮询 `getStarCatalogStatus`。

### 2.4 离线构建标志

- C++ 侧：`STELLARIUM_OHOS_OFFLINE` 编译宏（CMake `BOOL=1`），控制 `downloadStarCatalog` / `getStarCatalogStatus` 的禁用；
- ArkTS 侧：`OFFLINE_APPGALLERY_BUILD = true`（`MainWindowModels.ets:426`），控制 UI 分支。

## 3. 设计方案

### 3.1 stars5 预置

#### 3.1.1 构建侧

| 步骤 | 动作 | 说明 |
|---|---|---|
| 1 | 下载 `stars_5_1v0_6.cat`（245 MB）到 `stars/hip_gaia3/` | 更新 `scripts/update-ohos-astronomy-data.mjs` 加 `--allow-large-star-download` 逻辑 |
| 2 | `defaultStarsConfig.json` 中 stars5 的 `checked` 改为 `true` | C++ 侧首启时不会因 `checked=false` 触发 MD5 验证（文件来自可信 rawfile），减少 245 MB MD5 开销 |
| 3 | `data/ohos/catalog-manifest.json` 增加 stars5 条目 | `files` 数组追加 `{ "file": "stars_5_1v0_6.cat", "bytes": 257743872, "md5": "eb2834985d5885ac03695084cded6897", "valid": true }` |
| 4 | `sync-ohos-resources.sh` 已自动将 `stars/hip_gaia3/*` 打入 rawfile | 无需额外脚本改动 |

> HAP 体积增量 ≈ 245 MB（rawfile 压缩后约 150–180 MB，.cat 为二进制结构化数据，压缩率一般）。

#### 3.1.2 启动侧（StellariumResourceBootstrap.ets）

新增常量：

```typescript
const STAR_CATALOG_5 = 'stars/hip_gaia3/stars_5_1v0_6.cat';
const STAR_CATALOG_5_BYTES = 257743872; // 实测（SourceForge downloads.sourceforge.net Content-Length，2026-10-09）
```

在 `prepareStellariumResourcesAsync()` 的已有资源刷新逻辑中增加：

```typescript
// 与 stars4 同模式的异步落盘：只在文件不存在或大小不匹配时写入
const star5Path = `${installRoot}/${STAR_CATALOG_5}`;
if (fileSize(star5Path) !== STAR_CATALOG_5_BYTES) {
  const startedAt = Date.now();
  hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] installing stars_5 catalogue asynchronously');
  await writeRawFileAsync(appContext, `${RAW_ROOT}/${STAR_CATALOG_5}`, star5Path);
  if (fileSize(star5Path) !== STAR_CATALOG_5_BYTES) {
    throw new Error(`stars_5 catalogue size mismatch: ${fileSize(star5Path)}`);
  }
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `[startup] installed stars_5 catalogue in ${Date.now() - startedAt} ms`);
}
```

**启动时序**：stars5 的 `writeRawFileAsync` 排在 stars4 之后。两者合计约 300 MB，在 UFS 3.1 设备上预计 3–5 秒。`prepareStellariumResourcesAsync()` 在 Qt 引擎挂载前完成，不阻塞首帧渲染（首帧只有 stars0–stars4 数据，stars5 在 Qt 启动后的 `StarMgr::loadData()` 里加载）。

> 若 stars5 落盘未完成 Qt 就启动了，`StarMgr` 仍会从旧配置读取 `checked=false` 的 stars5 → 跳过；下次启动时配置已更新为 `checked=true` → 加载。这是安全的降级行为。

#### 3.1.3 starsConfig.json 写入

`prepareStellariumResources()` 在首启时用 `writeRawFile` 写入 `defaultStarsConfig.json`。由于步骤 3.1.1-2 已将 stars5 `checked` 改为 `true`，该写入自然包含新状态，无需额外逻辑。

### 3.2 星表面板改造

#### 3.2.1 数据模型扩展

`StarCatalogItem` 增加：

```typescript
export interface StarCatalogItem {
  id: string              // "stars0"…"stars8"
  name: string            // 显示名（从桥回包取，或 I18n 本地化）
  size: string            // "0.2 MB"…"1.8 GB"
  key: string
  fileName: string        // "stars_0_0v0_21.cat" 等
  url: string             // 下载 URL（离线模式下为空）
  html: string
  checked: boolean        // C++ 侧是否已加载
  magRange: string        // 新增："-2.0 ~ 6.0" 等（从桥回包取）
  count: string           // 新增："~5,000" 等（从桥回包取）
}
```

`StarCatalogRaw` 同步增加 `magRange` / `count` 可选字段。

C++ 侧 `getStarCatalogs` 已返回 `magRange` / `count` / `sizeMb`，只是 ArkTS 侧之前未映射。修改 `CatalogStore.loadStarCatalogs()` 的映射即可。

#### 3.2.2 CatalogsPanel 重写

替换当前双分支（离线空态 / 在线下载列表）为**统一列表**，无论离线/在线模式都显示全部 9 级星表：

```
┌─────────────────────────────────────────────────────┐
│  恒星星表（hip_gaia3 / Gaia DR3）                    │
├─────────────────────────────────────────────────────┤
│  ★ stars0  -2.0 ~ 6.0 等    ~5,000 星     0.2 MB   │
│                                 [已加载]            │
│  ★ stars1  6.0 ~ 7.5 等      ~22,000 星    1.0 MB   │
│                                 [已加载]            │
│  ★ stars2  7.5 ~ 9.0 等      ~140,000 星   6.5 MB   │
│                                 [已加载]            │
│  ★ stars3  9.0 ~ 10.5 等     ~420,000 星   12.8 MB  │
│                                 [已加载]            │
│  ★ stars4  10.5 ~ 12.0 等    ~170 万星     53 MB    │
│                                 [已加载]            │
│  ★ stars5  12.0 ~ 13.75 等   ~800 万星     245 MB   │
│                                 [已加载]            │
│  ○ stars6  13.75 ~ 15.5 等   ~2,980 万星   912 MB   │
│                                 [手动导入]          │
│  ○ stars7  15.5 ~ 16.75 等   ~5,750 万星   1.7 GB   │
│                                 [手动导入]          │
│  ○ stars8  16.75 ~ 18.0 等   ~1.2 亿星     1.8 GB   │
│                                 [手动导入]          │
└─────────────────────────────────────────────────────┘
```

**每行状态**：

| 条件 | 右侧按钮/标签 |
|---|---|
| `checked=true` | 绿色 `[已加载]` 标签 |
| `checked=false` 且 `OFFLINE_APPGALLERY_BUILD=true` | `[手动导入]` 按钮 |
| `checked=false` 且 `OFFLINE_APPGALLERY_BUILD=false` | `[下载]` 按钮（现有逻辑） |

**手动导入按钮**点击后弹出文件选择器（见 §3.3）。

#### 3.2.3 前置级校验提示

若用户尝试导入 stars6 但 stars5 未加载，按钮应置灰并提示"需先加载 stars5"。该信息从 `catalogList` 的前置项 `checked` 直接推导，无需额外桥命令。

### 3.3 离线手动导入

#### 3.3.1 新增桥命令：`importStarCatalog`

C++ 侧新增命令（不受 `STELLARIUM_OHOS_OFFLINE` 守卫限制，因为是纯本地操作）：

```cpp
if (commandName == "importStarCatalog")
{
    // arg = JSON: { "catalogId": "stars6", "sourcePath": "/data/local/tmp/stars_6_1v0_4.cat" }
    const QJsonObject argObj = QJsonDocument::fromJson(arg.toUtf8()).object();
    const QString catalogId = argObj.value("catalogId").toString();
    const QString sourcePath = argObj.value("sourcePath").toString();

    // 1. 从 catalogsDescription 找到该 ID 的描述
    StarMgr* sm = GETSTELMODULE(StarMgr);
    if (!sm) { result["ok"] = false; result["error"] = "no StarMgr"; return result; }

    QVariantMap catDesc;
    for (const QVariant& v : sm->getCatalogsDescription()) {
        QVariantMap m = v.toMap();
        if (m.value("id").toString() == catalogId) { catDesc = m; break; }
    }
    if (catDesc.isEmpty()) { result["ok"] = false; result["error"] = "unknown catalog id"; return result; }

    // 2. 检查前置级是否已加载
    // catalogsDescription 是有序列表，stars0…stars8；遍历到 catalogId 之前的项必须全 checked
    bool prereqOk = true;
    for (const QVariant& v : sm->getCatalogsDescription()) {
        QVariantMap m = v.toMap();
        if (m.value("id").toString() == catalogId) break;
        if (!m.value("checked").toBool()) { prereqOk = false; break; }
    }
    if (!prereqOk) { result["ok"] = false; result["error"] = "prerequisite catalog not loaded"; return result; }

    // 3. 校验源文件存在性 + 大小非零
    QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.isFile() || sourceInfo.size() == 0) {
        result["ok"] = false; result["error"] = "source file not found or empty"; return result;
    }

    // 4. 校验文件名匹配（防止用户选错文件）
    const QString expectedFileName = catDesc.value("fileName").toString();
    const QString sourceBaseName = sourceInfo.fileName();
    if (sourceBaseName != expectedFileName) {
        result["ok"] = false;
        result["error"] = QString("filename mismatch: expected %1, got %2").arg(expectedFileName, sourceBaseName);
        return result;
    }

    // 5. 复制到目标路径
    const QString destDir = StelFileMgr::getUserDir() + "/stars/hip_gaia3";
    const QString destPath = destDir + "/" + expectedFileName;
    StelFileMgr::makeSureDirExistsAndIsWritable(destDir);

    if (QFile::exists(destPath)) QFile::remove(destPath);
    if (!QFile::copy(sourcePath, destPath)) {
        result["ok"] = false; result["error"] = "copy failed"; return result;
    }
    QFile::setPermissions(destPath, QFile::permissions(destPath) | QFileDevice::ReadOwner);

    // 6. MD5 校验
    QFile catFile(destPath);
    if (catFile.open(QIODevice::ReadOnly)) {
        QCryptographicHash md5Hash(QCryptographicHash::Md5);
        // ...（复用 checkAndLoadCatalog 的 MD5 计算逻辑）
        catFile.close();
        if (md5Hash.result().toHex() != catDesc.value("checksum").toByteArray()) {
            QFile::remove(destPath);
            result["ok"] = false; result["error"] = "MD5 mismatch: file may be corrupt"; return result;
        }
    }

    // 7. 通知 StarMgr 加载
    const bool loaded = sm->checkAndLoadCatalog(catDesc, true);
    result["ok"] = loaded;
    result["loaded"] = loaded;
    result["id"] = catalogId;
    return result;
}
```

**关键设计决策**：
- 文件名校验：防止用户把 stars_7 文件选给 stars6 的导入槽；
- MD5 校验：不匹配则删除并报错，保证数据完整性；
- 前置级检查：防止跳级导致 C++ 侧加载失败；
- 复制到 `STEL_USERDIR`：与下载路径一致，`StelFileMgr` 可发现；
- `checkAndLoadCatalog(catDesc, true)` 调用后，该级立即可用**无需重启**（运行时热加载）。

#### 3.3.2 新增桥命令：`removeStarCatalog`

允许用户卸载已手动导入的 stars6~8（释放存储空间），但**禁止卸载内置的 stars0–stars5**：

```cpp
if (commandName == "removeStarCatalog")
{
    // arg = catalogId
    // 1. 校验 catalogId 在 stars6…stars8 范围
    // 2. 校验无更高级已加载（stars6 不能在有 stars7 已加载时卸载）
    // 3. 删除文件 + setCheckFlag(id, false) + 从 gridLevels 移除该级
    // 返回 { ok, id }
}
```

> 此命令为可选功能，初版可不实现。卸载后 `StarMgr` 需要重建 `gridLevels` 和 `hipIndex`，这需要 StarMgr 暴露一个 reload 接口。如果初版不做运行时卸载，用户可通过应用设置「清除数据」重置。

#### 3.3.3 ArkTS 侧：文件选择器

HarmonyOS 提供 `@ohos.file.picker` 的 `DocumentViewPicker`，可选择设备上的文件并获取 URI → 沙箱路径。

`CatalogStore` 新增方法：

```typescript
importLocalCatalog(catalogId: string, sourceUri: string): void {
    // 1. 将 URI 转为沙箱可读路径（fs.openSync via fd → copy to temp → get path）
    //    或直接用 sourcePath 参数让 C++ 侧 QFile::copy
    // 2. 桥调 importStarCatalog
    // 3. 成功后刷新 catalogList
}
```

UI 流程：
1. 用户点击 `[手动导入]` → 弹出 `DocumentViewPicker`（过滤 `.cat`）；
2. 用户选择文件 → 回调拿到 URI；
3. 检查文件名是否匹配（前端快速校验，不等 C++ 返回）；
4. 调 `importLocalCatalog(id, uri)` → 桥命令执行复制 + MD5 + 加载；
5. 结果回注 UI：成功 → 刷新列表（该项变为 `[已加载]`），失败 → 提示错误信息。

#### 3.3.4 权限

`DocumentViewPicker` 是系统安全组件，**不需要** `ohos.permission.READ_EXTERNAL_STORAGE` 等存储权限。用户主动选择即授权，应用只拿到选中文件的只读访问。

#### 3.3.5 命令注册

在 `StelOhosCommandCatalog.hpp` 的 `names()` 中追加 `"importStarCatalog"` / `"removeStarCatalog"`，并标注 `offline=true`（纯本地操作）。

### 3.4 设置快照面板

`SettingsQuickLegacyPanel` 的「基础星表」健康行当前只显示整体健康状态。扩展为显示**当前极限星等**：

```
基础星表：已加载至 13.75 等（stars0–stars5）/ 6 级已加载
```

数据来源：`CatalogStore.starCatalogHealth` 已有 `limitingMagnitude` 字段（来自 `getCatalogHealth` 桥命令）。C++ 侧需在 `getCatalogHealth` 的 stars 回包中增加 `loadedLevel`（当前最高已加载级号）和 `limitingMagnitude`（当前极限星等）。

### 3.5 getStarCatalogs 回包扩展

当前 C++ 侧 `getStarCatalogs` 返回的 `catalogs` 数组各项来自 `defaultStarsConfig.json`，已有 `id`/`fileName`/`count`/`magRange`/`sizeMb`/`url`/`checksum`/`checked`。ArkTS 侧的 `StarCatalogRaw` 需映射这些已有字段：

| C++ 字段 | ArkTS 映射 | 说明 |
|---|---|---|
| `id` | `id` | 已有 |
| `fileName` | `fileName` | 已有 |
| `count` | `count` | 已有（数字，如 0.005 表示百万） |
| `magRange` | `magRange` | 已有（JSON 数组 `[12, 13.75]`） |
| `sizeMb` | `sizeMb` | 已有（数字） |
| `url` | `url` | 已有（空或 SourceForge URL） |
| `checked` | `checked` | 已有 |
| `checksum` | `checksum` | 已有（MD5） |

**无需扩展 C++ 回包**——所有信息已存在，只是 ArkTS 侧之前没映射 `magRange`/`count`/`sizeMb`/`checksum`。修改 `CatalogStore.loadStarCatalogs()` 的映射即可。

`StarCatalogItem` 的 `size` 字段改为从 `sizeMb` 派生（`sizeMb >= 1024 ? (sizeMb/1024).toFixed(1) + ' GB' : sizeMb + ' MB'`），替代原来可能为空的 `size` 字段串。

## 4. 改动清单

### 4.1 C++ 侧

| 文件 | 改动 |
|---|---|
| `src/StelMainView.cpp` | 新增 `importStarCatalog` / `removeStarCatalog` 命令处理（约 80 行）；`getCatalogHealth` 回包增加 `loadedLevel` + `limitingMagnitude` |
| `src/StelOhosCommandCatalog.hpp` | `names()` 追加 `"importStarCatalog"` / `"removeStarCatalog"`；`item()` 补充描述和 examplePayload |
| `src/core/modules/StarMgr.hpp` | 新增 `int getLoadedMaxLevel() const`；`int getLimitingMagnitude() const`（派生自 `maxGeodesicGridLevel` → `defaultStarsConfig.json` 的 magRange） |
| `stars/hip_gaia3/defaultStarsConfig.json` | stars5 的 `checked` 改为 `true` |
| `data/ohos/catalog-manifest.json` | files 数组追加 stars5 条目；`limitingMagnitude` 改为 `13.75` |

### 4.2 ArkTS 侧

| 文件 | 改动 |
|---|---|
| `qability/StellariumResourceBootstrap.ets` | 新增 `STAR_CATALOG_5` / `STAR_CATALOG_5_BYTES` 常量；`prepareStellariumResourcesAsync()` 增加 stars5 异步落盘 |
| `state/CatalogStore.ets` | `loadStarCatalogs()` 映射 `magRange`/`count`/`sizeMb`/`checksum`；新增 `importLocalCatalog(id, sourceUri)` 方法 |
| `panels/panels/CatalogsPanel.ets` | 重写：统一列表替代双分支；每行显示星等范围 + 星数 + 大小 + 状态标签/按钮；`[手动导入]` 按钮触发文件选择器 |
| `common/types/MainWindowModels.ets` | `StarCatalogItem` 增加 `magRange`/`count`/`sizeMb`/`checksum` 字段；`StarCatalogRaw` 同步；`OFFLINE_APPGALLERY_BUILD` 仍为 `true`（不变） |
| `pages/MainWindowNativeNode.ets` | 星表面板的 `onDownload` 回调旁新增 `onImportCatalog` 回调（文件选择器 → `CatalogStore.importLocalCatalog`） |
| `bridge/CommandPort.ets` | 无改动（`request` / `requestWhenReady` 已是通用调用接口） |

### 4.3 I18n

新增 key：

| key | zh_CN | en |
|---|---|---|
| `catalog_import` | 手动导入 | Import |
| `catalog_importing` | 导入中… | Importing… |
| `catalog_import_success` | 「{id}」导入成功并已加载 | {id} imported and loaded |
| `catalog_import_failed` | 导入失败：{error} | Import failed: {error} |
| `catalog_prereq_missing` | 需先加载前置星表 | Prerequisite catalog required |
| `catalog_mag_range` | {from} ~ {to} 等 | Mag {from}–{to} |
| `catalog_count_millions` | ~{n} 万星 | ~{n}M stars |
| `catalog_loaded_to` | 已加载至 {mag} 等 | Loaded to mag {mag} |
| `catalog_filename_mismatch` | 文件名不匹配，需选择 {expected} | Filename mismatch, expected {expected} |

### 4.4 脚本

| 文件 | 改动 |
|---|---|
| `scripts/update-ohos-astronomy-data.mjs` | `--allow-large-star-download` 时下载 stars5；更新 `defaultStarsConfig.json` 和 `catalog-manifest.json` |
| `scripts/check-ohos-offline-catalogs.mjs` | 校验 stars5 存在 + MD5 匹配 |
| `scripts/check-ohos-ui-contract.mjs` | 无改动（星表面板无 `.id()` 锚点变化） |

## 5. 风险与缓解

| # | 风险 | 缓解 |
|---|---|---|
| 1 | HAP 体积增长 ~150–180 MB（stars5 压缩后） | 用户可接受；应用市场/AppGallery 对单 HAP 限 2 GB，远未触及 |
| 2 | 首次启动 stars5 落盘耗时 3–5 秒，延迟 C++ 可用 | stars5 落盘与 Qt 启动并行；若未完成则降级到 12 等，下次启动自动补上 |
| 3 | 用户导入错误的 .cat 文件 | 文件名校验 + MD5 校验双重守卫 |
| 4 | 用户导入的 .cat 来自不同版本（格式不兼容） | `ZoneArray::create()` 内部有版本检查；加载失败时 C++ 返回 `loaded=false`，前端提示 |
| 5 | 运行时热加载 stars6 后内存峰值 | stars6 解压后内存占用约 900 MB（mmap 模式下实际为虚拟地址空间）；Android 侧已用 `useMmap=false`，HarmonyOS 建议同设 `false`（`Q_OS_ANDROID` 分支已覆盖 OHOS，因为 OHOS 走 `#if defined(Q_OS_ANDROID)`） |
| 6 | 文件选择器返回 URI 格式兼容性 | `DocumentViewPicker` 返回 `file://` URI，通过 `fs.openSync(uri)` 获取 fd → C++ 侧用 fd 路径或先拷到临时文件再 `QFile::copy` |
| 7 | stars6~8 文件过大（912 MB–1.8 GB），设备存储不足 | UI 在导入前显示文件大小，提示用户确认剩余空间；`QFile::copy` 失败时返回磁盘空间不足错误 |
| 8 | 前置级卸载导致状态不一致 | 初版不实现 `removeStarCatalog`；如需实现则增加级联检查（高级已加载时禁止卸载低级） |

## 6. 实施顺序

1. **P0 — stars5 预置**（C++ 改动最小、收益最大）：
   - 修改 `defaultStarsConfig.json`（stars5 checked=true）
   - 修改 `catalog-manifest.json`
   - 修改 `StellariumResourceBootstrap.ets`（stars5 落盘）
   - 下载 stars5 文件到源树
   - 构建验证 + 真机确认加载至 13.75 等

2. **P1 — 星表面板改造**（UI 重写）：
   - `CatalogStore.loadStarCatalogs()` 映射扩展字段
   - `StarCatalogItem` / `StarCatalogRaw` 扩展
   - `CatalogsPanel.ets` 统一列表重写
   - I18n key 补充

3. **P2 — 离线手动导入**（新功能）：
   - C++ `importStarCatalog` 命令
   - `StelOhosCommandCatalog.hpp` 注册
   - `CatalogStore.importLocalCatalog()`
   - 文件选择器集成
   - 设置面板极限星等显示

4. **P3 — 可选**：
   - `removeStarCatalog` 命令
   - 运行时卸载 UI

## 7. 验收标准

1. stars5 预置：全新安装后 `getStarCatalogs` 返回 stars5 `checked=true`；`getStarCount` 星数从 ≈170 万增长至 ≈800 万；`getLimitMagnitude` 返回 ≈13.75。
2. 星表面板：9 级列表完整显示，stars0–stars5 显示 `[已加载]`，stars6–stars8 显示 `[手动导入]`。
3. 手动导入：选择正确的 `stars_6_1v0_4.cat` → 导入成功 → 列表刷新 stars6 为 `[已加载]` → 星数增长至 ≈2,980 万；选择错误文件名 → 提示文件名不匹配；前置级未加载 → 按钮置灰。
4. 设置面板：「基础星表」行显示当前极限星等。
5. 契约护栏：`check-ohos-ui-contract.mjs` 全绿。

## 8. 实施与验证记录（2026-10-09）

### 8.1 下载渠道验证（结论：SourceForge 有效，GitHub 不含 stars）

实测两条候选渠道：

| 渠道 | 结果 |
|---|---|
| **SourceForge** `.../Extra-data-files/stars-3.0/` | ✅ 有效。目录页列出 `stars_4/5/6/7/8`；`stars_5_1v0_6.cat/download` 经 302→302→200，`Content-Type: application/octet-stream`、`Content-Disposition: attachment; filename="stars_5_1v0_6.cat"`、`Content-Length: 257743872`（≈245.7 MiB），最终落到镜像 `zenlayer.dl.sourceforge.net` |
| **GitHub** `Stellarium/stellarium-data` releases | ❌ 不含星表。仅有 DSO 星表（`dso-3.23`）、`translations`、`weekly-snapshot`（桌面安装包）等资产，无 `stars_*.cat` |

结论：`defaultStarsConfig.json` 的 `url` 继续用 SourceForge（现状即如此），无需改为 GitHub。

> 与设计稿的偏差：`STAR_CATALOG_5_BYTES` 实测为 **257743872**（非 257017856）；`sizeMb` 245 一致。

### 8.2 本轮落地（P1：星表面板）

在**不打包 stars5**、**不改编译宏（保持离线构建）**的前提下，先做只读列表与渠道标注：

- `StarCatalogItem` / `StarCatalogRaw` 扩展 `magRange` / `count` / `sizeMb` / `checksum` / `source`。
- `CatalogStore.loadStarCatalogs()`：按 `defaultStarsConfig.json` 原样映射桥回包，并新增**静态 9 级快照**（`buildStarCatalogFallback()`），在桥不可用 / 回包为空 / 失败时回退 —— 使 UI-only 模拟器与桥未就绪场景也能渲染完整级表。
- `CatalogsPanel` 重写为**统一 9 级列表**（去掉了原离线空态）：每行显示 星等范围 / 星数 / 大小；已加载显示 `[已加载]`，未加载显示 `[手动导入]`（离线）或 `[下载]`（在线），未加载项额外标注 `来源：SourceForge`。
- 未加载项提供**「打开下载页」链接**：`StarCatalogItem.sourcePage` 由直链派生（去掉 `/download` 与文件名），点击经宿主 `openExternalUrl()` 用系统浏览器打开 SourceForge 目录页（`.../Extra-data-files/stars-3.0/`），供用户从浏览器手动下载（配合 P2 手动导入）。真机实测：点击后跳转 `com.huawei.hmos.browser`，落点 `Home / Extra-data-files / stars-3.0` 文件列表。
- 宿主：星表面板在**离线与在线模式都加载**列表（原来仅在线加载）。

**模拟器验证（Pura 90 Pro，UI-only，`127.0.0.1:5555`）**：进入「更多功能 → 天体数据与扩展 → 星表下载」，面板渲染标题「恒星星表」、摘要「已加载至 12.0 等（stars0–stars4）」、9 行 stars0–stars8，星等范围 / 星数 / 大小齐全；stars0–4 `[已加载]`，stars5–8 `[手动导入]` + `来源：SourceForge`；进程存活、无崩溃。

### 8.3 未实施（后续）

- P0：把 `stars_5_1v0_6.cat` 打入 rawfile + 启动异步落盘（本轮明确不做，避免 +245 MB）。
- 在线下载端到端：`STELLARIUM_OHOS_OFFLINE=0` + `OFFLINE_APPGALLERY_BUILD=false` 下点 `[下载]` 走 `downloadStarCatalog`（当前为离线构建）。
- P3：`removeStarCatalog` 运行时卸载。

### 8.4 已落地（P2：离线手动导入，2026-10-09 追加）

按用户决定**采用上游通行做法（严格，不放松校验）**：

- **「打开下载页」链接文字改为具体 `.cat` 文件名**（如 `stars_6_1v0_4.cat`），点击仍走系统浏览器打开 SourceForge 目录页。
- **「手动导入」按钮启用**（`Button`，非灰标签）：点击弹出系统文件选择器（`DocumentViewPicker`，过滤 `.cat`）。
- 流程：**ArkTS 选文件 + 校验文件名 + 异步拷到用户目录**（`filesDir/stellarium_userdir/stars/hip_gaia3/<fileName>`）→ 桥命令 **`importStarCatalog`**（C++）做**前置级 + 文件名 + MD5** 校验并**热加载**；校验失败时 `StarMgr` 删除该文件并返回失败。
  - 设计取向：拷贝（重活）由 ArkTS 用 `fileIo.copy` 异步完成，避免阻塞渲染线程；C++ 只做校验 + 加载（与 `downloadStarCatalog` 完成时同一条 `checkAndLoadCatalog` 路径，故行为一致：失败即删、成功即热加载）。
  - ArkTS：`CatalogStore.importLocalCatalog(id)`（`requestLongRunning` 轮询）+ 宿主 `importCatalogFile(id, fileName)`（picker + copy + 回注）；面板新增 `onImportCatalog` 回调。
  - C++：`src/StelMainView.cpp` 新增 `importStarCatalog`；`src/StelOhosCommandCatalog.hpp` 登记（命令数 358 → **359**）。
- **验证（真机 Mate 80 Pro `192.168.1.7:36717`）**：`arkts_check` 0 error；引擎**重编** + `BUILD SUCCESSFUL`；UI 契约 intact（50/34/29/18）；`check-ohos-command-catalog` 通过（359）。CLI `importStarCatalog stars6` → `{"ok":false,"error":"prerequisite catalog not loaded"}`（前置级守卫生效）；面板实测：链接文字为 `stars_7_1v0_4.cat` / `stars_8_2v0_3.cat`（可点），「手动导入」为**可点按钮**，点击弹出系统文件选择器。
- **未端到端走查**：真正导入一个 912 MB 的 stars6 需本地已备该文件，本轮未做（体积大且当前无该文件）；文件名不匹配 / MD5 不符的拒绝路径由 `importStarCatalog` 的守卫与 `StarMgr` 既有 MD5 逻辑保证。

### 8.5 注册为 .cat 的「打开方式」+ 改按 MD5 识别（2026-10-09 追加）

- **注册**：`harmonyos/resources/rawfile/arkdata/utd/utd.json5` 声明自定义 UTD（`com.joinother.skyinstrument.stellarium-cat`，后缀 `.cat`）；`harmonyos/module.json5` 的 QAbility `skills` 增加 `actions:[ohos.want.action.viewData]` + `uris:[{ scheme:"file", utd:"<自定义>", linkFeature:"FileOpen" }]`。
- **接收**：`QAbility.onCreate`/`onNewWant` 检测 `want.uri` 为 `.cat` → 写 `AppStorage('stellariumOpenCatalogUri')`；宿主 `@StorageLink`(`@Watch`) 消费，Qt 就绪后处理（未就绪先挂起）。
- **识别改按 MD5（不再按文件名）**：宿主把文件落到 `filesDir/stellarium_userdir/stars/hip_gaia3/<原名>`，桥命令 `importStarCatalog`（payload = 源文件路径）计算其 MD5，匹配 `defaultStarsConfig.json` 里 `checksum` 相等的级 → 前置级守卫 → 归位到该级 `fileName` → 加载。识别/加载失败即拒绝。`手动导入` 按钮与「打开方式」共用同一路径，不再做文件名预校验。
- **重复入队防护**：桥是「入队 + 轮询重发」，同步长命令会被重复执行（实测一次导入触发了约 9 次 `importStarCatalog`）；命令内对「同一路径 + 大小 + mtime 且上次成功」直接短路，避免重复 MD5 / 加载。
- **checked 标志**：`StarMgr::setCheckFlag` 由 private 提为 public（`src/core/modules/StarMgr.hpp`，仅可见性，行为不变），导入成功后显式置位，使 `getStarCatalogs` / 面板立即显示「已加载」（否则要等下次启动）。
- **真机实测（Mate 80 Pro）**：`stars_5_1v0_6.cat` 从文件管理器「打开方式」→ 本应用 → 日志 `[catalog-open] received .cat open-with want` + `command received: "importStarCatalog" .../stars_5_1v0_6.cat` + `Loading star catalog: ... stars_5_1v0_6 - 5_1v0_6; 8051935 entries`；`getStarCountFull` → `catalogLevels:6 / total:10380312`；`getStarCatalogs` → stars5 `checked:true`。

## 9. 星表版本与 MD5 维护（2026-10-09 补）

### 9.1 更新周期：随上游"版本"，不是定时

星表按**版本**发布，不是按固定周期：目录页 `stars-3.0`（第 3 版，Stellarium 25.1+），单个文件带版本后缀（`stars_5_1v0_6.cat` = 生成 1 / 版本 0 / 构建 6）。数据变化时后缀与内容一起变；两次版本之间文件保持稳定（`.asc` 签名也随之更新）。

`defaultStarsConfig.json` 由**上游维护**（`fileName` / `count` / `magRange` / `sizeMb` / `url` / `checksum`），上游发布新版时在同一提交里更新 —— 即 **`fileName` ↔ `checksum` ↔ `.cat` 字节 三者强耦合**。

**实测：Gaia DR3 投入使用后确实一直在变。** 上游 `Stellarium/stellarium` 的该文件自 Gaia DR3 引入（2024-12-25，commit `19ff230c9` "New star catalog with Gaia DR3"）到 2026-03-14，共被改 **12 次**。各级文件版本演变：

| 级 | 引入时 | 最近（2026-03-14） | 中途变化 |
|---|---|---|---|
| stars0 | `0v0_14` | `0v0_21` | 14→16→19→20→21（共 5 版） |
| stars1 | `0v0_14` | `0v0_16` | 14→15→16（3 版） |
| stars2 | `0v0_14` | `0v0_17` | 14→16→17（3 版） |
| stars3 | `0v0_9` | `0v0_10` | 9→10（1 次） |
| stars4 | `1v0_5` | `1v0_6` | 5→6（1 次） |
| stars5 | `1v0_5` | `1v0_6` | 5→6（1 次），且同日（`334cce00b`）修过一次 checksum |
| stars6 | `1v0_3` | `1v0_4` | 3→4（1 次） |
| stars7 | `1v0_3` | `1v0_4` | 3→4（1 次） |
| stars8 | `2v0_3` | `2v0_3` | 无 |

**结论**：亮星级（stars0–2）**最活跃**（每级 3–5 版，约每季度一次），而这正是**内置**的几级；中暗级（stars3–7）各改 1 次后趋稳；stars8 未动。桌面版与移动版共用同一份配置与同一套 `StarMgr` 校验（本文件属核心库），故结论一致。

**上游为何"名字 + MD5 精确匹配、宁拒不放"（依据其 issue/PR）**：

1. **格式/历元是契约**（PR #3992 "New star catalog with Gaia DR3"）：每个 `.cat` 头部带历元/格式信息，`StarMgr` 会校验；九级的跨目录 ID、双星分量、自行区同批生成、互相联动，混用不同代会重复/缺失。
2. **二进制大文件由引擎直接 mmap 信任**：字节错 = 坐标错甚至崩溃，MD5 是最廉价的保险。
3. **真实事故 #4090**：托管文件与配置指纹不符 → 程序 `corrupt, MD5 mismatch` 拒收，随后上游"修 checksum + bump 版本"。此机制就是为"托管/镜像给错文件"兜底。
4. **版本号写进文件名防同名互盖**：下载落到固定路径 `stars/hip_gaia3/<fileName>`，只有改版本后缀（`0v0_14 → 0v0_21`）才能避免旧文件冒充；那次 bump 的原话即 "avoid possible mixture the data"。
5. **托管会变、镜像会旧**（PR #4460）：托管从 GitHub 换到 SourceForge CDN（23 镜像），靠配置指纹兜底。

**更新的动因来自 bug 报告而非排期**：#4156（astroquery 0.4.9：修双星/跨目录 ID、补回 7.50 等缺失星）、#4600（lv0–2 自行区 10 万→20 万年，0 级 636→1124 星）等。**代价**：星表因此与 App 版本绑定，旧 App 无法加载上游新版——这正是 P2 手动导入是否放松校验（§8.3）的取舍根因。

### 9.2 本仓何时需要改配置

| 场景 | 是否要改 |
|---|---|
| 上游 bump `defaultStarsConfig.json`（新 fileName/checksum） | **要**：同步该文件，并把 `checked=true` 的内置 stars0–4 重新下载到**同版本**（否则 `StarMgr` MD5 校验失败、整级被拒） |
| 上游只改 stars5–8（未内置） | 同步配置即可；用户下载时按新 URL/checksum 校验 |
| 同版本文件字节变了（异常） | 不应发生；`.asc` PGP 签名可用于佐证 |

现状（2026-10-09）：本 PR 分支**未**改动 `stars/hip_gaia3/defaultStarsConfig.json`（与基线 `2b2b1d2b` 一致）；内置 stars0–4 的 MD5 与配置逐一相符。

### 9.3 护栏

`scripts/check-ohos-star-catalog.mjs`（接入 `check-ohos.sh`）：逐文件重算内置 `.cat` 的 MD5，比对 `defaultStarsConfig.json.checksum` 与 `data/ohos/catalog-manifest.json`，任何漂移即失败并提示。

> 期望 MD5 共**三处**，更新时必须一起改：① `defaultStarsConfig.json` 的 `checksum`；② `data/ohos/catalog-manifest.json`（由 `auditStars` 生成）；③ `scripts/update-ohos-astronomy-data.mjs` 的 `auditStars.expectedFiles[]`（内置期望值）。

### 9.4 上游更新后的操作

1. `git pull` 取上游新的 `defaultStarsConfig.json`。
2. 按新 `fileName` 重新下载内置 stars0–4 到 `stars/hip_gaia3/`（`node scripts/update-ohos-astronomy-data.mjs --update-stars [--allow-large-star-download]` 或手动）。
3. 同步 ② manifest 与 ③ `expectedFiles[]` 的期望值。
4. `node scripts/check-ohos-star-catalog.mjs` 通过后，再构建并真机核对 `getStarCatalogs.checked` 与 `getLimitMagnitude`。

### 9.5 历史版本可得性（实测）

官方源**只保留最新版，不提供逐版本历史**：

| 源 | 内容 |
|---|---|
| GitHub `stellarium-data` releases | 有 `stars-3.0`（2024-11-30，含 stars_4–stars_8 的**当前**版本 + `.asc`/`.md5`/`.sha256`）与 `stars-2.0`（2017，**Gaia 之前的旧方案**）。`stars-3.0` 的旧中间版（如 `stars_5_1v0_5`）已**被覆盖删除**——#4090 当年的下载 URL 现已 404。 |
| SourceForge `Extra-data-files/` | `stars-3.0/` 只含 stars_4–stars_8 当前版；旧代文件散在 `stars4/`…`stars8/`（`_1v0_0`–`_2`、`_2v0_0`–`_1`，属 stars-2.0 旧方案）。 |
| stars0–stars3 | **任何源都没有**（上游也把它们当"内置"，只随 App 发布）；可下载的只有 stars4–stars8。 |

**结论**：旧 App 需要的那一版**拿不到**——中间版本不存档，stars0–stars3 更是只存在于 App 包内。因此"旧 App 手动装匹配版星表"不可行；只剩两条路：① App 随星表一起更新；② 放松校验（§8.3 方案 A：认文件名模式 + 文件头历元/格式 + `.asc` 签名）。
