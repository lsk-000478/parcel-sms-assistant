import Foundation
struct BodyDecoder {
    static func decode(_ data: Data) -> String? {
        guard data.count < 8_000_000 else { return nil }
        let legacyHeader = data.prefix(16).range(of:Data("streamtyped".utf8)) != nil
        if legacyHeader { return ParcelDecodeLegacy(data) }
        guard data.starts(with:Data("bplist".utf8)) || data.starts(with:Data("<?xml".utf8)) else { return nil }
        return (try? NSKeyedUnarchiver.unarchivedObject(ofClasses:[NSAttributedString.self,NSMutableAttributedString.self,NSString.self,NSDictionary.self,NSArray.self,NSNumber.self,NSData.self,NSURL.self],from:data) as? NSAttributedString)?.string
    }
}
