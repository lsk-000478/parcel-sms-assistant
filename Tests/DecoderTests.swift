import Foundation
@main struct DecoderTests {
 static func main() throws {
  let value = "快递测试：包裹正在配送中 📦 取件码3-2-18"
  let attr = NSAttributedString(string:value)
  let legacy = NSArchiver.archivedData(withRootObject:attr)
  let keyed = try NSKeyedArchiver.archivedData(withRootObject:attr,requiringSecureCoding:true)
  assert(BodyDecoder.decode(legacy) == value)
  assert(BodyDecoder.decode(keyed) == value)
  assert(BodyDecoder.decode(Data([1,2,3])) == nil)
  assert(BodyDecoder.decode(legacy.prefix(24)) == nil)
  print("短信正文兼容测试全部通过")
 }
}
