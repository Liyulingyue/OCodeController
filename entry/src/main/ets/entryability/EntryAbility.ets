import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { OpenCodeCore } from '../core/OpenCodeCore';

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: Object): Promise<void> {
    console.info('[EntryAbility] Ability onCreate');
  }

  onDestroy(): void {
    console.info('[EntryAbility] Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('[EntryAbility] Ability onWindowStageCreate');

    const core = OpenCodeCore.getInstance();
    core.setSessionsChangedCallback((timestamp: number) => {
      AppStorage.setOrCreate<string>('refreshSessionsNow', timestamp.toString());
    });

    const initPromise = this.initCore(core);

    windowStage.loadContent('pages/MainPage', async (err) => {
      if (err.code) {
        console.error('[EntryAbility] Failed to load the content. Cause:', JSON.stringify(err));
        return;
      }
      console.info('[EntryAbility] Succeeded in loading the content.');
      await initPromise;
      await this.applyCurrentScreenOrientation(core);
    });
  }

  private async initCore(core: OpenCodeCore): Promise<void> {
    try {
      await core.init(this.context);
    } catch (e) {
      console.error('[EntryAbility] init failed:', e);
    }
    core.applyTheme(core.getThemeName(), core.getDarkMode());
    AppStorage.setOrCreate<string>('refreshSessionsNow', Date.now().toString());
  }

  private async applyCurrentScreenOrientation(core: OpenCodeCore): Promise<void> {
    try {
      await OpenCodeCore.applyScreenOrientation(this.context, core.isRotationLocked());
    } catch (e) {
      console.error('[EntryAbility] Failed to apply screen orientation:', e);
    }
  }

  onWindowStageDestroy(): void {
    console.info('[EntryAbility] Ability onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('[EntryAbility] Ability onForeground');
    const core = OpenCodeCore.getInstance();
    this.applyCurrentScreenOrientation(core);
  }

  onBackground(): void {
    console.info('[EntryAbility] Ability onBackground');
  }
}
