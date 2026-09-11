/**
 * G0-B 相机落盘探针（T00 的交付物，跑完即可删除或保留为调试页）。
 *
 * 目的：把「Camera Kit 出图后字节流怎么落到应用沙箱」这个唯一的平台未知数**实测定死**，
 * 结论写入 docs/decisions/ADR-001-camera-capture-path.md，之后的 T03 相机页只按选定路径实现。
 *
 * 方案 A（本页实现，首选）：`photoOutput.on('photoAvailable')` 拿 `Photo.main` →
 *   `getComponent(ComponentType.JPEG)` 取 **未经二次编码的 JPEG 字节** → fileIo 写沙箱。
 *   全程不申请任何媒体库权限。
 * 方案 B（对照）：`capture()` 默认落盘 + 查询自有媒体资源 —— 若它要求
 *   `WRITE_IMAGEVIDEO` 则直接淘汰（本应用不申请受限权限）。
 * 方案 C：安全控件 SaveButton 导出到系统相册 —— 属二期「保留/导出」，不作主路径。
 *
 * A1 防御（见 docs/HARMONYOS7-CHECKLIST.md §2）：**显式挑 CAMERA_FORMAT_JPEG 的 profile**，
 * 不依赖默认格式（API 26 起设备默认可能是 HEIF）。
 */

import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { AppCore } from '../app/AppCore';
import { sniffImageMime } from '../common/ImageFormat';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteProbe';
const PROBE_DIR: string = 'files/probe';

@Entry
@Component
struct CameraProbePage {
  @State status: string = '等待预览就绪…';
  @State result: string = '尚未拍摄';
  @State profileInfo: string = '';
  @State shots: number = 0;

  private controller: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private session: camera.Session | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;

  aboutToDisappear(): void {
    this.releaseCamera();
  }

  private async requestCameraPermission(ctx: common.Context): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const perms: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const res = await atManager.requestPermissionsFromUser(ctx, perms);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (err) {
      return false;
    }
  }

  private ensureProbeDir(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return;
    }
    const abs: string = core.files.absolutePath(PROBE_DIR);
    try {
      if (!fileIo.accessSync(abs)) {
        fileIo.mkdirSync(abs);
      }
    } catch (err) {
      try {
        fileIo.mkdirSync(abs);
      } catch (err2) {
        // 已存在
      }
    }
  }

  /** 挑 profile：优先 JPEG（A1） */
  private pickPhotoProfile(capability: camera.CameraOutputCapability): camera.Profile | undefined {
    for (const p of capability.photoProfiles) {
      if (p.format === camera.CameraFormat.CAMERA_FORMAT_JPEG) {
        this.profileInfo = '显式选中 JPEG profile（' + p.size.width.toString() + 'x'
          + p.size.height.toString() + '）';
        return p;
      }
    }
    if (capability.photoProfiles.length > 0) {
      const fallback: camera.Profile = capability.photoProfiles[0];
      this.profileInfo = '⚠️ 没有 JPEG profile，回退到默认格式 format=' + fallback.format.toString();
      return fallback;
    }
    return undefined;
  }

  /** 预览 surface 就绪后启动相机会话 */
  private async startCamera(): Promise<void> {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.status = '无法获取 Context';
      return;
    }
    const granted: boolean = await this.requestCameraPermission(ctx);
    if (!granted) {
      this.status = '❌ 相机权限被拒绝（A9 观察点：应可读提示而非崩溃）';
      return;
    }

    try {
      const manager: camera.CameraManager = camera.getCameraManager(ctx);
      const devices: camera.CameraDevice[] = manager.getSupportedCameras();
      if (devices.length === 0) {
        this.status = '❌ 无可用相机';
        return;
      }
      const device: camera.CameraDevice = devices[0];
      const capability: camera.CameraOutputCapability =
        manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);

      const photoProfile: camera.Profile | undefined = this.pickPhotoProfile(capability);
      if (photoProfile === undefined) {
        this.status = '❌ 没有可用的拍照 profile';
        return;
      }

      this.cameraInput = manager.createCameraInput(device);
      await this.cameraInput.open();

      const previewProfile: camera.Profile = capability.previewProfiles[0];
      this.previewOutput = manager.createPreviewOutput(previewProfile, this.surfaceId);

      this.photoOutput = manager.createPhotoOutput(photoProfile);
      this.registerPhotoListener(this.photoOutput);

      const session: camera.Session = manager.createSession(camera.SceneMode.NORMAL_PHOTO);
      session.beginConfig();
      session.addInput(this.cameraInput);
      session.addOutput(this.previewOutput);
      session.addOutput(this.photoOutput);
      await session.commitConfig();
      await session.start();
      this.session = session;
      this.status = '✅ 预览已启动，可以按快门';

      // 探针启动后自动按一次快门：把「人工操作」压到只剩「允许相机权限」那一下点按，
      // 结果全部落到 hilog，便于用 hdc 采集。手动按钮仍在，可重复拍摄。
      this.status = '✅ 预览已启动（5 秒后自动按快门）';
      setTimeout(() => {
        this.takeShot();
      }, 5000);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.status = '❌ 启动相机失败：' + e.code.toString() + ' ' + e.message;
      hilog.error(DOMAIN, TAG, 'startCamera failed: %{public}s', e.message);
    }
  }

  /** 方案 A：监听图出流，取 JPEG 字节直接落盘 */
  private registerPhotoListener(output: camera.PhotoOutput): void {
    output.on('photoAvailable', (err: BusinessError, photo: camera.Photo) => {
      if (err !== undefined && err.code !== 0) {
        this.result = '❌ photoAvailable 回调错误：' + err.code.toString() + ' ' + err.message;
        return;
      }
      this.persistPhoto(photo);
    });
  }

  private persistPhoto(photo: camera.Photo): void {
    photo.main.getComponent(image.ComponentType.JPEG)
      .then((component: image.Component) => {
        const buffer: ArrayBuffer = component.byteBuffer;
        const head: Uint8Array = new Uint8Array(buffer.slice(0, 12));
        const mime: string = sniffImageMime(head);

        const core: AppCore | undefined = AppCore.current();
        if (core === undefined) {
          this.result = '❌ AppCore 未就绪，无法落盘';
          return;
        }
        this.ensureProbeDir();
        this.shots += 1;
        const relPath: string = PROBE_DIR + '/probe-' + this.shots.toString() + '.bin';
        const absPath: string = core.files.absolutePath(relPath);
        const file = fileIo.openSync(
          absPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
        );
        try {
          fileIo.writeSync(file.fd, buffer);
        } finally {
          fileIo.closeSync(file);
        }
        const size: number = buffer.byteLength;
        const ok: boolean = mime === 'image/jpeg';
        this.result = (ok ? '✅ 方案 A 成功' : '⚠️ 方案 A 落盘成功但格式非 JPEG')
          + '：' + size.toString() + ' 字节 · 文件头判定 = ' + mime
          + ' · 路径 ' + relPath;
        hilog.info(DOMAIN, TAG, 'probe A: size=%{public}d mime=%{public}s', size, mime);
        photo.release();
      })
      .catch((e: BusinessError) => {
        this.result = '❌ 方案 A 失败（getComponent）：' + e.code.toString() + ' ' + e.message;
        hilog.error(DOMAIN, TAG, 'getComponent failed: %{public}s', e.message);
      });
  }

  private takeShot(): void {
    const output: camera.PhotoOutput | undefined = this.photoOutput;
    if (output === undefined) {
      this.status = '相机尚未就绪';
      return;
    }
    const setting: camera.PhotoCaptureSetting = {
      quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
      rotation: camera.ImageRotation.ROTATION_0
    };
    output.capture(setting).catch((err: BusinessError) => {
      this.result = '❌ capture 失败：' + err.code.toString() + ' ' + err.message;
    });
  }

  private releaseCamera(): void {
    if (this.session !== undefined) {
      this.session.stop().catch(() => {
      });
      this.session.release().catch(() => {
      });
      this.session = undefined;
    }
    if (this.cameraInput !== undefined) {
      this.cameraInput.close().catch(() => {
      });
      this.cameraInput = undefined;
    }
    this.photoOutput = undefined;
    this.previewOutput = undefined;
  }

  build() {
    Column({ space: 10 }) {
      Text('G0-B 相机落盘探针')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Stack() {
        XComponent({
          id: 'probeSurface',
          type: XComponentType.SURFACE,
          controller: this.controller
        })
          .onLoad(() => {
            this.surfaceId = this.controller.getXComponentSurfaceId();
            this.startCamera();
          })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height(320)
      .backgroundColor('#111111')
      .borderRadius(8)

      Text(this.status)
        .fontSize(13)
        .width('100%')
      Text(this.profileInfo)
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')
      Text(this.result)
        .fontSize(12)
        .width('100%')
        .padding(8)
        .backgroundColor('#F2F3F5')
        .borderRadius(6)

      Row({ space: 10 }) {
        Button('按快门（方案 A）')
          .onClick(() => {
            this.takeShot();
          })
        Button('返回')
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
      }
      .width('100%')

      Text('判据：结果里应出现「方案 A 成功」且文件头判定为 image/jpeg；全程未申请媒体库权限。')
        .fontSize(11)
        .fontColor('#999999')
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
