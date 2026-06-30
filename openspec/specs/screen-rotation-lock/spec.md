# screen-rotation-lock Specification

## Purpose
TBD - created by archiving change screen-rotation-lock. Update Purpose after archive.
## Requirements
### Requirement: 窗口创建时应用旋转锁定设置

系统在应用窗口创建时 MUST 根据当前旋转锁定设置应用屏幕方向。

#### Scenario: 窗口创建且旋转已锁定
- **当** `EntryAbility.onWindowStageCreate` 被调用且 `rotationLocked` 为 `true` 时
- **则** 系统将屏幕方向设置为竖屏（`Orientation.PORTRAIT`）

#### Scenario: 窗口创建且旋转未锁定
- **当** `EntryAbility.onWindowStageCreate` 被调用且 `rotationLocked` 为 `false` 时
- **则** 系统不设置运行时窗口方向偏好
- **并且** 窗口由系统和 ability manifest 中的 `auto_rotation_restricted` 决定后续旋转

### Requirement: 设置变更时实时应用

系统在用户切换旋转锁定设置后 MUST 应用屏幕方向变更，无需用户手动重启应用。

#### Scenario: 用户选择"锁定竖屏"
- **当** 用户点击"锁定竖屏"选项时
- **则** 系统将 `rotationLocked` 保存到本地存储
- **并且** 将 `AppStorage` 中的 `rotationLocked` 设置为 `true`
- **并且** 立即将屏幕方向设置为竖屏

#### Scenario: 用户选择"跟随系统"
- **当** 用户点击"跟随系统"选项时
- **则** 系统将 `rotationLocked` 保存到本地存储
- **并且** 将 `AppStorage` 中的 `rotationLocked` 设置为 `false`
- **并且** 系统启动新的 `EntryAbility` 实例并结束旧实例，以清除旧窗口上的运行时竖屏偏好
- **并且** 新窗口由 ability manifest 中的 `auto_rotation_restricted` 跟随系统旋转

### Requirement: 应用切换前台时重新应用设置

系统在应用从后台切换到前台时 MUST 重新应用旋转锁定设置，以应对系统方向可能在应用后台时被改变的情况。

#### Scenario: 应用从后台切换到前台
- **当** `EntryAbility.onForeground` 被调用时
- **则** 系统读取当前 `rotationLocked` 设置
- **并且** 当 `rotationLocked` 为 `true` 时重新应用竖屏方向
- **并且** 当 `rotationLocked` 为 `false` 时不设置运行时窗口方向偏好

