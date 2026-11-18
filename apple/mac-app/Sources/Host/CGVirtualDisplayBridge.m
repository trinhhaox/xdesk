#import "CGVirtualDisplayBridge.h"

// Khai báo riêng chỉ để gõ kiểu; KHÔNG tham chiếu trực tiếp ký hiệu lớp (không link-time dependency).
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, copy) NSArray *modes;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic, strong) dispatch_queue_t queue;
@end

@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

static NSString *const XDErrorDomain = @"vn.xox.xdesk.virtualdisplay";

static NSError *XDFail(NSString *message) {
    return [NSError errorWithDomain:XDErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}

@implementation XDVirtualDisplay {
    id _display; // CGVirtualDisplay, giữ để màn hình còn sống
    CGDirectDisplayID _displayID;
}

+ (BOOL)isSupported {
    Class display = NSClassFromString(@"CGVirtualDisplay");
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class settings = NSClassFromString(@"CGVirtualDisplaySettings");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    if (!display || !descriptor || !settings || !mode) return NO;
    return [display instancesRespondToSelector:@selector(initWithDescriptor:)] &&
           [display instancesRespondToSelector:@selector(applySettings:)] &&
           [display instancesRespondToSelector:@selector(displayID)] &&
           [descriptor instancesRespondToSelector:@selector(setMaxPixelsWide:)] &&
           [descriptor instancesRespondToSelector:@selector(setQueue:)] &&
           [settings instancesRespondToSelector:@selector(setModes:)] &&
           [settings instancesRespondToSelector:@selector(setHiDPI:)] &&
           [mode instancesRespondToSelector:@selector(initWithWidth:height:refreshRate:)];
}

+ (nullable instancetype)createWithName:(NSString *)name
                             pixelWidth:(NSUInteger)pixelWidth
                            pixelHeight:(NSUInteger)pixelHeight
                            refreshRate:(double)refreshRate
                                  hiDPI:(BOOL)hiDPI
                                  error:(NSError **)error {
    if (![self isSupported]) {
        if (error) *error = XDFail(@"CGVirtualDisplay không khả dụng trên bản macOS này");
        return nil;
    }
    CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
    descriptor.name = name;
    descriptor.vendorID = 0x7864; // 'xd'
    descriptor.productID = 0x0001;
    descriptor.serialNum = 1;
    descriptor.maxPixelsWide = (unsigned int)pixelWidth;
    descriptor.maxPixelsHigh = (unsigned int)pixelHeight;
    // ~110 ppi để macOS chọn tỉ lệ hiển thị hợp lý.
    descriptor.sizeInMillimeters = CGSizeMake(pixelWidth * 25.4 / 110.0, pixelHeight * 25.4 / 110.0);
    descriptor.queue = dispatch_get_main_queue();

    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    NSMutableArray *modes = [NSMutableArray array];
    // HiDPI: chỉ đưa mode 2× (điểm = điểm ảnh / 2). Nếu kèm mode 1× gốc, macOS chọn mode 1× và chữ trên viewer rất nhỏ.
    if (hiDPI) {
        [modes addObject:[[modeClass alloc] initWithWidth:pixelWidth / 2 height:pixelHeight / 2 refreshRate:refreshRate]];
    } else {
        [modes addObject:[[modeClass alloc] initWithWidth:pixelWidth height:pixelHeight refreshRate:refreshRate]];
    }
    CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.modes = modes;

    CGVirtualDisplay *display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
    if (!display || display.displayID == 0) {
        if (error) *error = XDFail(@"Không tạo được màn hình ảo (CGVirtualDisplay từ chối descriptor)");
        return nil;
    }
    if (![display applySettings:settings]) {
        if (error) *error = XDFail(@"Không áp dụng được mode cho màn hình ảo");
        return nil;
    }
    XDVirtualDisplay *result = [[XDVirtualDisplay alloc] init];
    result->_display = display;
    result->_displayID = display.displayID;
    return result;
}

- (CGDirectDisplayID)displayID { return _displayID; }

@end
