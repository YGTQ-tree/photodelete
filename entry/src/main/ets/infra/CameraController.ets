/**
 * 相机封装（T03）。实现路径**严格按 ADR-001 的实测结论**：
 *   `photoOutput.on('photoAvailable')` → `Photo.main.getComponent(ComponentType.JPEG).byteBuffer`
 *   → 回调把原始 JPEG 字节交给上层落盘。全程不申请媒体库权限。
 *
 * T03-A 增强：变焦 / 闪光灯 / 点按对焦 / 曝光补偿 / 前后摄切换 / 能力查询。
 * 这些控制项由 `PhotoSession` 实现的 Zoom / Flash / Focus / AutoExposure 接口提供。
 * 页面不直接碰 Camera Kit —— 相机可替换，也便于以后用假实现做 UI 测试。
 */

import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { Size2D, pickClosestRatio, ratioOf } from '../common/AspectFit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteCam';

/**
 * 预览流面积上限（≈2 MP，1920x1080 量级）。
 * 真机实测：竖屏时容器接近 1:1，不加限制会挑到 **2448x2448（6 MP）** 的预览流，
 * 白白吃带宽与内存。预览只要够清晰即可，成片另走 photoProfile（13 MP）。
 */
const PREVIEW_MAX_PIXELS: number = 1920 * 1080;

/** 拿到原始 JPEG 字节后的处理者 */
export type PhotoBytesHandler = (bytes: ArrayBuffer) => void;

/** 相机侧异步错误（会话/输出错误）的可读文案回调 —— 用于尽早把「被占用/服务中断」告诉用户 */
export type CameraErrorHandler = (message: string) => void;

/** 当前相机能力（供界面决定控件范围/是否可用） */
export class CameraCaps {
  zoomMin: number = 1;
  zoomMax: number = 1;
  zoomCurrent: number = 1;
  exposureMin: number = 0;
  exposureMax: number = 0;
  exposureCurrent: number = 0;
  flashMode: number = camera.FlashMode.FLASH_MODE_AUTO;
  position: number = camera.CameraPosition.CAMERA_POSITION_BACK;
  hasFront: boolean = false;
  hasBack: boolean = false;
  /** 预览/对焦坐标空间（用于点按对焦把屏幕坐标换算成相机坐标） */
  previewWidth: number = 0;
  previewHeight: number = 0;
  /**
   * 所选**预览流**的长宽比（宽/高）。界面必须用它来定画布尺寸，
   * 否则会把流拉伸到容器形状 —— 真机实测的「预览扭曲」就是这个问题。
   */
  previewRatio: number = 16 / 9;
  profileNote: string = '';
}

/** 相机异步错误 → 可读文案（模块级函数：ArkTS 对「函数类型的局部常量」支持不好，实测会编译失败） */
function cameraErrorText(code: number, message: string): string {
  return '相机连接中断（可能被其它应用占用）：' + code.toString() + ' ' + message;
}

export class CameraController {
  private session: camera.Session | undefined = undefined;
  private photoSession: camera.PhotoSession | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private manager: camera.CameraManager | undefined = undefined;
  private handler: PhotoBytesHandler | undefined = undefined;
  private ctx: common.Context | undefined = undefined;
  private errorHandler: CameraErrorHandler | undefined = undefined;
  private surfaceId: string = '';
  /** 界面预览区域的长宽比，用于挑预览流（见 pickPreviewProfile） */
  private boxRatio: number = 16 / 9;
  private caps: CameraCaps = new CameraCaps();
  private devices: camera.CameraDevice[] = [];

  profileInfo(): string {
    return this.caps.profileNote;
  }

  isReady(): boolean {
    return this.photoOutput !== undefined;
  }

  capabilities(): CameraCaps {
    return this.caps;
  }

  /** 显式挑 JPEG profile，并取其中像素最多的一档（未取最大档会严重拉低成片分辨率，已实测） */
  private pickPhotoProfile(capability: camera.CameraOutputCapability): camera.Profile | undefined {
    let best: camera.Profile | undefined = undefined;
    let bestPixels: number = 0;
    for (const p of capability.photoProfiles) {
      if (p.format !== camera.CameraFormat.CAMERA_FORMAT_JPEG) {
        continue;
      }
      const pixels: number = p.size.width * p.size.height;
      if (pixels > bestPixels) {
        best = p;
        bestPixels = pixels;
      }
    }
    if (best !== undefined) {
      this.caps.profileNote = 'JPEG ' + best.size.width.toString() + 'x' + best.size.height.toString()
        + '（共 ' + capability.photoProfiles.length.toString() + ' 档）';
      return best;
    }
    if (capability.photoProfiles.length > 0) {
      const fallback: camera.Profile = capability.photoProfiles[0];
      this.caps.profileNote = '⚠️ 无 JPEG 档，回退格式 ' + fallback.format.toString();
      return fallback;
    }
    return undefined;
  }

  /**
   * 挑预览流：**必须挑与界面容器长宽比最接近的一档**，不能盲取 `previewProfiles[0]`。
   *
   * 修复前的写法是 `createPreviewOutput(capability.previewProfiles[0], surfaceId)`，
   * 而容器是任意矩形（真机约 4.5:1），于是 4:3 的流被拉成 4.5:1 —— 画面明显扭曲。
   * 挑流只是第一步，界面还必须按 `previewRatio` 等比呈现画布（见 common/AspectFit.ts）。
   */
  private pickPreviewProfile(capability: camera.CameraOutputCapability,
    boxRatio: number): camera.Profile | undefined {
    const list: Size2D[] = [];
    for (const p of capability.previewProfiles) {
      list.push(new Size2D(p.size.width, p.size.height));
    }
    const idx: number = pickClosestRatio(list, boxRatio, PREVIEW_MAX_PIXELS);
    if (idx < 0) {
      return undefined;
    }
    const chosen: camera.Profile = capability.previewProfiles[idx];
    this.caps.previewWidth = chosen.size.width;
    this.caps.previewHeight = chosen.size.height;
    this.caps.previewRatio = ratioOf(new Size2D(chosen.size.width, chosen.size.height));
    return chosen;
  }

  /**
   * 打开相机并开始预览。成功返回空串，失败返回可读错误。
   * `boxRatio` = 界面为预览预留区域的长宽比（宽/高），用于挑选最合适的预览流。
   */
  async open(ctx: common.Context, surfaceId: string, boxRatio: number,
    onBytes: PhotoBytesHandler, onError: CameraErrorHandler): Promise<string> {
    // 幂等：surface 重建 / 页面重入 / 窗口尺寸变化都可能再调一次 open，
    // 若不清掉旧会话，就会有**两个 session 往同一个 surface 上写**，画面出现拉伸/错乱
    // （真机反馈的「分屏时预览又扭曲了」与此一致）。这里先关干净的再开。
    await this.close();
    this.handler = onBytes;
    this.errorHandler = onError;
    this.ctx = ctx;
    this.surfaceId = surfaceId;
    this.boxRatio = boxRatio > 0 ? boxRatio : 16 / 9;
    this.manager = camera.getCameraManager(ctx);
    this.devices = this.manager.getSupportedCameras();
    if (this.devices.length === 0) {
      return '没有可用相机';
    }
    // 记录前后摄可用性，供界面决定是否显示切换按钮
    for (const d of this.devices) {
      if (d.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
        this.caps.hasFront = true;
      }
      if (d.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
        this.caps.hasBack = true;
      }
    }
    let start: camera.CameraDevice = this.devices[0];
    for (const d of this.devices) {
      if (d.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
        start = d;
        break;
      }
    }
    return await this.startWith(start);
  }

  /** 前后摄切换：重建会话（几百毫秒，属预期） */
  async switchCamera(): Promise<string> {
    await this.close();
    let target: camera.CameraDevice | undefined = undefined;
    const wantFront: boolean = this.caps.position !== camera.CameraPosition.CAMERA_POSITION_FRONT;
    for (const d of this.devices) {
      if (wantFront && d.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
        target = d;
        break;
      }
      if (!wantFront && d.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
        target = d;
        break;
      }
    }
    if (target === undefined) {
      return '没有可切换的摄像头';
    }
    const ctx: common.Context | undefined = this.ctx;
    const handler: PhotoBytesHandler | undefined = this.handler;
    if (ctx === undefined || handler === undefined) {
      return '控制器状态丢失，请返回重进相机页';
    }
    this.handler = handler;
    this.ctx = ctx;
    return await this.startWith(target);
  }

  private async startWith(device: camera.CameraDevice): Promise<string> {
    const mgr: camera.CameraManager | undefined = this.manager;
    if (mgr === undefined) {
      return '相机管理器未初始化';
    }
    try {
      const capability: camera.CameraOutputCapability =
        mgr.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const photoProfile: camera.Profile | undefined = this.pickPhotoProfile(capability);
      if (photoProfile === undefined) {
        return '没有可用的拍照 profile';
      }
      const photoNote: string = this.caps.profileNote;
      const previewProfile: camera.Profile | undefined =
        this.pickPreviewProfile(capability, this.boxRatio);
      if (previewProfile === undefined) {
        return '没有可用的预览 profile';
      }
      // 把预览档也写进回显：真机上直接可见「预览流与容器比例是否匹配」
      this.caps.profileNote = photoNote + ' · 预览 '
        + this.caps.previewWidth.toString() + 'x' + this.caps.previewHeight.toString();
      this.caps.position = device.cameraPosition;

      this.cameraInput = mgr.createCameraInput(device);
      await this.cameraInput.open();
      this.previewOutput = mgr.createPreviewOutput(previewProfile, this.surfaceId);
      this.photoOutput = mgr.createPhotoOutput(photoProfile);
      // 约定 1：**先注册监听再 capture**
      this.registerListener(this.photoOutput);
      this.registerErrorListeners(this.previewOutput, this.photoOutput);

      const session: camera.Session = mgr.createSession(camera.SceneMode.NORMAL_PHOTO);
      session.beginConfig();
      session.addInput(this.cameraInput);
      session.addOutput(this.previewOutput);
      session.addOutput(this.photoOutput);
      await session.commitConfig();
      await session.start();
      this.session = session;
      this.photoSession = session as camera.PhotoSession;

      // 读取能力范围并设置合理初值
      const ps: camera.PhotoSession = this.photoSession;
      try {
        const zr: number[] = (ps as camera.Zoom).getZoomRatioRange();
        this.caps.zoomMin = zr[0];
        this.caps.zoomMax = zr[1];
        this.caps.zoomCurrent = (ps as camera.Zoom).getZoomRatio();
      } catch (err) {
        this.caps.zoomMin = 1;
        this.caps.zoomMax = 1;
      }
      try {
        const er: number[] = (ps as camera.AutoExposure).getExposureBiasRange();
        this.caps.exposureMin = er[0];
        this.caps.exposureMax = er[1];
        this.caps.exposureCurrent = 0;
      } catch (err) {
        this.caps.exposureMin = 0;
        this.caps.exposureMax = 0;
      }
      hilog.info(DOMAIN, TAG, 'started: %{public}s zoom=[%{public}d,%{public}d] exposure=[%{public}d,%{public}d]',
        this.caps.profileNote, this.caps.zoomMin, this.caps.zoomMax,
        this.caps.exposureMin, this.caps.exposureMax);
      return '';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'startWith failed: %{public}s', e.message);
      return '相机启动失败：' + e.code.toString() + ' ' + e.message;
    }
  }

  /**
   * 相机侧异步错误 → 立刻变成用户能看懂的状态文案。
   *
   * 为什么需要：真机实测（用户用微信相机做的占用实验）——**相机被占用时 open() 可能不报错**，
   * 画面直接静止，直到按下快门才抛 `7400201 Camera service fatal error`。
   * 只靠 open() 的 try/catch 是抓不到这种「不抛错的失效」的，必须听 session/preview 的错误事件。
   */
  private registerErrorListeners(output: camera.PreviewOutput, photo: camera.PhotoOutput): void {
    const session: camera.Session | undefined = this.session;
    const notify: CameraErrorHandler = (msg: string) => {
      hilog.error(DOMAIN, TAG, 'camera async error: %{public}s', msg);
      const handler: CameraErrorHandler | undefined = this.errorHandler;
      if (handler !== undefined) {
        handler(msg);
      }
    };
    try {
      output.on('error', (err: BusinessError) => {
        notify(cameraErrorText(err.code, err.message));
      });
    } catch (e) {
      // 某些设备/版本不支持该事件，忽略即可
    }
    try {
      photo.on('error', (err: BusinessError) => {
        notify(cameraErrorText(err.code, err.message));
      });
    } catch (e) {
      // 同上
    }
    if (session !== undefined) {
      try {
        (session as camera.PhotoSession).on('error', (err: BusinessError) => {
          notify(cameraErrorText(err.code, err.message));
        });
      } catch (e) {
        // 同上
      }
    }
  }

  private registerListener(output: camera.PhotoOutput): void {
    output.on('photoAvailable', (err: BusinessError, photo: camera.Photo) => {
      if (err !== undefined && err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'photoAvailable error: %{public}s', err.message);
        return;
      }
      photo.main.getComponent(image.ComponentType.JPEG)
        .then((component: image.Component) => {
          const bytes: ArrayBuffer = component.byteBuffer;
          hilog.info(DOMAIN, TAG, 'captured %{public}d bytes', bytes.byteLength);
          const h: PhotoBytesHandler | undefined = this.handler;
          if (h !== undefined) {
            h(bytes);
          }
          photo.release();
        })
        .catch((e: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'getComponent failed: %{public}s', e.message);
        });
    });
  }

  // ---------- T03-A 控制面 ----------

  /** 变焦；返回实际生效的倍率（越界会被夹到范围内） */
  setZoom(ratio: number): number {
    const ps: camera.PhotoSession | undefined = this.photoSession;
    if (ps === undefined) {
      return this.caps.zoomCurrent;
    }
    const clamped: number = Math.min(this.caps.zoomMax, Math.max(this.caps.zoomMin, ratio));
    try {
      (ps as camera.Zoom).setZoomRatio(clamped);
      this.caps.zoomCurrent = clamped;
      return clamped;
    } catch (err) {
      return this.caps.zoomCurrent;
    }
  }

  /** 闪光灯模式（FlashMode 枚举值） */
  setFlash(mode: number): number {
    const ps: camera.PhotoSession | undefined = this.photoSession;
    if (ps === undefined) {
      return this.caps.flashMode;
    }
    try {
      (ps as camera.Flash).setFlashMode(mode);
      this.caps.flashMode = mode;
    } catch (err) {
      // 保留原值
    }
    return this.caps.flashMode;
  }

  /** 曝光补偿；返回实际生效值 */
  setExposure(bias: number): number {
    const ps: camera.PhotoSession | undefined = this.photoSession;
    if (ps === undefined) {
      return this.caps.exposureCurrent;
    }
    const clamped: number = Math.min(this.caps.exposureMax, Math.max(this.caps.exposureMin, bias));
    try {
      (ps as camera.AutoExposure).setExposureBias(clamped);
      this.caps.exposureCurrent = clamped;
      return clamped;
    } catch (err) {
      return this.caps.exposureCurrent;
    }
  }

  /**
   * 点按对焦。入参是**归一化坐标**（0..1，相对预览区域），
   * 这里换算到相机预览坐标系后调用 setFocusPoint。
   */
  focusAt(nx: number, ny: number): boolean {
    const ps: camera.PhotoSession | undefined = this.photoSession;
    if (ps === undefined) {
      return false;
    }
    try {
      const focus: camera.Focus = ps as camera.Focus;
      const point: camera.Point = {
        x: Math.round(nx * this.caps.previewWidth),
        y: Math.round(ny * this.caps.previewHeight)
      };
      focus.setFocusPoint(point);
      return true;
    } catch (err) {
      return false;
    }
  }

  async capture(): Promise<string> {
    const output: camera.PhotoOutput | undefined = this.photoOutput;
    if (output === undefined) {
      return '相机尚未就绪';
    }
    const setting: camera.PhotoCaptureSetting = {
      quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
      rotation: camera.ImageRotation.ROTATION_0
    };
    try {
      await output.capture(setting);
      return '';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      return '拍摄失败：' + e.code.toString() + ' ' + e.message;
    }
  }

  async close(): Promise<void> {
    if (this.session !== undefined) {
      try {
        await this.session.stop();
        await this.session.release();
      } catch (err) {
        // 释放阶段尽力而为
      }
      this.session = undefined;
      this.photoSession = undefined;
    }
    if (this.cameraInput !== undefined) {
      try {
        await this.cameraInput.close();
      } catch (err) {
        // 同上
      }
      this.cameraInput = undefined;
    }
    this.photoOutput = undefined;
    this.previewOutput = undefined;
  }
}
