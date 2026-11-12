#import "LegacyText.h"
NSString *ParcelDecodeLegacy(NSData *data) {
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        id object = [NSUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
        return [object isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)object string] : nil;
    } @catch (NSException *exception) { return nil; }
}
