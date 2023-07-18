#import <Foundation/Foundation.h>

typedef void (^Callback)();

@interface Multitouch : NSObject

+ (bool)start;

+ (NSInteger)onMousepad;
+ (NSInteger)onTrackpad;

+ (bool)isOneAndAHalfTap;
+ (bool)isDoubleTap;

+ (void)setOnTrackpadTap:(Callback)callback;

+ (NSInteger)lastTouchCount;

@end
