#import <Foundation/Foundation.h>

typedef void (^LongSetter)(long);

NS_ASSUME_NONNULL_BEGIN

@interface Multitouch : NSObject

@property (class, nonatomic, readonly, nullable) Multitouch *shared NS_SWIFT_NAME(shared);

- (NSInteger)onMousepad;
- (NSInteger)onTrackpad;

- (bool)isOneAndAHalfTap;
- (bool)isDoubleTap;

- (void)setOnTrackpadTap:(nullable LongSetter)callback;

@end

NS_ASSUME_NONNULL_END
