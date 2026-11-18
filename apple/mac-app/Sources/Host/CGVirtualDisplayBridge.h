#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Cầu nối tới API riêng CGVirtualDisplay (chấp nhận được vì phát hành ngoài App Store).
/// Toàn bộ khai báo lớp riêng nằm trong .m và chỉ tra cứu lúc chạy (NSClassFromString + respondsToSelector),
/// nên khi macOS đổi/xoá API: `isSupported` = NO hoặc `create...` trả nil kèm lỗi, không crash lúc nạp app.
/// Vòng đời màn hình ảo = vòng đời của đối tượng này (giải phóng = màn hình biến mất).
@interface XDVirtualDisplay : NSObject

@property(class, readonly) BOOL isSupported;
@property(nonatomic, readonly) CGDirectDisplayID displayID;

/// Tạo màn hình ảo `pixelWidth × pixelHeight` điểm ảnh thật; `hiDPI` YES thì thêm mode logic = một nửa (2×).
+ (nullable instancetype)createWithName:(NSString *)name
                             pixelWidth:(NSUInteger)pixelWidth
                            pixelHeight:(NSUInteger)pixelHeight
                            refreshRate:(double)refreshRate
                                  hiDPI:(BOOL)hiDPI
                                  error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
