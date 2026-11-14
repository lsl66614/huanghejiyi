// entry/src/ohosTest/ets/testability/pages/Index.ets —— ohosTest 宿主空白页（仅承载测试进程）
@Entry
@Component
struct Index {
  @State message: string = 'ohosTest host';

  build() {
    Column() {
      Text(this.message)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}