## 1. 在 OpenCodeCore 中添加方向应用方法

- [x] 1.1 在 `OpenCodeCore.ts` 中添加 `public static async applyScreenOrientation(context: UIAbilityContext, isLocked: boolean, recreateWhenUnlocked?: boolean): Promise<void>` 方法
- [x] 1.2 在方法内使用 `window.getLastWindow(context)` 获取当前窗口
- [x] 1.3 调用 `window.setPreferredOrientation` 设置 `Orientation.PORTRAIT`（锁定时）；跟随系统时不设置运行时方向，并在 `module.json5` 中声明默认 `auto_rotation_restricted` 与 `launchType: "multiton"`

## 2. 修改 EntryAbility 应用方向

- [x] 2.1 在 `EntryAbility.ets` 的 `onWindowStageCreate` 中，在 `loadContent` 完成后调用 `OpenCodeCore.applyScreenOrientation` 应用当前设置
- [x] 2.2 在 `onForeground` 中重新应用屏幕方向

## 3. 修改 AboutPage 实时应用方向

- [x] 3.1 在 `AboutPage.ets` 中使用 `OpenCodeCore` 复用方向设置工具
- [x] 3.2 在"跟随系统"选项的 `onClick` 中，调用 `OpenCodeCore.applyScreenOrientation` 传入 `false, true`
- [x] 3.3 在"锁定竖屏"选项的 `onClick` 中，调用 `OpenCodeCore.applyScreenOrientation` 传入 `true`

## 4. 测试验证

- [x] 4.1 测试：首次安装应用，锁定竖屏后重启，确认方向正确锁定
- [x] 4.2 测试：在应用内切换到"锁定竖屏"，确认屏幕立即锁定为竖屏
- [x] 4.3 测试：切换到"跟随系统"，确认屏幕可以随设备旋转
- [x] 4.4 测试：应用切换到后台再切回前台，确认方向保持正确
