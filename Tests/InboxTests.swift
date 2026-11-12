import Foundation
import SQLite3

@main struct InboxTests {
    static func main() throws {
        // A synthetic database only: never open the user's Messages database in tests.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("fixture.db")
        var db: OpaquePointer?
        guard sqlite3_open(url.path,&db) == SQLITE_OK, let db else { fatalError("fixture open") }
        defer { sqlite3_close(db) }
        func sql(_ value: String) {
            guard sqlite3_exec(db,value,nil,nil,nil) == SQLITE_OK else { fatalError(String(cString:sqlite3_errmsg(db))) }
        }
        sql("CREATE TABLE handle (id TEXT); INSERT INTO handle VALUES ('test-sender');")
        sql("CREATE TABLE message (date REAL, text TEXT, attributedBody BLOB, handle_id INTEGER, is_from_me INTEGER, service TEXT);")
        let now = Date()
        func add(_ service: String, _ text: String, outgoing: Bool = false, age: Double = 0, attributed: Bool = false) throws {
            var stmt: OpaquePointer?
            assert(sqlite3_prepare_v2(db,"INSERT INTO message VALUES (?, ?, ?, 1, ?, ?)",-1,&stmt,nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
            sqlite3_bind_double(stmt,1,now.addingTimeInterval(-age).timeIntervalSinceReferenceDate * 1_000_000_000)
            if attributed {
                let data = try NSKeyedArchiver.archivedData(withRootObject:NSAttributedString(string:text),requiringSecureCoding:true)
                _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt,3,$0.baseAddress,Int32(data.count),transient) }
            } else { sqlite3_bind_text(stmt,2,text,-1,transient) }
            sqlite3_bind_int(stmt,4,outgoing ? 1 : 0)
            sqlite3_bind_text(stmt,5,service,-1,transient)
            assert(sqlite3_step(stmt) == SQLITE_DONE)
        }
        try add("SMS","快递测试：包裹正在配送中")
        try add("RCS","包裹已存入驿站，取件码1-2-3")
        try add("iMessage","快递测试:包裹正在配送中",attributed:true)
        try add("iMessage","晚上一起吃饭")
        try add("iMessage","快递寄件验证码123456")
        try add("iMessage","包裹正在配送中",outgoing:true)
        try add("SMS","包裹正在配送中",age:91*24*3600)
        try add("Unsupported","包裹正在配送中")
        let before = sqlite3_total_changes(db)
        let read = try InboxReader.read(databaseURL:url,now:now)
        assert(read.scanned == 5 && read.events.count == 3 && read.unreadable == 0)
        assert(Set(read.events.compactMap(\.service)) == Set(["SMS","RCS","iMessage"]))
        assert(read.events.first { $0.service == "iMessage" }?.status == .delivery)
        assert(sqlite3_total_changes(db) == before)
        var ledger = ReceiptLedger()
        let parcel = ParcelParser.group(read.events.filter { $0.service == "iMessage" })[0]
        ledger.markReceived(parcel)
        let restored = try JSONDecoder().decode(ReceiptLedger.self,from:JSONEncoder().encode(ledger))
        assert(restored.archivedEvents.first?.service == "iMessage")
        // Old archive records have no service key; they must continue to decode.
        let legacy = ParcelParser.parse(id:99,date:now,sender:"test",body:"包裹已签收")!
        let legacyData = try JSONEncoder().encode(legacy)
        let legacyRecord = try JSONDecoder().decode(ParcelEvent.self,from:legacyData)
        assert(legacyRecord.service == nil)
        print("信息读取回归测试通过：短信、RCS、iMessage、过滤与旧归档兼容")
    }
}
