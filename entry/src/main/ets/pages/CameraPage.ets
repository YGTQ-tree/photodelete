/**
 * 相机页（T03）：预览 + 快门 + 「N 小时后自动转入待删除」。
 *
 * 勾选项的语义（见 docs/ARCHITECTURE.md §2.1）：
 *   - 选定 1/6/24/72 小时 → 该照片以 BUFFER 状态落库，到期由惰性物化转入待删除；
 *   - 选「永久」         → 直接 KEPT，不自动待删。
 * 时长只影响**这一张**（快照进 policy_hours），改设置不会追溯已拍照片。
 *
 * 相机实现严格按 ADR-001 的实测结论（见 infra/CameraController）。
 */

import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

import { AppCore } from '../app/AppCore';
import { KEEP_FOREVER, KEEP_OPTION_HOURS } from '../domain/RetentionPolicy';
import { Size2D, fitInside } from '../common/AspectFit';
import { DEVTOOLS_ENABLED } from '../common/BuildConfig';
import { CameraController } from '../infra/CameraController';
import type { CameraCaps } from '../infra/CameraController';
import { CameraVm, CaptureOutcome } from '../viewmodel/CameraVm';

@Entry
@Component
struct CameraPage {
  @State keepHours: number = 24;
  @State status: string = '正在启动相机…';
  @State lastResult: string = '';
  @State profileNote: string = '';
  @State busy: boolean = false;
  @State shots: number = 0;
  // T03-A 控制面
  @State zoom: number = 1;
  @State zoomMin: number = 1;
  @State zoomMax: number = 1;
  @State exposure: number = 0;
  @State exposureMin: number = 0;
  @State exposureMax: number = 0;
  @State flashLabel: string = '闪光 自动';
  @State showGrid: boolean = true;
  @State focusNote: string = '';
  @State canSwitch: boolean = false;
  /**
   * 预览画布长宽比 = **相机预览流**的长宽比。必须与流一致，否则画面被拉伸
   * （真机缺陷：容器约 4.5:1 而流是 4:3，画面明显扭曲）。
   */
  @State previewRatio: number = 16 / 9;
  /** 预览容器实测尺寸，用于把画布等比嵌进去（letterbox，不裁剪不拉伸） */
  @State boxW: number = 0;
  @State boxH: number = 0;
  private previewW: number = 1;
  private previewH: number = 1;
  /** 防止 onLoad 重入并发开两次相机（两个 session 抢一个 surface → 画面异常） */
  private starting: boolean = false;
  /** 已经启动过的 surfaceId：同一个 surface 不重复开 */
  private startedSurface: string = '';

  private xc: XComponentController = new XComponentController();
  private cam: CameraController = new CameraController();
  private vm: CameraVm | undefined = undefined;
  private surfaceId: string = '';

  aboutToAppear(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.status = '应用尚未初始化';
      return;
    }
    this.vm = new CameraVm(core);
    this.vm.defaultKeepHours()
      .then((h: number) => {
        this.keepHours = h;
      })
      .catch(() => {
        // 读设置失败就用默认 24h
      });
  }

  aboutToDisappear(): void {
    this.cam.close();
  }

  private async ensurePermission(ctx: common.Context): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const perms: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const res = await atManager.requestPermissionsFromUser(ctx, perms);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (err) {
      return false;
    }
  }

  private startPreview(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.status = '无法获取 Context';
      return;
    }
    // 同一个 surface 已经开好了就不要再开（窗口尺寸变化 / onLoad 重入都会走到这里）
    if (this.starting || (this.startedSurface === this.surfaceId && this.cam.isReady())) {
      return;
    }
    this.starting = true;
    const surface: string = this.surfaceId;
    this.ensurePermission(ctx).then((granted: boolean) => {
      if (!granted) {
        this.starting = false;
        this.status = '相机权限被拒绝：请在设置的权限管理里允许后重试';
        return;
      }
      this.cam.open(ctx, surface, this.boxRatio(), (bytes: ArrayBuffer) => {
        this.handleBytes(bytes);
      }, (msg: string) => {
        // 相机侧异步错误（被占用 / 服务中断）：立刻给出可读文案，用户不用等到按快门
        this.status = msg;
      })
        .then((err: string) => {
          this.starting = false;
          if (err.length > 0) {
            this.status = err;
            return;
          }
          this.startedSurface = surface;
          this.status = '准备就绪';
          this.syncCaps();
        })
        .catch((e: Error) => {
          this.starting = false;
          this.status = '相机启动异常：' + e.message;
        });
    });
  }

  /** 把控制器读到的能力同步到 UI 状态 */
  private syncCaps(): void {
    const caps: CameraCaps = this.cam.capabilities();
    this.profileNote = caps.profileNote;
    this.previewRatio = caps.previewRatio > 0 ? caps.previewRatio : 16 / 9;
    this.zoomMin = caps.zoomMin;
    this.zoomMax = caps.zoomMax;
    this.zoom = caps.zoomCurrent;
    this.exposureMin = caps.exposureMin;
    this.exposureMax = caps.exposureMax;
    this.exposure = caps.exposureCurrent;
    this.canSwitch = caps.hasFront && caps.hasBack;
    this.flashLabel = caps.flashMode === 2 ? '闪光 自动'
      : (caps.flashMode === 1 ? '闪光 开' : '闪光 关');
  }

  /** 预览容器当前的长宽比；还没量出尺寸时按 16:9 估，保证挑流逻辑总有个合理目标 */
  private boxRatio(): number {
    return this.boxW > 0 && this.boxH > 0 ? this.boxW / this.boxH : 16 / 9;
  }

  /**
   * 画布尺寸 = 按 previewRatio **等比嵌进**容器（letterbox）。
   *
   * ⚠️ 这里**必须**是 letterbox，不能是 cover（铺满+裁切）。真机实测（分屏截图）：
   * 当画布比可见区域大时，ArkUI 会把 surface **缩放到可见区域**，于是
   * 2.53:1 的可见框里放 1.8:1 的流 → 画面纵向被压扁 0.71 倍（杯子变扁椭圆）。
   * 只有「画布 ≤ 可见区域」时 surface 才等于画布，比例才真的等于流的比例。
   */
  private canvasSize(): Size2D {
    const w: number = this.boxW > 0 ? this.boxW : 1080;
    const h: number = this.boxH > 0 ? this.boxH : 608;
    return fitInside(w, h, this.previewRatio);
  }

  private handleBytes(bytes: ArrayBuffer): void {
    const vm: CameraVm | undefined = this.vm;
    if (vm === undefined) {
      this.status = '应用尚未初始化';
      return;
    }
    vm.saveCapture(bytes, this.keepHours)
      .then((outcome: CaptureOutcome) => {
        this.busy = false;
        if (outcome.ok) {
          this.shots += 1;
        }
        this.lastResult = (outcome.ok ? '✅ ' : '❌ ') + outcome.message;
      })
      .catch((err: Error) => {
        this.busy = false;
        this.lastResult = '❌ 保存异常：' + err.message;
      });
  }

  private takeShot(): void {
    if (this.busy || !this.cam.isReady()) {
      return;
    }
    this.busy = true;
    this.lastResult = '拍摄中…';
    this.cam.capture().then((err: string) => {
      if (err.length > 0) {
        this.busy = false;
        this.lastResult = '❌ ' + err;
      }
    });
  }

  private labelOf(hours: number): string {
    return hours === KEEP_FOREVER ? '永久' : hours.toString() + 'h';
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('待删相机')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 10 })
        Blank()
        Text(this.shots > 0 ? '已拍 ' + this.shots.toString() + ' 张' : '')
          .fontSize(13)
          .fontColor('#666666')
        Button('我的照片')
          .fontSize(13)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .margin({ left: 8 })
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PhotosPage' }).catch((err: Error) => {
              this.getUIContext().getPromptAction().showToast({ message: '打开失败：' + err.message });
            });
          })
      }
      .width('100%')

      // 外层 = 屏幕上的**可见框**（clip 掉溢出的部分）；内层 = 画布（按流比例 cover 铺满）
      Stack({ alignContent: Alignment.Center }) {
        Stack() {
          XComponent({
            id: 'cameraPreview',
            type: XComponentType.SURFACE,
            controller: this.xc
          })
            .onLoad(() => {
              this.surfaceId = this.xc.getXComponentSurfaceId();
              this.startPreview();
            })
            .width('100%')
            .height('100%')
        }
        .width(this.canvasSize().width)
        .height(this.canvasSize().height)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          // 点按对焦的归一化基准必须是**画布**：布局时 event.x/y 就是相对画布左上角的，
          // 因此被裁掉的部分也能正确换算成相机坐标
          this.previewW = Number(newArea.width);
          this.previewH = Number(newArea.height);
        })
        .onClick((event: ClickEvent) => {
          // 点按对焦：把点击位置归一化后交给相机
          const nx: number = this.previewW > 0 ? event.x / this.previewW : 0.5;
          const ny: number = this.previewH > 0 ? event.y / this.previewH : 0.5;
          const ok: boolean = this.cam.focusAt(nx, ny);
          this.focusNote = ok
            ? '对焦 @(' + nx.toFixed(2) + ', ' + ny.toFixed(2) + ')'
            : '对焦暂不可用';
        })

        // 网格线画在**可见框**上（用户看到的三分线就是所见画面的三分线）。
        // hitTestBehavior Transparent：网格不吃点击，否则点按对焦会被它拦掉。
        if (this.showGrid) {
          Column() {
            Divider().strokeWidth(1).color('#55FFFFFF')
            Blank()
            Divider().strokeWidth(1).color('#55FFFFFF')
            Blank()
            Divider().strokeWidth(1).color('#55FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .hitTestBehavior(HitTestMode.Transparent)

          Row() {
            Divider().vertical(true).strokeWidth(1).color('#55FFFFFF')
            Blank()
            Divider().vertical(true).strokeWidth(1).color('#55FFFFFF')
            Blank()
            Divider().vertical(true).strokeWidth(1).color('#55FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ minHeight: 240 })
      .backgroundColor('#111111')
      .borderRadius(10)
      .clip(true)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = Number(newArea.width);
        const h: number = Number(newArea.height);
        if (w > 0 && h > 0 && (Math.abs(w - this.boxW) > 1 || Math.abs(h - this.boxH) > 1)) {
          this.boxW = w;
          this.boxH = h;
        }
      })

      // 状态 + 对焦回显放同一行：预览要尽可能大，控件区越扁越好
      Row({ space: 8 }) {
        Text(this.status + (this.profileNote.length > 0 ? ' · ' + this.profileNote : ''))
          .fontSize(12)
          .fontColor('#666666')
          .layoutWeight(1)
        Text(this.focusNote)
          .fontSize(11)
          .fontColor('#888888')
      }
      .width('100%')

      if (DEVTOOLS_ENABLED) {
        // 开发专用几何自检：把「容器 / 画布 / 预览流」三个比例同时显示出来，
        // 分屏或旋转后截一张图就能判断到底是哪一层不匹配（不必靠肉眼猜是否扭曲）
        Text('几何：容器 ' + Math.round(this.boxW).toString() + 'x' + Math.round(this.boxH).toString()
          + '（' + (this.boxRatio()).toFixed(2) + '） · 画布 '
          + this.canvasSize().width.toString() + 'x' + this.canvasSize().height.toString()
          + '（' + this.previewRatio.toFixed(2) + '） · 流 '
          + this.cam.capabilities().previewWidth.toString() + 'x'
          + this.cam.capabilities().previewHeight.toString())
          .fontSize(11)
          .fontColor('#2C6CB5')
          .width('100%')
      }

      // 空字符串也占一行高度，所以有内容才渲染（省下的高度全给预览）
      if (this.lastResult.length > 0) {
        Text(this.lastResult)
          .fontSize(13)
          .width('100%')
          .padding(6)
          .backgroundColor('#F2F3F5')
          .borderRadius(6)
      }

      Row({ space: 6 }) {
        Button(this.flashLabel)
          .fontSize(13)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            // 自动(2) → 开(1) → 关(0) 循环
            const current: number = this.cam.capabilities().flashMode;
            const next: number = current === 2 ? 1 : (current === 1 ? 0 : 2);
            const applied: number = this.cam.setFlash(next);
            this.flashLabel = applied === 2 ? '闪光 自动' : (applied === 1 ? '闪光 开' : '闪光 关');
          })
        Button(this.showGrid ? '网格 开' : '网格 关')
          .fontSize(13)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.showGrid = !this.showGrid;
          })
        if (this.canSwitch) {
          Button('切换镜头')
            .fontSize(13)
            .backgroundColor('#F2F3F5')
            .fontColor('#333333')
            .onClick(() => {
              this.status = '切换中…';
              this.cam.switchCamera().then((err: string) => {
                if (err.length > 0) {
                  this.status = err;
                  return;
                }
                this.syncCaps();
                this.status = '准备就绪';
              });
            })
        }
      }
      .width('100%')

      // 变焦与曝光并排：一条滑轨占一行太浪费，并排后预览多出一整行高度
      if (this.zoomMax > this.zoomMin || this.exposureMax > this.exposureMin) {
        Row({ space: 16 }) {
          if (this.zoomMax > this.zoomMin) {
            Row({ space: 6 }) {
              Text(this.zoom.toFixed(1) + 'x')
                .fontSize(12)
                .width(46)
              Slider({
                value: this.zoom,
                min: this.zoomMin,
                max: this.zoomMax < 10 ? this.zoomMax : 10,
                step: 0.1,
                style: SliderStyle.OutSet
              })
                .layoutWeight(1)
                .onChange((value: number, mode: SliderChangeMode) => {
                  const applied: number = this.cam.setZoom(value);
                  this.zoom = applied;
                })
            }
            .layoutWeight(1)
          }

          if (this.exposureMax > this.exposureMin) {
            Row({ space: 6 }) {
              Text('曝光 ' + this.exposure.toFixed(1))
                .fontSize(12)
                .width(80)
              Slider({
                value: this.exposure,
                min: this.exposureMin,
                max: this.exposureMax,
                step: 0.1,
                style: SliderStyle.OutSet
              })
                .layoutWeight(1)
                .onChange((value: number, mode: SliderChangeMode) => {
                  const applied: number = this.cam.setExposure(value);
                  this.exposure = applied;
                })
            }
            .layoutWeight(1)
          }
        }
        .width('100%')
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(KEEP_OPTION_HOURS, (hours: number) => {
          Button(this.labelOf(hours))
            .fontSize(14)
            .margin(3)
            .backgroundColor(this.keepHours === hours ? '#D94838' : '#F2F3F5')
            .fontColor(this.keepHours === hours ? '#FFFFFF' : '#333333')
            .onClick(() => {
              this.keepHours = hours;
            })
        }, (hours: number) => hours.toString())
        if (DEVTOOLS_ENABLED) {
          // 开发专用：1 分钟到期，用于自动化验证「到期物化」（否则要等 1 小时）
          Button('1分钟')
            .fontSize(14)
            .margin(3)
            .backgroundColor(this.keepHours === 1 / 60 ? '#D94838' : '#FFE0B2')
            .fontColor(this.keepHours === 1 / 60 ? '#FFFFFF' : '#333333')
            .onClick(() => {
              this.keepHours = 1 / 60;
            })
        }
      }
      .width('100%')

      Text(this.keepHours > 0
        ? '⏱ ' + this.keepHours.toString() + ' 小时后自动转入待删除'
        : '不自动待删（永久保留）')
        .fontSize(13)
        .fontColor(this.keepHours > 0 ? '#D94838' : '#1B5E20')
        .width('100%')

      Button(this.busy ? '处理中…' : '拍照')
        .width('100%')
        .height(48)
        .fontSize(18)
        .enabled(!this.busy)
        .onClick(() => {
          this.takeShot();
        })
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
