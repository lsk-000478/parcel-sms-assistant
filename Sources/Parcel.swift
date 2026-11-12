import Foundation

enum ShoppingPlatform: String, CaseIterable {
    case taobao = "淘宝", tmall = "天猫", jd = "京东", pdd = "拼多多", douyin = "抖音", kuaishou = "快手", rednote = "小红书", wechat = "视频号 / 微信小店", vip = "唯品会", suning = "苏宁易购", dewu = "得物", xiaomi = "小米商城"
    var aliases: [String] {
        switch self {
        case .wechat: return ["视频号", "微信小店", "微信小商店"]
        default: return [rawValue]
        }
    }
    var glyph: String {
        switch self {
        case .taobao: return "淘"
        case .tmall: return "猫"
        case .jd: return "京"
        case .pdd: return "拼"
        case .douyin: return "♪"
        case .kuaishou: return "快"
        case .rednote: return "红"
        case .wechat: return "微"
        case .vip: return "唯"
        case .suning: return "苏"
        case .dewu: return "得"
        case .xiaomi: return "米"
        }
    }
}
struct PlatformClue {
    let platform: ShoppingPlatform?
    let evidence: String
    var label: String { platform?.rawValue ?? "平台未知" }
}
enum PlatformDetector {
    static func candidates(in text: String) -> [(ShoppingPlatform, String)] {
        ShoppingPlatform.allCases.compactMap { platform in
            for alias in platform.aliases {
                let word = NSRegularExpression.escapedPattern(for: alias)
                // 快递公司/驿站名称不能证明购买平台；仅认平台签名或明确购物上下文。
                let patterns = [
                    "(?:【|\\[)\\s*\(word)(?:订单|商城|购物)?\\s*(?:】|\\])",
                    "\(word)(?:平台|商城|小店)?(?:上|中|的|所购)?(?:购买|下单|订单|商品|包裹)",
                    "(?:来自|购于|购买于|下单于)\\s*\(word)",
                    "在\\s*\(word)(?:平台|商城|上)?(?:购买|下单|所购)"
                ]
                for pattern in patterns {
                    if let evidence = ParcelParser.match(pattern, text) { return (platform,evidence) }
                }
            }
            return nil
        }
    }
    static func identify(_ events: [ParcelEvent]) -> PlatformClue {
        let clues = events.flatMap { candidates(in:$0.body) }
        let platforms = Set(clues.map { $0.0 })
        guard platforms.count == 1, let clue = clues.first else {
            return PlatformClue(platform:nil,evidence: platforms.isEmpty ? "短信未明确说明购买平台；快递公司与驿站不能作为判断依据。" : "短信涉及多个平台，暂不确定归属：" + platforms.map(\.rawValue).sorted().joined(separator:"、"))
        }
        return PlatformClue(platform:clue.0,evidence:"短信线索：\(clue.1)（仅根据短信文字识别，未向平台核验）")
    }
}
enum ParcelStatus: String, CaseIterable, Codable {
    case sent = "已寄出", transit = "运输中", delivery = "派送中", approaching = "即将上门", pickup = "待取件", delivered = "已签收", unknown = "快递通知"
}
struct ParcelEvent: Identifiable, Codable {
    let id: Int64
    let date: Date
    let sender: String
    let body: String
    let carrier: String
    let tracking: String?
    let code: String?
    let station: String?
    let eta: String?
    let status: ParcelStatus
    let service: String?
    var serviceLabel: String {
        switch service {
        case "SMS": return "短信"
        case "RCS": return "RCS"
        case "iMessage": return "iMessage"
        default: return "历史记录未注明"
        }
    }
}
struct Parcel: Identifiable {
    let id: String
    let events: [ParcelEvent]
    var latest: ParcelEvent { events[0] }
    var platformClue: PlatformClue { PlatformDetector.identify(events) }
    // 只有最新短信仍明确给出取件码，才展示为当前可用码。
    var currentCode: String? { latest.status == .pickup ? latest.code : nil }
}
struct ReceiptLedger: Codable {
    var manualDates: [String: Date] = [:]
    var archivedEvents: [ParcelEvent] = []
    func isReceived(_ parcel: Parcel) -> Bool { manualDates[parcel.id] != nil || parcel.latest.status == .delivered }
    func receivedDate(_ parcel: Parcel) -> Date { manualDates[parcel.id] ?? parcel.latest.date }
    mutating func reconcile(_ incoming: [ParcelEvent]) -> [Parcel] {
        var byID = Dictionary(archivedEvents.map { ($0.id,$0) }, uniquingKeysWith: { _, newer in newer })
        for event in incoming { byID[event.id] = event }
        let parcels = ParcelParser.group(Array(byID.values))
        archivedEvents = parcels.filter { isReceived($0) }.flatMap(\.events)
        return parcels
    }
    mutating func markReceived(_ parcel: Parcel, at date: Date = Date()) {
        manualDates[parcel.id] = date
        var byID = Dictionary(archivedEvents.map { ($0.id,$0) }, uniquingKeysWith: { _,newer in newer })
        for event in parcel.events { byID[event.id] = event }
        archivedEvents = Array(byID.values)
    }
    mutating func undoManualMark(_ parcel: Parcel) {
        manualDates.removeValue(forKey:parcel.id)
        if parcel.latest.status != .delivered { let ids = Set(parcel.events.map(\.id)); archivedEvents.removeAll { ids.contains($0.id) } }
    }
}
struct ParcelParser {
    static func match(_ pattern: String, _ text: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(result.range(at: result.numberOfRanges > 1 ? 1 : 0), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func parse(id: Int64, date: Date, sender: String, body: String, service: String? = nil) -> ParcelEvent? {
        // 验证码与广告不当作物流进度。
        if body.contains("验证码") || body.contains("校验码") || body.contains("登录密码") { return nil }
        let brands = ["顺丰", "中通", "圆通", "申通", "韵达", "极兔", "京东物流", "京东快递", "邮政", "EMS", "德邦", "菜鸟", "丰巢", "兔喜", "妈妈驿站", "快递超市"]
        let carrier = brands.first { body.localizedCaseInsensitiveContains($0) } ?? "快递"
        let relevant = body.range(of: "快递|包裹|运单|取件码|提货码|签收|驿站|丰巢|寄件|快件|派件|派送", options: .regularExpression) != nil
        guard relevant || carrier != "快递" else { return nil }
        let progress = body.range(of: "取件码|提货码|取货码|已到|到达|入库|已存|已放|签收|派送|派件|配送|上门|揽收|已寄|已发|运输|运单|在途|离开|发往", options: .regularExpression) != nil
        guard progress else { return nil }
        let code = match("(?:取件码|提货码|取货码)\\s*(?:为|是)?\\s*[:：]?\\s*[【\\[]?([A-Z0-9]+(?:[-－—][A-Z0-9]+){0,4})(?![A-Z0-9])", body)
        // 只认明确标注的完整运单号，不把手机号、订单号或尾号用作归并键。
        let tracking = match("(?:快递单号|运单号|物流单号|运单编号|运单|单号)\\s*[:：为]?\\s*([A-Z]{0,6}[0-9]{8,22})(?![A-Z0-9*＊])", body)
        var status: ParcelStatus = .unknown
        if body.range(of: "已取件|已领取|已取出|本人签收|收件人签收", options: .regularExpression) != nil { status = .delivered }
        else if code != nil || body.range(of: "请.{0,8}(取件|取货)|已入库|已存入|已放[在至入]|到达.{0,30}(驿站|快递柜)", options: .regularExpression) != nil { status = .pickup }
        else if body.contains("已签收") { status = .delivered }
        else if body.range(of: "即将.{0,10}(上门|送达)|预计.{0,12}(分钟|小时).{0,12}(送达|上门)|预约.{0,12}上门", options: .regularExpression) != nil { status = .approaching }
        else if body.range(of: "正在派|派送中|派件中|配送中|为您派送|正在配送|开始派送", options: .regularExpression) != nil { status = .delivery }
        else if body.range(of: "已揽收|已寄出|寄件成功|寄出成功|揽件成功", options: .regularExpression) != nil { status = .sent }
        else if body.range(of: "运输|在途|转运|离开|发往|到达", options: .regularExpression) != nil { status = .transit }
        let station = match("(?:已存入|已放在|已放至|已放入|已到达|已送达|请到|请至|到达)\\s*([^，。；！\\n]{2,50}(?:驿站|快递柜|快递超市|代收点|服务站))", body)
        let eta = match("((?:预计|预计于|将于)[^，。；！\\n]{1,45}(?:送达|上门|到达))", body)
        return ParcelEvent(id: id, date: date, sender: sender, body: body, carrier: carrier, tracking: tracking, code: code, station: station, eta: eta, status: status, service: service)
    }
    static func group(_ events: [ParcelEvent]) -> [Parcel] {
        let groups = Dictionary(grouping: events) { event in event.tracking.map { "tracking:\($0.uppercased())" } ?? "sms:\(event.id)" }
        return groups.map { Parcel(id: $0.key, events: $0.value.sorted { $0.date > $1.date }) }.sorted { $0.latest.date > $1.latest.date }
    }
}
