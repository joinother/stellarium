# 手机端 UI 重构交接文档

> 生成时间：2026-07-27 18:00
> 状态：已回退到 `ba34693f4e`，手机端 UI 功能缺失，需重新实现
> 目标接收方：CodeX

---

## 1. 背景

### 1.1 问题描述

2026-07-27 下午，在尝试将手机端（compactShell）和平板端（expandedShell）UI 分离时，引入了一个**破坏性改动**：

**commit 627b2f054a** `feat: 重建独立手机端 compactShell`

该 commit 使用了**全屏 Column + `HitTestMode.Block`** 覆盖整个触摸层，导致：
- ❌ 星图无法拖动（XComponent 收不到触摸事件）
- ❌ 星星无法点击
- ❌ 底部 Dock 被触摸事件吞掉
- ❌ `isUiPoint` 坐标判断全部失效

### 1.2 当前回退状态

已将 `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets` 回退到 **ba34693f4e**（2026-07-27 03:32 版本）。

**当前版本状态**：
- ✅ 星图渲染正常（FPS ≈ 80+）
- ✅ 拖动/点击可用（触摸挂在 `Blank` 上）
- ✅ 平板端 expandedShell 完整
- ✅ 手机端 compactShell（原版简化版）可用
- ❌ **手机端增强功能全部缺失**

---

## 2. 手机端缺失功能清单

以下功能均在 commit `627b2f054a` 中实现，现已随回退丢失：

### 2.1 左侧琉璃工具栏
```
位置: compactShell 内，左侧屏幕边缘
内容: 垂直排列的圆形按钮
  - 放大 (zoom_in)     → this.zoomStep(0.5)
  - 缩小 (zoom_out)    → this.zoomStep(2.0)
  - 陀螺仪 (gyro)      → this.toggleGyroscope()
  - 音乐 (audio)       → this.toggleMusic()

样式:
  - 44x44 圆形
  - rgba(35, 55, 85, 0.72) 半透明深蓝底
  - backdropBlur(30) 磨砂玻璃
  - rgba(160, 200, 240, 0.40) 1.5px 边框
  - borderRadius(22)
  - springMotion(0.42, 0.85) 动画
```

### 2.2 底部透明 Dock
```
位置: compactShell 底部，与星图底部齐平
内容: 搜索 / 时间 / 定位 / 图层 / 菜单 / 设置 / 三点更多

样式:
  - 半透明胶囊容器
  - backdropBlur(30)
  - 独立圆形按钮 + 三点更多按钮
  - 三点按钮旋转动画 (动画展开时 45deg)
```

### 2.3 底部半屏面板 (bottomSheetPanel)
```
位置: 从底部弹出的半屏面板
内容: 可拖拽的内容面板，用于显示详情/设置等

交互:
  - 三段式拖拽限位: 0% (关闭) / 60% / 90%
  - >90% 弹性 overscroll
  - springMotion(0.36, 0.72) 果冻 Q 弹回弹
  - 拖拽手柄 (drag handle)
```

### 2.4 更多功能抽屉 (compactDrawer)
```
位置: 从底部弹出的抽屉
内容: 65% 屏幕高度的功能列表

交互:
  - 从底部弹出动画
  - 下拉关闭手势
  - 弹性滚动
```

### 2.5 底部详情卡片 (bottomDetailCard)
```
位置: 星图底部，Dock 上方
内容: 选中天体的详情显示

样式:
  - 88% 屏宽
  - 拖拽手柄
  - PanGesture 可拖动
  - 位置记忆
```

---

## 3. 关键实现代码

> 以下代码均来自 commit `627b2f054a`，可直接参考实现。

### 3.1 状态变量（需新增到 WindowNativeNode struct）

```typescript
// 文件: build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets
// 建议添加到 L215 附近

@State private cardDragStartX: number = 0
@State private cardDragStartY: number = 0
@State private sheetHeightPct: number = 70
@State private sheetDragStartY: number = 0
@State private sheetDragStartPct: number = 70
```

### 3.2 harmonyShell() — 设备自动切换

```typescript
// 替换原 build() 中的布局选择逻辑

harmonyShell() {
  Stack({ alignContent: Alignment.Bottom }) {
    if (this.isExpandedLayout) {
      this.expandedShell()
    } else {
      this.compactShell()
    }
  }
  .width('100%')
  .height('100%')
}
```

### 3.3 compactShell() — 完整实现

> ⚠️ **关键设计原则**：触摸层分离！
> - `Blank` 只负责星图触摸（handleSkyTouch）
> - UI 组件（工具栏/Dock/抽屉）各自处理自己的 onClick
> - **禁止**使用全屏 Column + HitTestMode.Block 覆盖

```typescript
// 参考 commit 627b2f054a 中的实现，核心结构：

compactShell() {
  Stack({ alignContent: Alignment.Bottom }) {
    // 1. 星图触摸层（全屏）- 最重要！
    Column()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => {
        this.handleSkyTouch(event)
      })

    // 2. 左侧垂直工具栏（琉璃风格）
    Column({ space: 6 }) {
      // 放大按钮
      Stack() {
        Image(this.getIcon('zoom_in', false))
          .width(24).height(24).fillColor(this.nmText())
      }
        .width(44).height(44)
        .backgroundColor('rgba(35, 55, 85, 0.72)')
        .backdropBlur(30)
        .border({ width: 1.5, color: 'rgba(160, 200, 240, 0.40)' })
        .borderRadius(22)
        .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.28)', offsetX: 0, offsetY: 4 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .animation({ duration: 200, curve: curves.springMotion(0.42, 0.85) })
        .onClick(() => { this.zoomStep(0.5) })

      // 缩小按钮
      Stack() { /* ... */ }
        .onClick(() => { this.zoomStep(2.0) })

      // 陀螺仪按钮
      Stack() { /* ... */ }
        .onClick(() => { this.toggleGyroscope() })

      // 音乐按钮
      Stack() { /* ... */ }
        .onClick(() => { this.toggleMusic() })
    }
    .position({ x: 12, y: 60 })
    .zIndex(3)

    // 3. 底部 Dock
    this.compactDock()

    // 4. 更多功能抽屉
    if (this.drawerVisible) {
      Stack() { this.compactDrawer() }
        .zIndex(50)
    }

    // 5. 底部半屏面板
    if (this.panelVisible) {
      this.bottomSheetPanel()
    }

    // 6. 底部详情卡片
    if (this.infoWinVisible) {
      Stack() { this.bottomDetailCard() }
        .zIndex(50)
    }
  }
  .width('100%')
  .height('100%')
  .zIndex(1)
}
```

### 3.4 isUiPoint() — 紧凑布局坐标判断

```typescript
// 关键修改：紧凑布局下，Dock 区域由组件自身 onClick 处理
// 不应在 isUiPoint 中拦截

private isUiPoint(x: number, y: number): boolean {
  // ... 前置判断 ...

  if (!this.isExpandedLayout) {
    // 紧凑布局：底部 Dock 由 compactDock 组件自身 onClick 处理
    // 不在此处拦截，让星图触摸事件正常传递
    return false  // 关键！不拦截底部区域
  }

  // 平板布局：原逻辑
  return y >= this.skyHeight - 80
}
```

---

## 4. 技术踩坑记录

### 4.1 触摸层架构（核心教训）

**正确的触摸架构**（ba34693f4e 版本）：
```
Stack (全屏)
├── XComponent (星图渲染)
├── Blank (onTouch → handleSkyTouch)  ← 星图触摸
├── Column (UI 组件)
│   ├── Row (按钮) → onClick → triggerAction
│   └── ...
```

**错误的触摸架构**（627b2f054a 版本）：
```
Stack (全屏)
├── Column (全屏 Column + HitTestMode.Block)  ← 拦截所有触摸！
│   └── onTouch (只在这一层生效)
├── Column (UI 组件)
│   └── onClick → 被上面的 Column 吞掉了！
```

### 4.2 构建缓存问题

**问题**：修改源码后，hvigor 可能使用旧的 ArkTS 字节码缓存。

**解决方案**：
```bash
# 必须先 clean 再 build
hvigorw clean --no-daemon
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

### 4.3 gitignore 注意事项

`build/` 目录在 `.gitignore` 中，但 `build/libstellarium-harmonyos/entry/src/main/ets/` 下的文件已被 git 跟踪。

添加修改时需要：
```bash
git add -f build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets
```

---

## 5. 关键 Git Commit 参考

| Commit | 说明 | 状态 |
|--------|------|------|
| `ba34693f4e` | 凌晨验证通过版本，当前基线 | ✅ 当前 |
| `627b2f054a` | 手机端 UI 重建（有 bug） | ❌ 已回退，代码在历史中 |
| `653eaf8b27` | 本次回退 commit | ✅ 当前 HEAD |

查看重建版本代码：
```bash
# 查看完整的 627b2f054a 版本 ets 文件
git show 627b2f054a:build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets
```

---

## 6. 重新实现建议

### 6.1 分步实施

1. **第一步**：恢复 `compactShell` 的基本结构（左侧工具栏 + 底部 Dock）
   - 保持 `Blank` 作为触摸层
   - 逐步添加 UI 组件
   - 每添加一个组件测试触摸是否正常

2. **第二步**：添加 `bottomSheetPanel`（半屏面板）
   - 实现三段式拖拽
   - 测试拖拽流畅度

3. **第三步**：添加 `compactDrawer`（更多功能抽屉）
   - 实现弹出/关闭动画
   - 测试手势

4. **第四步**：添加 `bottomDetailCard`（详情卡片）
   - 实现拖拽
   - 测试 PanGesture

### 6.2 验证清单

- [ ] 手机端拖动星图流畅（FPS > 60）
- [ ] 手机端点击星星能选中
- [ ] 左侧工具栏按钮可点击
- [ ] 底部 Dock 按钮可点击
- [ ] 半屏面板可拖拽
- [ ] 抽屉可弹出/关闭
- [ ] 详情卡片可拖动
- [ ] 平板端 expandedShell 不受影响
- [ ] 双设备同时测试通过

---

## 7. 相关文件路径

| 文件 | 说明 |
|------|------|
| `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets` | 主 ArkUI 文件，需修改 |
| `harmonyos/ets-source/pages/MainWindowNativeNode.ets` | ets 源文件（同步修改） |
| `src/StelMainView.cpp` | C++ 渲染核心（已回退到 ba34693f4e） |
| `build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp` | NAPI 桥接层 |
