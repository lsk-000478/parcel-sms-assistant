import Foundation
@main struct Tests {
 static func main() {
  func parse(_ s: String, _ id: Int64 = 1, _ seconds: Double = 0) -> ParcelEvent? { ParcelParser.parse(id:id,date:Date(timeIntervalSince1970:seconds),sender:"1069",body:s) }
  assert(parse("【菜鸟】您的包裹已存入幸福小区菜鸟驿站，取件码：3-12-456。")?.code == "3-12-456")
  assert(parse("【顺丰】运单号SF123456789012已揽收")?.status == .sent)
  assert(parse("快递员即将上门，请保持电话畅通")?.status == .approaching)
  assert(parse("【京东物流】正在配送，预计今日18点送达")?.eta == "预计今日18点送达")
  assert(parse("【中通】您的验证码为123456，请用于寄件登录") == nil)
  assert(parse("快递优惠券，点击领取") == nil)
  assert(parse("包裹尾号1234，取件码2-345")?.tracking == nil)
  assert(parse("运单号12345678****已到达驿站")?.tracking == nil)
  let a = parse("运单号SF123456789012已存入菜鸟驿站，取件码1-2-3",1,1)!
  let b = parse("运单号SF123456789012已签收",2,2)!
  let p = ParcelParser.group([a,b]); assert(p.count == 1 && p[0].currentCode == nil && p[0].events.count == 2)
  assert(ParcelParser.group([parse("包裹已入库，取件码1-2-3",3)!,parse("包裹已入库，取件码1-2-3",4)!]).count == 2)
  assert(parse("【中通】包裹已签收并存入幸福驿站，取件码【3-2-18】")?.status == .pickup)
  assert(parse("【中通】包裹已签收并存入幸福驿站，取件码【3-2-18】")?.code == "3-2-18")
  func platform(_ body: String) -> ShoppingPlatform? { PlatformDetector.identify([parse(body)!]).platform }
  assert(platform("【淘宝】您的包裹已发出") == .taobao)
  assert(platform("【京东】您的订单包裹正在派送") == .jd)
  assert(platform("【京东物流】您的包裹正在派送") == nil)
  assert(platform("【菜鸟】包裹已存入驿站，取件码1-2-3") == nil)
  assert(platform("【中通】您在拼多多购买的包裹已到达") == .pdd)
  assert(platform("【顺丰】抖音订单的包裹已寄出") == .douyin)
  assert(platform("【快手】您的包裹已发出") == .kuaishou)
  assert(platform("小红书购买的包裹已到达") == .rednote)
  assert(platform("【微信小店】包裹已到达") == .wechat)
  assert(platform("【视频号】包裹已到达") == .wechat)
  assert(platform("【天猫】包裹已到达") == .tmall)
  assert(platform("【顺丰】包裹正在派送，欢迎关注抖音") == nil)
  assert(platform("【淘宝】您的包裹已到达；京东订单查询") == nil)
  let older = parse("【拼多多】运单号SF123456789012已发出",5,1)!
  let newer = parse("【顺丰】运单号SF123456789012已存入菜鸟驿站，取件码1-2-3",6,2)!
  assert(ParcelParser.group([older,newer])[0].platformClue.platform == .pdd)
  let conflicting = parse("【淘宝】运单号SF123456789012已发出",7,3)!
  assert(ParcelParser.group([older,newer,conflicting])[0].platformClue.platform == nil)
  var ledger = ReceiptLedger()
  let active = ParcelParser.group([newer])[0]
  ledger.markReceived(active,at:Date(timeIntervalSince1970:100))
  assert(ledger.isReceived(active))
  let restored = try! JSONDecoder().decode(ReceiptLedger.self,from:JSONEncoder().encode(ledger))
  assert(restored.isReceived(active) && restored.archivedEvents.count == 1)
  assert(ledger.reconcile([]).count == 1) // 离开90天读取窗口后，归档仍保留。
  ledger.undoManualMark(active)
  assert(!ledger.isReceived(active) && ledger.archivedEvents.isEmpty)
  var automatic = ReceiptLedger()
  _ = automatic.reconcile([a,b])
  assert(automatic.reconcile([]).first?.latest.status == .delivered)
  automatic.markReceived(p[0]); automatic.undoManualMark(p[0])
  assert(automatic.isReceived(p[0])) // 撤销手动标记不覆盖短信中的签收事实。
  print("短信解析与归并测试全部通过")
 }
}
