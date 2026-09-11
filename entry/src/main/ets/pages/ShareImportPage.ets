/**
 * 分享接收结果页：告诉用户「导入了几张、之后会怎样、原图要自己删」。
 *
 * 这一页的存在本身就是那条硬限制的载体：**原图不在我们手里**，必须明说。
 */

import { AppCore } from '../app/AppCore';

@Entry
@Component
struct ShareImportPage {
  @State message: string = '正在导入…';
  @State detail: string = '';

  aboutToAppear(): void {
    const raw: string | undefined = AppStorage.get<string>('shareImportResult');
    if (raw !== undefined && raw.length > 0) {
      this.message = raw;
    }
    const d: string | undefined = AppStorage.get<string>('shareImportDetail');
    if (d !== undefined) {
      this.detail = d;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('分享接收')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text(this.message)
        .fontSize(15)
        .width('100%')
        .padding(12)
        .backgroundColor('#EEF7EE')
        .borderRadius(8)

      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(12)
          .fontColor('#D94838')
          .width('100%')
      }

      Text('说明：\n• 已把分享的图片**复制**一份到本应用，之后由本应用按你设定的时长自动整理；\n'
        + '• 系统相册里的**原图不在本应用管理范围内**，需要你自己去图库删除，本应用无法代删。')
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')

      Row({ space: 10 }) {
        Button('去待删除')
          .fontSize(15)
          .onClick(() => {
            this.getUIContext().getRouter().replaceUrl({ url: 'pages/TrashPage' });
          })
        Button('返回')
          .fontSize(15)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .justifyContent(FlexAlign.Center)
  }
}
