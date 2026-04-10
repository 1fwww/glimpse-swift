# Performance Upgrade Plan

> Goal: 消除所有用户可感知的延迟和卡顿，做到"随叫随到"的 smooth 感。

---

## Phase 1: 选区流畅度（独立，无依赖）

### Step 1.1 — rAF 节流 mousemove
**做什么：** 在 App.jsx 的 `handleMouseMove` 外面包一层 `requestAnimationFrame`，确保每帧最多处理一次 mouse event。

**文件：** `src/App.jsx`

**预期效果：** 消除 >60fps 的事件洪泛。在高刷新率显示器上效果最明显。

**Checkpoint：** 在弱机上拖拽选区，看是否比改前更流畅。

**风险：** 零。纯加一层 wrapper，不改数据流。

**时间：** 5 分钟。

---

### Step 1.2 — useRef + 直接 DOM 操作
**做什么：** 
1. 把 `selection` state 改成 `useRef`
2. mousemove 时直接操作 DOM（`.style.left/top/width/height`）更新选区边框和暗色遮罩
3. 只在 `mouseup` 时 `setState` 一次（给 chat panel 定位、toolbar 定位、cropped image 计算用）

**文件：** `src/App.jsx`

**预期效果：** 拖拽期间零 React re-render。帧率接近 60fps。

**Checkpoint：** 
- 选区拖拽流畅度明显提升
- 松开鼠标后 chat panel 正确定位
- 截图保存的 crop 区域正确
- Window hover 检测仍然正常

**风险：** 中。以下组件读取 `selection` state，需要改成从 ref 读取或只在 mouseup 后使用：
- EditToolbar 定位逻辑
- ChatPanel 定位逻辑
- DrawingCanvas 选区参数
- Window hover 检测
- Dimensions badge 显示
- Cropped image 计算

**时间：** 30-60 分钟。

---

## Phase 2: Chat 窗口即时响应（解决 Cmd+Shift+X 慢 + Pin 慢）

### Step 2.1 — 启动时 pre-warm chat webview
**做什么：**
1. 在 `lib.rs` setup 中，overlay prewarm 完成后 500ms，创建 chat webview（hidden, offscreen: position -9999,-9999）
2. 等 `CHAT_READY` 变 true（React 已 mount）
3. chat webview 常驻后台，不销毁

**文件：** `src-tauri/src/lib.rs`, `src-tauri/src/windows.rs`

**预期效果：** Chat webview 在用户第一次需要时已经 ready。

**Checkpoint：** 
- App 启动后 ~2s，`CHAT_READY` 为 true
- 内存增加 ~30MB（可接受）
- 截图快捷键不受影响（上次 bug 的根因）

**风险：** 中。上次尝试引入了截图快捷键 bug。可能的原因：
- Chat webview 的 React mount 改变了 localStorage（theme 等）
- Chat webview 的 `useThreadManager` 在 mount 时读写文件
- Chat webview 抢占了 Accessory mode 下的窗口焦点

**缓解措施：**
- Pre-warm 在 overlay prewarm 完成后才开始（不竞争）
- Chat webview 创建时 `visible: false` + `position: -9999,-9999`
- 不设 `always_on_top`
- 不改 activation policy
- 创建后立即 `CHAT_READY.store(false)` 等待前端 ready

---

### Step 2.2 — Cmd+Shift+X 使用 pre-warmed chat
**做什么：**
1. `handle_chat_shortcut` 检测到 chat 已存在 → `show()` + `set_focus()` + reposition
2. 不再调 `create_chat_window`（已经存在）
3. 如果 chat 不在屏幕上（-9999），移到屏幕中央

**文件：** `src-tauri/src/lib.rs`

**预期效果：** Cmd+Shift+X 从 ~800ms 降到 < 50ms。

**Checkpoint：**
- 按 Cmd+Shift+X 窗口瞬间出现
- 引用文字正确传入
- 连续 close → reopen → close → reopen 都即时

**风险：** 低（chat 已经 ready，只是 show）

---

### Step 2.3 — close_chat 改为 hide
**做什么：**
1. `close_chat_window` 改为 `w.hide()` + `w.set_always_on_top(false)`（不 `w.close()`）
2. 下次使用时 `show()` + reposition

**文件：** `src-tauri/src/windows.rs`

**预期效果：** 关闭后再打开是即时的（不需要重新创建 webview）。

**Checkpoint：**
- 关闭 chat → 再打开 → 即时出现
- 关闭 chat 后 dock icon 正确处理（Accessory mode）
- 隐藏的 chat 不影响截图快捷键
- 隐藏的 chat 不出现在 Cmd+Tab

**风险：** 中。上次尝试 hide 导致了问题。需要确保：
- hide 后 `IS_ACCESSORY` 正确设置
- hide 后 `has_other` 窗口检测不把隐藏的 chat 算在内
- 前端状态在 show 后正确恢复

---

### Step 2.4 — Pin 使用 pre-warmed chat
**做什么：**
1. `pin_chat` 检测到 chat 已存在 → 直接 reposition + emit data + show
2. 不再创建新 webview
3. 关闭 overlay 和 show chat 之间做 50ms 重叠（overlay 先隐藏，chat 立即显示）

**文件：** `src-tauri/src/windows.rs`

**预期效果：** Pin 从 ~1s 降到 < 100ms。

**Checkpoint：**
- 截图 → 聊天 → Pin → chat 窗口瞬间出现在正确位置
- Thread 数据正确传输
- 截图附件正确显示
- Overlay 干净关闭

**风险：** 中。数据传输时序：
- emit `load-thread-data` 必须在 chat 的 React 已 mount 后
- 如果 pre-warmed 且 CHAT_READY=true，直接 emit 即可
- 如果 chat 正在显示其他 thread，需要先 emit 切换

---

## Phase 3: 截图连续触发（双 overlay）

### Step 3.0 — 临时方案：延长 reuse window
**做什么：** 把 `close_overlay` 的 300ms delay 改成 2000ms。

**文件：** `src-tauri/src/windows.rs` (一行改动)

**预期效果：** 2 秒内的重新触发都使用旧 overlay（即时）。覆盖 90% 场景。

**Checkpoint：**
- 截图 → 退出 → 1 秒后再截图 → 成功
- 全屏下截图 → 退出 → 切 Space → 截图 → 新 overlay 在正确 Space

**风险：** 低。但全屏 Space 关联延迟到 2s 后才更新。如果用户在全屏 A 截图 → 退出 → 1 秒内切到全屏 B → 再截图 → overlay 可能在 A 的 Space 上。

**时间：** 1 分钟。

---

### Step 3.1 — 双 overlay 架构（如果 3.0 不够）
**做什么：**
1. `close_overlay` 不销毁旧 overlay，只 hide
2. 立即开始创建 overlay-standby（新 Space 关联）
3. overlay-standby ready 后：销毁旧 overlay
4. 下次截图使用 standby（rename 为 active）
5. 始终保持一个 hidden standby 备用

**文件：** `src-tauri/src/windows.rs`, `src-tauri/src/lib.rs`

**预期效果：** 任何时间间隔的重新触发都即时。

**Checkpoint：**
- 快速连续截图 5 次 → 全部成功
- 截图 → 等 1s → 截图 → 等 3s → 截图 → 全部成功
- 全屏 → 截图 → 退出 → 切 Space → 截图 → 正确 Space
- ESC 在两个 overlay 上都能工作

**风险：** 高。
- 两个 overlay 的 ESC 检测（CGEventTap 不区分窗口）
- 两个 overlay 的 `screen-captured` event 路由
- 窗口命名（Tauri 要求 unique label）
- `get_webview_window("overlay")` 的引用管理
- 全屏 Space 关联的正确性

**时间：** 3-5 小时。

---

## Phase 4: 验证 + 边界测试

### 测试矩阵

| 场景 | 预期 |
|---|---|
| 快速连续截图 5 次 | 全部成功，零延迟 |
| 截图 → 等 1s → 截图 → 等 3s → 截图 | 全部成功 |
| 全屏 app 下截图 → 退出 → 再截图 | 正确 Space |
| Cmd+Shift+X → 关 → 立即再 Cmd+Shift+X | 即时打开 |
| Cmd+Shift+X → 关 → 等 5s → Cmd+Shift+X | 即时打开 |
| 截图 → Pin → 关 chat → 再截图 | 全部即时 |
| 截图 → Pin → Cmd+Shift+X | Chat 已被 pin 占用，正确处理 |
| 选区拖拽（弱机） | 接近 60fps |
| 截图 → 标注 → 保存 → 截图 | 全部即时 |

---

## 执行顺序

```
Day 1:
  Phase 1 (Step 1.1 + 1.2) — 选区流畅度
  Phase 2 (Step 2.1) — Chat pre-warm
  
Day 2:
  Phase 2 (Step 2.2 + 2.3 + 2.4) — Chat 即时 + Pin 即时
  Phase 3 (Step 3.0) — 临时 reuse window 延长
  Phase 4 — 全量验证

Day 3 (if needed):
  Phase 3 (Step 3.1) — 双 overlay（仅当 3.0 不够时）
```

---

## 成功指标

| 指标 | 当前 | 目标 |
|---|---|---|
| 截图触发延迟 | 0-800ms (不稳定) | < 50ms (100% 稳定) |
| 选区拖拽帧率 | ~30-40fps (弱机) | ~55-60fps |
| Cmd+Shift+X 响应 | ~800ms | < 50ms |
| 截图→Pin | ~1000ms | < 100ms |
| 内存增加 | — | +30-50MB (可接受) |
