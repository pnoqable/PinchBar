#import "MultitouchSupport.h"

#import <Cocoa/Cocoa.h>

#import <array>
#import <map>
#import <mutex>
#import <vector>

#pragma mark linked symbols

struct MTTouch {
    int frame;
    double timestamp;
    int fid, state, pad[2];
    float uv[2], dUV[2];
    float size;
    int zero1;
    float angle, r1, r2;
    float mm[2], dMM[2];
    int zero2[2];
    float pad2;
};

typedef const void* MTDeviceRef;
typedef const MTTouch* MTTouchRef;

typedef void (*MTContactCallbackFunction)(MTDeviceRef, MTTouchRef, int, double);

extern "C" CFArrayRef MTDeviceCreateList(void);

extern "C" void MTDeviceGetSensorSurfaceDimensions(MTDeviceRef, int*, int*);

extern "C" void MTDeviceStart(MTDeviceRef, int);
extern "C" void MTDeviceStop(MTDeviceRef);

extern "C" void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
extern "C" void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);

#pragma mark private variables

IONotificationPortRef ioNotificationPort = NULL;
CFArrayRef multitouchDevices = NULL;

std::recursive_mutex mutex;

bool isTrackpad = false;
int touchCount = 0;

std::map<int, std::array<float, 2>> touchStartPositions;

double lastTouchTime = 0;
std::vector<int> lastTouchCounts;

Callback onTrackpadTap = nil;

#pragma mark private functions

static void contactFrameCallback(MTDeviceRef device, MTTouchRef touches, int count, double time) {
    int width, height;
    MTDeviceGetSensorSurfaceDimensions(device, &width, &height);
    
    std::lock_guard lock(mutex);
    
    bool isTrackpadNow = width > height;
    if(isTrackpad != isTrackpadNow) {
        isTrackpad = isTrackpadNow;
        lastTouchTime = 0;
        lastTouchCounts.clear();
    }
    
    if(touchCount == 0 && count > 0) {
        if(time - lastTouchTime > NSEvent.doubleClickInterval) {
            lastTouchCounts.clear();
        }
        
        lastTouchTime = time;
    }
    
    if(count > touchCount && touchStartPositions.size() > touchCount) {
        touchStartPositions.clear();
    }
    
    touchCount = count;
    
    if(lastTouchTime != 0) {
        for(const MTTouch* t = touches; t < touches + count; t++) {
            auto p = touchStartPositions.emplace(t->fid, std::to_array(t->mm)).first->second;
            if(fmax(fabs(p[0] - t->mm[0]), fabs(p[1] - t->mm[1])) > 2) {
                lastTouchTime = 0;
            }
        }
    }
    
    if(count == 0) {
        if(time - lastTouchTime < NSEvent.doubleClickInterval) {
            lastTouchCounts.push_back((int)touchStartPositions.size());
            
            if(isTrackpad && onTrackpadTap) {
                onTrackpadTap();
            }
        } else {
            lastTouchCounts.clear();
        }
    }
}

static bool registerContactFrameCallback(void) {
    if(multitouchDevices) {
        for(int i=0; i<CFArrayGetCount(multitouchDevices); i++) {
            MTDeviceRef device = CFArrayGetValueAtIndex(multitouchDevices, i);
            MTUnregisterContactFrameCallback(device, contactFrameCallback);
            MTDeviceStop(device);
        }
        CFRelease(multitouchDevices);
    }
    
    multitouchDevices = MTDeviceCreateList();
    
    if(!multitouchDevices) {
        return false;
    }
    
    for(int i=0; i<CFArrayGetCount(multitouchDevices); i++) {
        MTDeviceRef device = CFArrayGetValueAtIndex(multitouchDevices, i);
        MTRegisterContactFrameCallback(device, contactFrameCallback);
        MTDeviceStart(device, 0);
    }
    
    return true;
}

static void releaseIOObjects(io_iterator_t iterator) {
    for(io_object_t object = IOIteratorNext(iterator); object; object = IOIteratorNext(iterator)) {
        IOObjectRelease(object);
    }
}

static void multitouchDeviceAddedCallback(void *refcon, io_iterator_t iterator) {
    releaseIOObjects(iterator);
    registerContactFrameCallback();
}

static bool registerMultitouchDeviceAddedCallback(void) {
    if(ioNotificationPort) {
        return true;
    }
    
    ioNotificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(ioNotificationPort),
                       kCFRunLoopDefaultMode);
    
    io_iterator_t iterator;
    kern_return_t error = IOServiceAddMatchingNotification(ioNotificationPort,
                                                           kIOFirstMatchNotification,
                                                           IOServiceMatching("AppleMultitouchDevice"),
                                                           multitouchDeviceAddedCallback,
                                                           NULL, &iterator);
    if(error) {
        IONotificationPortDestroy(ioNotificationPort);
        ioNotificationPort = NULL;
        return false;
    }
    
    releaseIOObjects(iterator);
    return true;
}

#pragma mark implementation

@implementation Multitouch

+ (bool)start {
    return registerContactFrameCallback() && registerMultitouchDeviceAddedCallback();
}

+ (NSInteger)onMousepad {
    std::lock_guard lock(mutex);
    return isTrackpad ? 0 : touchCount;
}

+ (NSInteger)onTrackpad {
    std::lock_guard lock(mutex);
    return isTrackpad ? touchCount : 0;
}

+ (bool)isOneAndAHalfTap {
    std::lock_guard lock(mutex);
    return touchCount && lastTouchCounts == std::vector{1};
}

+ (bool)isDoubleTap {
    std::lock_guard lock(mutex);
    return touchCount && lastTouchCounts == std::vector{touchCount};
}

+ (void)setOnTrackpadTap:(Callback)callback {
    std::lock_guard lock(mutex);
    onTrackpadTap = callback;
}

+ (NSInteger)lastTouchCount {
    std::lock_guard lock(mutex);
    return lastTouchCounts.size() ? lastTouchCounts.back() : 0;
}

@end
