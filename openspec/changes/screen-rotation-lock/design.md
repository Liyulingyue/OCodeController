## 背景

当前旋转锁定的实现存在两部分问题：

### HarmonyOS 端（`EntryAbility.ets`）

`EntryAbility` 已导入 `window` from `@kit.ArkUI`，但从未使用它来控制屏幕方向。`EntryAbility.onWindowStageCreate` 创建窗口时没有读取 `rotationLocked` 设置，导致无论用户选择什么，屏幕方向都由系统决定。

```typescript
// EntryAbility.ets - 当前 onWindowStageCreate
onWindowStageCreate(windowStage: window.WindowStage): void {
  // 没有读取或应用 rotationLocked 设置
  windowStage.loadContent('pages/MainPage', ...);
}
```

### Android 端（`EntryEntryAbilityActivity.java`）

`applyRotationLock()` 方法通过反射访问 `AppStorage`，这种方式的可行性不稳定：
- 反射调用 `AppStorage.getInstance()` 和 `getBool("rotationLocked", false)` 可能在不同版本中失败
- ArkUI-X 的 `AppStorage` 可能尚未初始化，导致读取到默认值

## 目标 / 非目标

**目标：**
- 在 HarmonyOS 设备上正确实现屏幕竖屏锁定
- 用户切换设置后生效，无需用户手动重启应用
- 在窗口创建时正确应用锁定设置

**非目标：**
- 不实现横屏锁定（仅支持竖屏锁定和跟随系统）
- 不改变 Android/iOS ArkUI-X 端的实现（保持现状）

## 关键决策

### 1. HarmonyOS 端：使用 window API 设置方向

**决策**：在 `module.json5` 的 `EntryAbility` 上声明 `orientation: "auto_rotation_restricted"` 作为应用默认方向，并声明 `launchType: "multiton"` 允许切回跟随系统时创建新窗口。运行时仅在锁定竖屏时设置窗口方向；未锁定时不调用 `setPreferredOrientation`，让 ability manifest 接管。

关键 API：
```typescript
if (isLocked) {
  const win = await window.getLastWindow(context);
  await win.setPreferredOrientation(window.Orientation.PORTRAIT);
}
```

- `Orientation.PORTRAIT`：锁定竖屏
- 未锁定时不设置运行时方向：避免 `UNSPECIFIED` 在 ArkUI-X 模拟器上把窗口带回竖屏
- `module.json5` 的 `auto_rotation_restricted`：默认跟随系统自动旋转锁控制，避免在 ArkTS 代码中引用非 crossplatform enum symbol
- `module.json5` 的 `launchType: "multiton"`：用于切回跟随系统时启动新窗口，清除旧窗口上的 `PORTRAIT` 偏好

### 2. 设置变更时实时应用

**决策**：在 `AboutPage.ets` 的设置切换回调中通过 `OpenCodeCore.applyScreenOrientation` 应用方向变更，方向控制和窗口重建逻辑只封装在 `OpenCodeCore` 中。

```typescript
.onClick(() => {
  this.isRotationLocked = true;
  this.core.setRotationLocked(true);
  AppStorage.setOrCreate<boolean>('rotationLocked', true);
  OpenCodeCore.applyScreenOrientation(context, true);
})
```

切回跟随系统时，旧窗口已经有 `PORTRAIT` 运行时偏好，`Orientation.UNSPECIFIED` 不能可靠恢复到 manifest 自动旋转。因此保存 `rotationLocked=false` 后启动新的 `EntryAbility` 实例并结束旧实例，新窗口不再设置运行时方向，由 manifest 接管。

### 3. 抽取通用方向设置工具

**决策**：在 `OpenCodeCore` 中添加一个静态方法 `applyScreenOrientation`，供 `EntryAbility` 和 `AboutPage` 共用。

```typescript
public static async applyScreenOrientation(
  context: UIAbilityContext,
  isLocked: boolean,
  recreateWhenUnlocked: boolean = false
): Promise<void> {
  if (isLocked) {
    const win = await window.getLastWindow(context);
    await win.setPreferredOrientation(window.Orientation.PORTRAIT);
    return;
  }
  if (recreateWhenUnlocked) {
    await context.startAbility(restartWant);
    await context.terminateSelf();
  }
}
```

## 风险 / 权衡

- **[风险] `getLastWindow` 异步失败**：在窗口未就绪时调用可能失败。→ **缓解**：仅锁定竖屏时调用，并在 `onWindowStageCreate` 中等待内容加载后应用。
- **[风险] 平板设备方向**：平板通常默认横屏，锁定竖屏可能体验不佳。→ **缓解**：仅在"锁定竖屏"选项下生效，平板用户通常选择"跟随系统"。
- **[风险] 权限问题**：某些设备可能限制应用设置方向。→ **缓解**：`setPreferredOrientation` 是标准 API，大多数设备支持。
- **[权衡] 跟随系统需要窗口重建**：crossplatform window API 不支持运行时设置 `AUTO_ROTATION_RESTRICTED`，`UNSPECIFIED` 又不能可靠恢复自动旋转。→ **缓解**：只在用户从竖屏锁定切回跟随系统时重建 ability 窗口，生命周期恢复时不重建。
