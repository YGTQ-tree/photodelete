/**
 * 设置持久化（preferences）。
 * 键与默认值见 docs/ARCHITECTURE.md §3.3。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

import { DEFAULT_KEEP_HOURS, KEEP_FOREVER } from '../domain/RetentionPolicy';

const STORE_NAME: string = 'photo_delete_settings';
const KEY_KEEP_HOURS: string = 'default_keep_hours';
const KEY_NOTIFY: string = 'notify_on_materialize';
const KEY_SCHEMA: string = 'schema_version';

export class SettingsRepo {
  private prefs: preferences.Preferences;

  private constructor(prefs: preferences.Preferences) {
    this.prefs = prefs;
  }

  static async open(context: common.Context): Promise<SettingsRepo> {
    const options: preferences.Options = { name: STORE_NAME };
    const prefs: preferences.Preferences = await preferences.getPreferences(context, options);
    return new SettingsRepo(prefs);
  }

  /** 默认保留时长（小时）；KEEP_FOREVER(0) 表示永久 */
  async defaultKeepHours(): Promise<number> {
    const value: preferences.ValueType = await this.prefs.get(KEY_KEEP_HOURS, DEFAULT_KEEP_HOURS);
    const hours: number = Number(value);
    return Number.isNaN(hours) ? DEFAULT_KEEP_HOURS : hours;
  }

  async setDefaultKeepHours(hours: number): Promise<void> {
    const safe: number = hours < 0 ? KEEP_FOREVER : hours;
    await this.prefs.put(KEY_KEEP_HOURS, safe);
    await this.prefs.flush();
  }

  async notifyOnMaterialize(): Promise<boolean> {
    const value: preferences.ValueType = await this.prefs.get(KEY_NOTIFY, true);
    return Boolean(value);
  }

  async setNotifyOnMaterialize(enabled: boolean): Promise<void> {
    await this.prefs.put(KEY_NOTIFY, enabled);
    await this.prefs.flush();
  }

  async schemaVersion(): Promise<number> {
    const value: preferences.ValueType = await this.prefs.get(KEY_SCHEMA, 1);
    return Number(value);
  }
}
