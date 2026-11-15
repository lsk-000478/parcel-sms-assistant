import SwiftUI
import MapKit
import CoreLocation

struct RecyclingPlace: Identifiable, Codable, Equatable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let phone: String?
    let website: String?
    var id: String { "\(name)-\(String(format:"%.5f",latitude))-\(String(format:"%.5f",longitude))" }
    var coordinate: CLLocationCoordinate2D { .init(latitude:latitude,longitude:longitude) }
    func distance(from center: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude:latitude,longitude:longitude).distance(from:CLLocation(latitude:center.latitude,longitude:center.longitude))
    }
    static func nearby(_ places: [Self], center: CLLocationCoordinate2D, radius: Double) -> [Self] {
        var seen=Set<String>()
        return places.filter { seen.insert($0.id).inserted && $0.distance(from:center) <= radius }
            .sorted { $0.distance(from:center) < $1.distance(from:center) }
    }
    func openMap() {
        let item=MKMapItem(placemark:MKPlacemark(coordinate:coordinate))
        item.name=name
        item.openInMaps()
    }
}

@MainActor final class RecyclingStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var address=""
    @Published var radius=5
    @Published var places:[RecyclingPlace]=[]
    @Published var preview:RecyclingPlace?
    @Published var chosen:RecyclingPlace?
    @Published var center:CLLocationCoordinate2D?
    @Published var areaLabel="尚未设置搜索位置"
    @Published var message="输入城市、街道或附近地标，查找纸箱回收的候选收购方。"
    @Published var busy=false
    private let locator=CLLocationManager()
    private var locating=false
    private let key="recycling.chosen.v1"
    override init() {
        super.init()
        locator.delegate=self
        locator.desiredAccuracy=kCLLocationAccuracyHundredMeters
        if let data=UserDefaults.standard.data(forKey:key) {
            chosen=try? JSONDecoder().decode(RecyclingPlace.self,from:data)
        }
    }
    func choose(_ place:RecyclingPlace) {
        guard let data=try? JSONEncoder().encode(place) else { return }
        UserDefaults.standard.set(data,forKey:key)
        chosen=place
    }
    func clearChoice() { UserDefaults.standard.removeObject(forKey:key); chosen=nil }
    func locate() {
        guard !busy else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            message="系统定位未开启。可以手动输入地址查找，无需开启定位。"; return
        }
        locating=true; busy=true; message="等待本次定位…"
        switch locator.authorizationStatus {
        case .notDetermined: locator.requestWhenInUseAuthorization()
        case .authorizedAlways,.authorizedWhenInUse: locator.requestLocation()
        default: locationUnavailable()
        }
    }
    private func locationUnavailable() {
        locating=false; busy=false
        message="未获得定位权限。请手动输入地址，或在系统设置中为本应用允许定位。"
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.locating else { return }
            switch self.locator.authorizationStatus {
            case .authorizedAlways,.authorizedWhenInUse: self.locator.requestLocation()
            case .denied,.restricted: self.locationUnavailable()
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.locating else { return }
            self.locating=false
            guard let location=locations.last,location.horizontalAccuracy >= 0,
                  abs(location.timestamp.timeIntervalSinceNow) < 120 else {
                self.busy=false; self.message="暂时无法获得有效位置，请手动输入地址。"; return
            }
            await self.search(near:location.coordinate,label:"当前位置（本次定位）")
        }
    }
    nonisolated func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) {
        Task { @MainActor [weak self] in
            guard let self,self.locating else { return }
            self.locating=false; self.busy=false
            self.message="定位失败，请手动输入地址查找。"
        }
    }
    func searchAddress() async {
        let query=address.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !busy else { return }
        guard !query.isEmpty else { message="请先输入城市、街道或地标。"; return }
        busy=true; places=[]; preview=nil; center=nil
        message="正在确认搜索区域…"
        do {
            let request=MKLocalSearch.Request(); request.naturalLanguageQuery=query
            request.resultTypes=[.address,.pointOfInterest]
            let response=try await MKLocalSearch(request:request).start()
            guard let item=response.mapItems.first else {
                busy=false; message="找不到这个地址，请补充城市和街道后再试。"; return
            }
            await search(near:item.placemark.coordinate,label:item.name ?? query)
        } catch { busy=false; message="地址查询失败，请检查网络，或换一个更明确的地址。" }
    }
    private func search(near coordinate:CLLocationCoordinate2D,label:String) async {
        center=coordinate; areaLabel=label; places=[]; preview=nil
        message="正在查询附近的回收点…"
        let meters=Double(radius)*1000
        var results:[RecyclingPlace]=[]; var completed=0
        for keyword in ["再生资源回收","废品收购站","废纸回收"] {
            let request=MKLocalSearch.Request()
            request.naturalLanguageQuery=keyword; request.resultTypes = .pointOfInterest
            request.region=MKCoordinateRegion(center:coordinate,latitudinalMeters:meters*2,longitudinalMeters:meters*2)
            do {
                let response=try await MKLocalSearch(request:request).start()
                completed += 1
                results += response.mapItems.map { item in
                    let p=item.placemark
                    let address=[p.locality,p.subLocality,p.thoroughfare,p.subThoroughfare].compactMap{$0}.joined()
                    return RecyclingPlace(name:item.name ?? "未命名回收点",address:address.isEmpty ? (p.title ?? "地图未提供地址") : address,
                        latitude:p.coordinate.latitude,longitude:p.coordinate.longitude,phone:item.phoneNumber,website:item.url?.absoluteString)
                }
            } catch { /* Keep successful searches; never fabricate fallback merchants. */ }
        }
        places=RecyclingPlace.nearby(results,center:coordinate,radius:meters)
        busy=false
        if completed == 0 { message="地图服务暂不可用，请稍后重试。没有生成或填充商户。" }
        else if places.isEmpty { message="本次在\(radius)公里内未找到候选回收点。可以扩大范围或换一个附近地标。" }
        else { message="找到\(places.count)个候选回收点，按直线距离排序。\(completed < 3 ? "部分查询未完成，可稍后重试。" : "")" }
    }
}

struct RecyclingView:View {
    @ObservedObject var store:RecyclingStore
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Label("纸箱回收",systemImage:"arrow.3.trianglepath").font(.title2.bold())
            TextField("城市、街道或附近地标",text:$store.address).textFieldStyle(.roundedBorder)
                .onSubmit { Task { await store.searchAddress() } }
            HStack {
                Picker("范围",selection:$store.radius) { ForEach([3,5,10,20],id:\.self) { Text("\($0)公里").tag($0) } }.frame(maxWidth:180)
                Button("查找回收点") { Task { await store.searchAddress() } }.buttonStyle(.borderedProminent).disabled(store.busy)
            }
            HStack {
                Button("使用当前位置查找",systemImage:"location") { store.locate() }.disabled(store.busy)
                if store.chosen != nil { Button("查看已选收购方") { store.preview=store.chosen } }
            }
            Text("查询会将输入的地址或本次位置及回收搜索词发送至 Apple 地图服务，不发送短信内容。定位仅在你点击并允许后使用。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(store.areaLabel).font(.headline)
            Text(store.message).font(.callout).foregroundStyle(.secondary)
            if store.busy { ProgressView().controlSize(.small) }
            ScrollView {
                LazyVStack(spacing:12) {
                    ForEach(store.places) { place in
                        Button { store.preview=place } label: {
                            VStack(alignment:.leading,spacing:8) {
                                HStack { Text(place.name).font(.headline); Spacer(); if store.chosen?.id == place.id { Label("已选择",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green) } }
                                Text(place.address).font(.callout).foregroundStyle(.secondary)
                                if let center=store.center { Text(String(format:"距搜索中心约 %.1f 公里（直线）",place.distance(from:center)/1000)).font(.caption).foregroundStyle(.secondary) }
                            }.padding().frame(maxWidth:.infinity,alignment:.leading)
                                .background(store.preview?.id == place.id ? Color.teal.opacity(0.12) : Color(nsColor:.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding().navigationSplitViewColumnWidth(min:340,ideal:420)
    }
}

struct RecyclingDetailView:View {
    @ObservedObject var store:RecyclingStore
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if let place=store.preview {
                    Label(place.name,systemImage:"shippingbox").font(.title2.bold())
                    Text(place.address).textSelection(.enabled)
                    if let phone=place.phone,!phone.isEmpty { Text("联系电话：\(phone)").textSelection(.enabled) }
                    else { Text("地图未提供联系电话，可打开地图查看商户资料。").foregroundStyle(.secondary) }
                    if let website=place.website, let url=URL(string:website),["http","https"].contains(url.scheme?.lowercased() ?? "") { Link("商户网站",destination:url) }
                    Button("在地图中查看") { place.openMap() }
                    if store.chosen?.id == place.id {
                        Label("已选为我的收购方",systemImage:"checkmark.circle.fill").foregroundStyle(.green)
                        Button("取消选择") { store.clearChoice() }
                    } else { Button("选择这家收购方") { store.choose(place) }.buttonStyle(.borderedProminent) }
                    Text("选择只保存在本机，不会发送你的联系方式、预约回收或通知商户。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName:"shippingbox.and.arrow.backward").font(.system(size:42)).foregroundStyle(.teal)
                    Text("让快递盒再利用").font(.title2.bold())
                    Text("先查找附近回收点，再从列表挑选收购方。你的选择会保留，重新打开后可通过“查看已选收购方”找到。")
                }
                Divider()
                Text("交付前先联系确认").font(.headline)
                Text("结果来自地图的回收类商户资料，未核实是否收纸箱、当前营业、收购价格或上门服务。按距离排列供你比较，不代表商户认证或服务承诺。")
                Text("纸箱保持干燥，去除快递面单或涂盖姓名、地址和电话，再联系收购方确认接收方式。").foregroundStyle(.secondary)
                Text("地址搜索以地图解析的地点为中心；距离为直线距离，并非道路距离。已选商户是上次保存的资料快照。").font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
