import Foundation
import CoreLocation
@main struct RecyclingTests {
    static func main() throws {
        let center=CLLocationCoordinate2D(latitude:30,longitude:120)
        func place(_ name:String,_ delta:Double)->RecyclingPlace {
            RecyclingPlace(name:name,address:"测试地址",latitude:30+delta,longitude:120,phone:nil,website:nil)
        }
        let near=place("近处",0.001),far=place("远处",0.02),outside=place("范围之外",1)
        let result=RecyclingPlace.nearby([far,near,near,outside],center:center,radius:5000)
        assert(result.map(\.name) == ["近处","远处"])
        assert(near.distance(from:center) > 100 && near.distance(from:center) < 120)
        let restored=try JSONDecoder().decode(RecyclingPlace.self,from:JSONEncoder().encode(near))
        assert(restored == near && restored.id == near.id)
        assert(RecyclingPlace.nearby([outside],center:center,radius:3000).isEmpty)
        print("回收点距离、去重、范围筛选及已选商户保存格式测试通过")
    }
}
