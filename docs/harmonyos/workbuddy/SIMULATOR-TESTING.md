# 模拟器操作手册（给 AI Agent 看）

> 2026-07-22
> 目标 App：Stellarium（包名 `org.qtproject.example.stellarium`，Ability `QAbility`）
> 模拟器地址：`127.0.0.1:5555`

---

## 0. 坐标系常识（极易搞错）

```
屏幕宽度(px) = 宽度(vp) × 密度(density)
屏幕高度(px) = 高度(vp) × 密度(density)
```
- **uitest dumpLayout 输出的 `bounds`** = 设备像素（px）
- **uitest uiInput click 坐标** = 设备像素（px）
- App 内 C++ 侧收到的是 **vp**（内部会自动 × 密度做投影）
- 常见密度 = 2.0（vp × 2 = px）
- **点坐标前一定要先 `dumpLayout` 拿当前真实的 bounds**，因为面板展开/收起后按钮位置会变

---

## 1. 安装/卸载/启动/停止 App

### 安装 HAP
```bash
# 安装（-r 覆盖重装）
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 install -r /路径/entry-signed.hap
```
- 装包时间：275MB HAP 约 1~2 分钟
- 成功标志：`[Info]App install path:... process:success.`
- 失败标志：`code:9568332 error: install sign info inconsistent`（证书链不一致）或 `code:9568450 must be debug type`（不是 debug 类型）

### 启动 App
```bash
hdc -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```
- 启动后约 10~30 秒渲染星空（Qt 启动 + 加载纹理较慢）
- 如果启动后白屏/卡住，抓 hilog 看

### 停止/重装（App 冻结时必须走这套）
当 App 卡死、`aa start` 没反应时，**普通 `aa force-stop` 清不掉冻结进程**：
```bash
# 1 查进程 PID
hdc -t 127.0.0.1:5555 shell ps -ef | grep stellarium
# 2 强杀
hdc -t 127.0.0.1:5555 shell kill -9 <PID>
# 3 卸载
hdc -t 127.0.0.1:5555 uninstall org.qtproject.example.stellarium
# 4 重装（见上）
# 5 如果还不行 → 重启模拟器
```

### 查看 App 是否在运行
```bash
hdc -t 127.0.0.1:5555 shell aa dump -a | grep stellarium
```

---

## 2. 抓日志（调试的核心手段）

### 基本命令
```bash
# 抓取并过滤 Stellarium 相关日志（推荐）
hdc -t 127.0.0.1:5555 shell hilog -x | grep -iE 'stellarium|Stellarium|qt'
```
- **必须加 `-x`**：不带 `-x` 的 hilog 会阻塞挂起，卡住终端
- 过滤：C++ 侧用 `OH_LOG_Print(LOG_APP, LOG_WARN, ..., "StellariumCpp", ...)` 输出，`qInfo()/qWarning()` 的 tag 是 `stellarium:`，可能被 hilog 限流
- **关键判断**：搜 `StellariumCpp` 看 C++ 桥是否正常；搜 `bridge not ready` 看 ArkUI 是否在等 C++ 初始化；搜 `error`/`signal`/`SIG` 看崩溃

### 清缓冲区
```bash
hdc -t 127.0.0.1:5555 shell hilog -r
```

### 有用的日志关键字
| 关键字 | 含义 |
|---|---|
| `StellariumCpp` | C++ 侧 `OH_LOG_Print` 输出，最可靠 |
| `stellarium:` | Qt `qInfo()/qWarning()` 输出，可能被限流 |
| `bridge not ready` | C++ 桥未就绪，ArkUI 在轮询等待 |
| `command pending` | 命令还在等 Qt 线程处理 |
| `selectAt` | 点星选择操作 |
| `setPanel` | 面板切换操作 |
| `ok:true` | 命令执行成功 |
| `{pending:true}` | 命令已入队、尚未完成 |
| `RESULT_` | 命令结果投递 |
| `SIGABRT`, `SIGSEGV` | 崩溃信号 |

---

## 3. 抓 UI 布局（看屏幕上有什么）

### dumpLayout 命令
```bash
# 在模拟器上 dump 布局到文件
hdc -t 127.0.0.1:5555 shell uitest dumpLayout \
  -p /data/local/tmp/layout.json \
  -b org.qtproject.example.stellarium \
  -m false -i

# 拉回本地
hdc -t 127.0.0.1:5555 file recv /data/local/tmp/layout.json ./layout.json
```
**⚠️ `-m false -i` 两个参数必须加**：`-m false` 不合并窗口，`-i` 不过滤节点，否则底部面板/按钮会被折叠掉看不见。

### 用脚本分析布局
```bash
# 用项目自带的 layout_check.py
python3 ~/stellarium-src/harmonyos/script/layout_check.py layout.json 星 座 搜索

# 或者用 extract_layout.py
python3 ~/stellarium-src/harmonyos/script/extract_layout.py layout.json --clickable
```

**没有 scripts 目录的话**：直接 Python 解析 JSON：
```python
import json
data = json.load(open('layout.json'))
def walk(n, indent=0):
    if 'text' in n and n['text']:
        print('  '*indent, n['text'], n.get('bounds',''))
    for c in n.get('children',[]):
        walk(c, indent+1)
for w in data.get('windows', [data]):
    walk(w)
```

### JSON 布局示例
```json
{
  "node": {
    "id": "search_button",
    "text": "🔍",
    "bounds": [100, 50, 200, 150],  // [left, top, right, bottom] 设备像素
    "clickable": true,
    "children": []
  }
}
```
- `bounds` = `[left, top, right, bottom]` 设备像素
- 点击坐标 = `mid_x = (left+right)/2`，`mid_y = (top+bottom)/2`

---

## 4. 模拟点击和滑动

### 点击（最常用）
```bash
# 单个手指点击 (x, y) —— 坐标是设备像素
hdc -t 127.0.0.1:5555 shell uitest uiInput click <x> <y>
```
**注意**：`uitest uiInput click` 用位置参数，**不是** `-x -y` 标志。

### 滑动
```bash
# 从 (x1,y1) 滑动到 (x2,y2)，duration 毫秒
hdc -t 127.0.0.1:5555 shell uitest uiInput swipe <x1> <y1> <x2> <y2> <duration_ms>
```

### 按键
```bash
# 模拟回车/确认等
hdc -t 127.0.0.1:5555 shell uitest uiInput keyevent ENTER
```

### 输入文本
```bash
hdc -t 127.0.0.1:5555 shell uitest uiInput text "天狼星"
```

---

## 5. 截图

```bash
hdc -t 127.0.0.1:5555 shell uitest screenCap -p /data/local/tmp/screen.png
hdc -t 127.0.0.1:5555 file recv /data/local/tmp/screen.png ./screen.png
```
但更推荐 `dumpLayout` + 文本分析，截图无法可靠判断 UI 状态。

---

## 6. 触摸交互的常见陷阱（必看）

### ⚠️ 第一次点击被启动遮罩吃掉
`isLoading` 遮罩默认 `true`，**只有用户点击遮罩才会消失**（`onClick(() => isLoading=false)`），**不会自动消失**。因此：
- 第一次 `uitest click` 必然命中遮罩，什么 UI 都点不到
- **策略**：先点任意位置一下（消掉遮罩），等 1 秒，再点目标按钮

### ⚠️ 全屏父容器会吞掉子按钮的 onClick
`expandedShell` 全屏父 `Stack` 如果挂了 `onTouch(handleSkyTouch)`，就算配了 `Transparent`，里面的工具栏图标/搜索框/面板按钮的 `onClick` 也会被吞掉（事件被父容器的触摸处理器当画布触摸拦截了）。
- 如果点了搜索按钮但 hilog 里看到 `sky touch down` → `selectAt`，说明命中测试层级有问题
- 修复在代码里：把 `onTouch` 从全屏父容器**下移到一个平级兄弟组件**（已在按这个方向修）

### ⚠️ 点击坐标要从当前 dump 取
面板展开/收起后，按钮坐标会变。**每次点击前重新 dump 布局拿坐标，不要复用旧的**。

### ⚠️ Block 模式会让容器自身的 onClick 失效
给容器节点设 `HitTestMode.Block` 会使**容器自身不响应点击**（仅子组件响应）。如果容器需要接收点击（如 `iconButton` 的 `Stack`），用默认模式即可。

---

## 7. 端到端测试 check-list

装好 App 启动后，按这个顺序验证：

### 7.1 星空渲染
```bash
# 抓 20 秒 hilog
hdc -t 127.0.0.1:5555 shell hilog -x | grep -iE 'stellarium|qWarning|error|SIG' | head -50
```
- 检查有无 `SIGABRT`/`SIGSEGV`（崩溃）
- 检查有无 `bridge not ready` 持续重试（初始化卡住）
- 检查有无 `command pending` 长时间不 resolve（命令桥死锁）

### 7.2 点星选择
```bash
# 1. dump 布局找星空区域（通常是全屏空白区域）
hdc -t ... shell uitest dumpLayout -p /data/local/tmp/l.json -b ... -m false -i
# 2. 随机点击一个星空坐标（比如屏幕中央偏右 100,300）
hdc -t ... shell uitest uiInput click 100 300
# 3. 抓日志看 selectAt 是否命中天体
hdc -t ... shell hilog -x | grep -iE 'selectAt|cleverFind|object'
```
- 应看到 `selectAt` → 搜索到天体名 → 详情面板弹出

### 7.3 工具栏按钮
- 搜索按钮（🔍）：点击后应有搜索面板弹出
- 菜单按钮：展开/收起菜单
- 定位按钮：触发 `setActionChecked`
- 第一下可能被遮罩吃掉，点两次

### 7.4 搜索功能
```bash
# 点击搜索按钮 → 弹出搜索框 → 输入文字
hdc -t ... shell uitest uiInput text "天狼星"
# 等一下搜索建议
hdc -t ... shell hilog -x | grep -i 'fetchSuggestions'
# 点击搜索建议或确认
hdc -t ... shell uitest uiInput click <建议坐标>
```
- 搜索建议应在输入后有日志输出 `fetchSuggestions` 返回结果

### 7.5 详情面板
选中天体后：
- dump 布局看面板是否弹出
- 面板内应有天体名称、坐标、星等、星座等文字
- 等待 10 秒，看高度/方位数值是否变化（**地平坐标随地球自转变化，赤道坐标不动**）

---

## 8. 常见错误速查

| 错误码/信息 | 原因 | 修法 |
|---|---|---|
| `9568450 must be debug type` | HAP 的 profile 类型不是 debug | 用 DevEco auto-sign（debug 类型） |
| `9568332 sign info inconsistent` | 应用证书链和 profile 不匹配 | 统一用 OpenHarmony 证书链 + debug profile，或 DevEco auto-sign |
| `9568328 signature verification failed` | 签名校验失败 | 重新签名 |
| `hilog` 挂起 | 没加 `-x` | 加 `-x`（读完缓冲退出） |
| `bridge not ready` 反复出现 | C++ 库还没加载完 | 等 30 秒以上；或检查 Qt 是否正常初始化 |
| `command pending` 不 resolve | 跨线程命令卡死 | 检查 `runOhosCommandOnQtThread` 是否用了 `BlockingQueuedConnection`（应是非阻塞入队） |
| `uitest click` 点不上按钮 | 遮罩/命中测试层级/坐标过期 | 先消遮罩、坐标重新 dump、检查 Transparent/Block 设置 |
| App 冻结、aa start 没反应 | 进程僵死 | `kill -9` + 卸载 + 重装（见第 1 节） |
