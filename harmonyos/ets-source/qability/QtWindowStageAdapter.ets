import Window from '@ohos.window';
import { AsyncCallback, Callback, BusinessError } from '@ohos.base';
import { bundleManager } from '@kit.AbilityKit';
import { WindowNativeNodeCreateInfo } from '../pages/StellariumTypes';
import { hasCurrentPrivacyConsent } from './PrivacyConsent';
import hilog from '@ohos.hilog';

export default class QtWindowStageAdapter implements Window.WindowStage {
  private stage: Window.WindowStage;
  private storage: LocalStorage;

  constructor(stage: Window.WindowStage, storage: LocalStorage) {
    this.stage = stage;
    this.storage = storage;
  }

  getMainWindow(): Promise<Window.Window>;
  getMainWindow(callback: AsyncCallback<Window.Window>): void;
  getMainWindow(callback?: AsyncCallback<Window.Window>): Promise<Window.Window> | void {
    if (callback) this.stage.getMainWindow(callback);
    else return this.stage.getMainWindow();
  }

  getMainWindowSync(): Window.Window { return this.stage.getMainWindowSync(); }

  createSubWindow(name: string): Promise<Window.Window>;
  createSubWindow(name: string, callback: AsyncCallback<Window.Window>): void;
  createSubWindow(name: string, callback?: AsyncCallback<Window.Window>): Promise<Window.Window> | void {
    if (callback) this.stage.createSubWindow(name, callback);
    else return this.stage.createSubWindow(name);
  }

  createSubWindowWithOptions(name: string, options: Window.SubWindowOptions): Promise<Window.Window> {
    return this.stage.createSubWindowWithOptions(name, options);
  }

  getSubWindow(): Promise<Array<Window.Window>>;
  getSubWindow(callback: AsyncCallback<Array<Window.Window>>): void;
  getSubWindow(callback?: AsyncCallback<Array<Window.Window>>): Promise<Array<Window.Window>> | void {
    if (callback) this.stage.getSubWindow(callback);
    else return this.stage.getSubWindow();
  }

  private bindQtContent(path: string, storage?: LocalStorage): void {
    if (!hasCurrentPrivacyConsent()) throw new Error('Qt content requires current privacy consent');
    if (path !== 'pages/MainWindowNativeNode') throw new Error(`Unsupported Qt main page: ${path}`);
    const info = storage?.get<WindowNativeNodeCreateInfo>('createInfo');
    if (info === undefined) throw new Error('Qt main page createInfo is missing');
    this.storage.setOrCreate<WindowNativeNodeCreateInfo>('createInfo', info);
    AppStorage.setOrCreate('stellariumQtContentReady', true);
    hilog.info(0, 'StellariumPrivacy', '[privacy-probe] phase=qt-content-bound-existing-window');
  }

  loadContent(path: string, storage: LocalStorage, callback: AsyncCallback<void>): void;
  loadContent(path: string, storage?: LocalStorage): Promise<void>;
  loadContent(path: string, callback: AsyncCallback<void>): void;
  loadContent(path: string, storageOrCallback?: LocalStorage | AsyncCallback<void>, callback?: AsyncCallback<void>): Promise<void> | void {
    const completion = typeof storageOrCallback === 'function' ? storageOrCallback : callback;
    const storage = typeof storageOrCallback === 'function' ? undefined : storageOrCallback;
    const bind = async (): Promise<void> => { this.bindQtContent(path, storage); };
    if (completion) {
      void bind().then(() => {
        const success: BusinessError = { code: 0, name: '', message: '' };
        completion(success);
      }).catch((error: Error) => {
        const failure: BusinessError = { code: 1300002, name: error.name, message: error.message };
        completion(failure);
      });
    } else return bind();
  }

  loadContentByName(name: string, storage: LocalStorage, callback: AsyncCallback<void>): void;
  loadContentByName(name: string, callback: AsyncCallback<void>): void;
  loadContentByName(name: string, storage?: LocalStorage): Promise<void>;
  loadContentByName(name: string, storageOrCallback?: LocalStorage | AsyncCallback<void>, callback?: AsyncCallback<void>): Promise<void> | void {
    throw new Error(`Named Qt main pages are unsupported: ${name}`);
  }

  releaseUIContent(): Promise<void> { return this.stage.releaseUIContent(); }

  on(eventType: 'windowStageEvent', callback: Callback<Window.WindowStageEventType>): void;
  on(eventType: 'windowStageLifecycleEvent', callback: Callback<Window.WindowStageLifecycleEventType>): void;
  on(eventType: 'windowStageClose', callback: Callback<void>): void;
  on(eventType: string, callback: Callback<Window.WindowStageEventType> | Callback<Window.WindowStageLifecycleEventType> | Callback<void>): void {
    if (eventType === 'windowStageEvent') this.stage.on(eventType, callback as Callback<Window.WindowStageEventType>);
    else if (eventType === 'windowStageLifecycleEvent') this.stage.on(eventType, callback as Callback<Window.WindowStageLifecycleEventType>);
    else if (eventType === 'windowStageClose') this.stage.on(eventType, callback as Callback<void>);
    else throw new Error(`Unsupported window stage event: ${eventType}`);
  }

  off(eventType: 'windowStageEvent', callback?: Callback<Window.WindowStageEventType>): void;
  off(eventType: 'windowStageLifecycleEvent', callback?: Callback<Window.WindowStageLifecycleEventType>): void;
  off(eventType: 'windowStageClose', callback?: Callback<void>): void;
  off(eventType: string, callback?: Callback<Window.WindowStageEventType> | Callback<Window.WindowStageLifecycleEventType> | Callback<void>): void {
    if (eventType === 'windowStageEvent') this.stage.off(eventType, callback as Callback<Window.WindowStageEventType>);
    else if (eventType === 'windowStageLifecycleEvent') this.stage.off(eventType, callback as Callback<Window.WindowStageLifecycleEventType>);
    else if (eventType === 'windowStageClose') this.stage.off(eventType, callback as Callback<void>);
    else throw new Error(`Unsupported window stage event: ${eventType}`);
  }

  setDefaultDensityEnabled(enabled: boolean): void { this.stage.setDefaultDensityEnabled(enabled); }
  setCustomDensity(density: number, applyToSubWindow?: boolean): void { this.stage.setCustomDensity(density, applyToSubWindow); }
  removeStartingWindow(): Promise<void> { return this.stage.removeStartingWindow(); }
  setWindowModal(isModal: boolean): Promise<void> { return this.stage.setWindowModal(isModal); }
  setWindowRectAutoSave(enabled: boolean, isSaveBySpecifiedFlag?: boolean): Promise<void> {
    return isSaveBySpecifiedFlag === undefined ? this.stage.setWindowRectAutoSave(enabled) : this.stage.setWindowRectAutoSave(enabled, isSaveBySpecifiedFlag);
  }
  isWindowRectAutoSave(): Promise<boolean> { return this.stage.isWindowRectAutoSave(); }
  setSupportedWindowModes(modes: Array<bundleManager.SupportWindowMode>, grayOutMaximizeButton?: boolean): Promise<void> {
    return grayOutMaximizeButton === undefined ? this.stage.setSupportedWindowModes(modes) : this.stage.setSupportedWindowModes(modes, grayOutMaximizeButton);
  }
}
