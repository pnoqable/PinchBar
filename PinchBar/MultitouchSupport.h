#import <Foundation/Foundation.h>

@interface Multitouch : NSObject

+ (bool)start;

+ (NSInteger)onMousepad;
+ (NSInteger)onTrackpad;

+ (bool)isOneAndAHalfTap;
+ (bool)isDoubleTap;

@end
