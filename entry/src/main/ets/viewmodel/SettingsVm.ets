/**
 * 设置页的编排层。
 */

import { AppCore } from '../app/AppCore';
import { DEFAULT_KEEP_HOURS } from '../domain/RetentionPolicy';

export class SettingsState {
  keepHours: number = DEFAULT_KEEP_HOURS;
  notify: boolean = true;
}

export class SettingsVm {
  private core: AppCore;

  constructor(core: AppCore) {
    this.core = core;
  }

  async load(): Promise<SettingsState> {
    const state: SettingsState = new SettingsState();
    state.keepHours = await this.core.settings.defaultKeepHours();
    state.notify = await this.core.settings.notifyOnMaterialize();
    return state;
  }

  async setKeepHours(hours: number): Promise<void> {
    await this.core.settings.setDefaultKeepHours(hours);
  }

  async setNotify(enabled: boolean): Promise<void> {
    await this.core.settings.setNotifyOnMaterialize(enabled);
  }
}
