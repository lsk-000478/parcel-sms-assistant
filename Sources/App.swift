import SwiftUI
import AppKit

struct PlatformBadge: View {
    let clue: PlatformClue
    var tint: Color {
        switch clue.platform {
        case .taobao, .xiaomi: return .orange
        case .tmall, .jd, .pdd, .rednote: return .red
        case .douyin: return .cyan
        case .kuaishou: return .orange
        case .wechat: return .green
        case .vip: return .pink
        case .suning: return .yellow
        case .dewu: return .teal
        case nil: return .secondary
        }
    }
    var body: some View {
        HStack(spacing:7) {
            ZStack {
                RoundedRectangle(cornerRadius:7).fill(tint.opacity(0.16))
                if let platform = clue.platform { Text(platform.glyph).font(.system(size:18,weight:.bold)).foregroundStyle(tint) }
                else { Image(systemName:"bag.badge.questionmark").foregroundStyle(tint) }
            }.frame(width:30,height:30).accessibilityHidden(true)
            Text(clue.label).font(.callout.weight(.medium))
        }.help(clue.evidence).accessibilityElement(children:.ignore).accessibilityLabel("购物平台：\(clue.label)")
    }
}

struct ContentView: View {
    @StateObject private var store = InboxStore()
    @StateObject private var recycling = RecyclingStore()
    @State private var filter = "进行中"
    @State private var query = ""
    @State private var selection: String?
    private var filtered: [Parcel] {
        store.parcels.filter { p in
            let received = store.ledger.isReceived(p)
            let matches = filter == "全部通知" || (filter == "进行中" && !received) || (filter == "已收货归档" && received) || (filter == "待取件" && !received && p.latest.status == .pickup) || (filter == "配送到家" && !received && [.delivery,.approaching].contains(p.latest.status)) || (filter == "寄出 / 运输" && !received && [.sent,.transit].contains(p.latest.status))
            return matches && (query.isEmpty || p.platformClue.label.localizedCaseInsensitiveContains(query) || p.events.contains { $0.body.localizedCaseInsensitiveContains(query) || $0.carrier.contains(query) })
        }
    }
    private var selected: Parcel? { filtered.first { $0.id == selection } }
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:16) {
                Label("快递短信助手",systemImage:"shippingbox.fill").font(.title2.bold()).padding(.top)
                Text("支持短信、RCS 与 iMessage").foregroundStyle(.secondary).font(.caption)
                ForEach(["进行中","待取件","配送到家","寄出 / 运输","已收货归档","全部通知","纸箱回收"], id:\.self) { item in
                    Button { filter=item; selection=nil } label: {
                        HStack { Text(item); Spacer(); if item == "已收货归档" { Text("\(store.parcels.filter { store.ledger.isReceived($0) }.count)") } else if item == "进行中" { Text("\(store.parcels.filter { !store.ledger.isReceived($0) }.count)") } }
                            .padding(10).background(filter == item ? Color.accentColor.opacity(0.16) : Color.clear).clipShape(RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain)
                }
                Spacer()
                if let date=store.lastRefresh { Text("上次同步 \(date.formatted(date:.omitted,time:.shortened))").font(.caption).foregroundStyle(.secondary) }
                Toggle("每分钟刷新",isOn:$store.autoRefresh).disabled(store.lastRefresh == nil)
                Text("快递信息本机处理\n回收查询使用联网地图").font(.caption).foregroundStyle(.secondary)
            }.padding().frame(minWidth:190)
        } content: {
            if filter == "纸箱回收" { RecyclingView(store:recycling) } else {
            VStack(spacing:0) {
                HStack { TextField("搜索平台、运单或短信",text:$query).textFieldStyle(.roundedBorder); Button { Task { await store.refresh() } } label: { Image(systemName:"arrow.clockwise") }.disabled(store.busy) }.padding()
                if store.busy { ProgressView("正在读取短信…").padding() }
                if let error=store.error, filtered.isEmpty { ScrollView { VStack(alignment:.leading,spacing:16) { Label("需要读取短信的权限",systemImage:"lock.shield").font(.headline); Text(error); Text("完全磁盘访问权限允许应用接触其他受保护文件，范围较广。本应用仅使用只读方式读取“信息”短信；你可随时在系统设置中撤销权限。").foregroundStyle(.secondary); Button("打开隐私设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) } }.padding() } }
                else if !store.started && filtered.isEmpty { VStack(alignment:.leading,spacing:18) { Text("连接 Mac 的短信").font(.title2.bold()); Text("请确保 iPhone 的快递短信已同步到 Mac“信息”。点击下方按钮后，应用会在本机读取最近90天的短信，并筛选快递通知。"); Text("若系统拒绝访问，需要你手动授予本应用完全磁盘访问权限。").foregroundStyle(.secondary); Button("开始读取快递短信") { Task { await store.refresh() } }.buttonStyle(.borderedProminent) }.padding(24); Spacer() }
                else if filtered.isEmpty { VStack(spacing:14) { Image(systemName:"tray").font(.largeTitle); Text(store.parcels.isEmpty ? "暂未识别到快递短信" : "没有符合筛选的通知"); Text("尚未收到短信、短信未同步或正文格式不支持，都可能导致缺少记录。").font(.caption).foregroundStyle(.secondary) }.padding(); Spacer() }
                else { List(filtered,selection:$selection) { p in
                    VStack(alignment:.leading,spacing:7) {
                        PlatformBadge(clue:p.platformClue)
                        HStack { Text(p.latest.carrier).bold(); Spacer(); Text(store.ledger.isReceived(p) ? "已收货" : p.latest.status.rawValue).font(.caption).foregroundStyle(color(p.latest.status)) }
                        if let code=p.currentCode, !store.ledger.isReceived(p) { Text("取件码 \(code)").font(.title3.monospaced().bold()) }
                        Text(p.latest.body).lineLimit(2).font(.callout).foregroundStyle(.secondary)
                        Text(p.latest.date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical,8).tag(p.id)
                } }
                if let archiveError=store.archiveError { Text(archiveError).font(.caption).foregroundStyle(.red).padding() }
                Text(store.coverage).font(.caption2).foregroundStyle(.secondary).padding()
            }.navigationSplitViewColumnWidth(min:300,ideal:370)
            }
        } detail: {
            if filter == "纸箱回收" { RecyclingDetailView(store:recycling) }
            else if let p=selected { ScrollView { VStack(alignment:.leading,spacing:20) {
                HStack { Image(systemName:"shippingbox").font(.largeTitle).foregroundStyle(color(p.latest.status)); VStack(alignment:.leading) { Text(p.latest.carrier).font(.title.bold()); Text(store.ledger.isReceived(p) ? "已收货" : p.latest.status.rawValue).foregroundStyle(color(p.latest.status)) } }
                VStack(alignment:.leading,spacing:8) {
                    Text("购买平台").font(.caption).foregroundStyle(.secondary)
                    PlatformBadge(clue:p.platformClue)
                    Text(p.platformClue.evidence).font(.caption).foregroundStyle(.secondary)
                }
                if let code=p.currentCode, !store.ledger.isReceived(p) { VStack(alignment:.leading,spacing:8) { Text("短信中的取件码").foregroundStyle(.secondary); Text(code).font(.system(size:36,weight:.bold,design:.monospaced)).textSelection(.enabled); Text("请以原短信和驿站实际状态为准。").font(.caption).foregroundStyle(.secondary) }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:12)) }
                if store.ledger.isReceived(p) {
                    VStack(alignment:.leading,spacing:8) {
                        Label("已收货归档",systemImage:"checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                        Text(store.ledger.manualDates[p.id] != nil ? "来源：你在本工具中手动标记" : "来源：短信显示已签收或已取件").font(.callout)
                        Text("记录时间：\(store.ledger.receivedDate(p).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                        if store.ledger.manualDates[p.id] != nil { Button("撤销手动标记") { store.undoManualMark(p) } }
                    }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.green.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:12))
                } else {
                    Button("标记已收货并归档") { store.markReceived(p); filter="已收货归档"; selection=p.id }.buttonStyle(.borderedProminent)
                    Text("用于你已确认收货但没有收到签收短信的情况。工具无法自动读取购物平台中的确认收货操作。").font(.caption).foregroundStyle(.secondary)
                }
                field("运单号",p.latest.tracking ?? "短信未提供完整运单号")
                field("商品", "短信未明确提供商品名称")
                field("预计送达",p.latest.eta ?? "短信未提供，不作推算")
                field("取件地点",p.latest.station ?? "请查看下方原短信")
                if p.latest.tracking == nil { Text("此通知缺少完整运单号，暂未与其他短信合并。").font(.callout).foregroundStyle(.secondary) }
                Divider(); Text("短信时间线").font(.headline)
                ForEach(p.events) { e in VStack(alignment:.leading,spacing:10) { HStack { Text(e.status.rawValue).bold(); Spacer(); Text(e.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }; Text(e.body).textSelection(.enabled); Text("消息类型：\(e.serviceLabel) · 来源：\(e.sender)").font(.caption).foregroundStyle(.secondary) }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:10)) }
            }.padding(28) } } else { VStack(spacing:14) { Image(systemName:"text.bubble").font(.system(size:48)).foregroundStyle(.teal); Text("选择一条快递通知").font(.title2); Text("查看取件码、原短信及包裹进度").foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity) }
        }.frame(minWidth:1000,minHeight:650).task { while !Task.isCancelled { do { try await Task.sleep(for:.seconds(60)) } catch { break }; if store.autoRefresh { await store.refresh() } } }
    }
    func color(_ s: ParcelStatus) -> Color { switch s { case .pickup: return .green; case .delivery,.approaching: return .orange; case .delivered: return .secondary; default: return .teal } }
    func field(_ name:String,_ value:String) -> some View { VStack(alignment:.leading,spacing:5) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
}
@main struct ParcelInboxApp: App { var body: some Scene { WindowGroup { ContentView() }.defaultSize(width:1120,height:730) } }
