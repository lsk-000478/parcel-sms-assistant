import Foundation
import Combine
import SQLite3

struct InboxRead {
    let events: [ParcelEvent]
    let scanned: Int
    let unreadable: Int
}
enum InboxFailure: LocalizedError {
    case access, incompatible
    var errorDescription: String? {
        switch self {
        case .access: return "无法读取本机信息。请在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中添加并允许“快递短信助手”，然后退出并重新打开应用。"
        case .incompatible: return "当前“信息”数据库格式不兼容，尚未读取短信。"
        }
    }
}
struct InboxReader {
    static func read(databaseURL: URL = URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Messages/chat.db"), now: Date = Date()) throws -> InboxRead {
        let path = databaseURL.path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database = db else {
            if let db { sqlite3_close(db) }; throw InboxFailure.access
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2000)
        // 只读，不复制数据库、不修改短信或已读状态。
        var statement: OpaquePointer?
        let sql = """
        SELECT m.ROWID, m.date, m.text, m.attributedBody, h.id, m.service
        FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.is_from_me = 0 AND m.date > ? AND m.service IN ('SMS', 'RCS', 'iMessage')
        ORDER BY m.date DESC LIMIT 5000
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw InboxFailure.incompatible }
        defer { sqlite3_finalize(statement) }
        let cutoff = now.addingTimeInterval(-90*24*3600).timeIntervalSinceReferenceDate * 1_000_000_000
        sqlite3_bind_double(statement, 1, cutoff)
        var events: [ParcelEvent] = []; var scanned = 0; var unreadable = 0
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            scanned += 1
            var text = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            if text.isEmpty, let pointer = sqlite3_column_blob(statement, 3) {
                let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 3)))
                if let value = BodyDecoder.decode(data) { text = value }
                else { unreadable += 1 }
            }
            let sender = sqlite3_column_text(statement, 4).map { String(cString:$0) } ?? "未知号码"
            let service = sqlite3_column_text(statement, 5).map { String(cString:$0) }
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1) / 1_000_000_000)
            if let event = ParcelParser.parse(id:sqlite3_column_int64(statement,0),date:date,sender:sender,body:text,service:service) { events.append(event) }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw InboxFailure.access }
        return InboxRead(events:events,scanned:scanned,unreadable:unreadable)
    }
}
@MainActor final class InboxStore: ObservableObject {
    @Published var parcels: [Parcel] = []
    @Published var error: String?
    @Published var lastRefresh: Date?
    @Published var busy = false
    @Published var coverage = "读取最近90天、最多5000条收到的信息（短信、RCS、iMessage）；仅保留识别到的快递通知。"
    @Published var autoRefresh = false
    @Published var started = false
    @Published var ledger = ReceiptLedger()
    @Published var archiveError: String?
    private var archiveCorrupt = false
    private let archiveURL = URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/ParcelSMSInbox/receipts.json")
    init() {
        do {
            if FileManager.default.fileExists(atPath:archiveURL.path) {
                ledger = try JSONDecoder().decode(ReceiptLedger.self,from:Data(contentsOf:archiveURL))
                parcels = ParcelParser.group(ledger.archivedEvents)
            }
        } catch { archiveCorrupt = true; archiveError = "本地归档读取失败，原文件未覆盖。\(error.localizedDescription)" }
    }
    private func persist(_ candidate: ReceiptLedger) throws {
        // 不覆盖无法读取的旧归档，避免静默丢失记录。
        if archiveCorrupt { throw NSError(domain:"归档不可写，请先检查本地归档文件",code:1) }
        try FileManager.default.createDirectory(at:archiveURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(candidate).write(to:archiveURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:archiveURL.path)
    }
    func markReceived(_ parcel: Parcel) {
        var candidate = ledger; candidate.markReceived(parcel)
        do { try persist(candidate); ledger = candidate; archiveError = nil } catch { archiveError = "收货标记未保存：\(error.localizedDescription)" }
    }
    func undoManualMark(_ parcel: Parcel) {
        var candidate = ledger; candidate.undoManualMark(parcel)
        do { try persist(candidate); ledger = candidate; archiveError = nil } catch { archiveError = "撤销未保存：\(error.localizedDescription)" }
    }
    func refresh() async {
        guard !busy else { return }; started = true; busy = true
        do {
            let read = try await Task.detached { try InboxReader.read() }.value
            var candidate = ledger
            parcels = candidate.reconcile(read.events)
            do { try persist(candidate); ledger = candidate; archiveError = nil } catch { archiveError = "归档保存失败：\(error.localizedDescription)" }
            error = nil; lastRefresh = Date()
            coverage = "已检查最近90天内 \(read.scanned) 条信息（短信、RCS、iMessage）；识别出 \(read.events.count) 条快递通知。\(read.scanned == 5000 ? "已达到5000条上限，更早信息未读取。" : "")\(read.unreadable > 0 ? "其中 \(read.unreadable) 条信息的正文格式暂不支持，可能漏掉通知。" : "")"
            autoRefresh = true
        } catch { self.error = error.localizedDescription; autoRefresh = false }
        busy = false
    }
}
