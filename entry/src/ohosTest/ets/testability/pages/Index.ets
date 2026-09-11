@Entry
@Component
struct Index {
  @State message: string = 'PhotoDelete 契约测试';

  build() {
    Row() {
      Column() {
        Text(this.message)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
    .height('100%')
  }
}
