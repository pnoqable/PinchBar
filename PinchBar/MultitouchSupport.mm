#import "MultitouchSupport.h"
#import "MultitouchState.h"

#import <Cocoa/Cocoa.h>

#import <algorithm>
#import <memory>
#import <mutex>
#import <numeric>
#import <vector>

#pragma mark linked symbols

typedef const void* MTDeviceRef;

typedef void (*MTContactCallbackFunction)(MTDeviceRef, MTTouchRef, int, double);
typedef void (*MTContactCallbackRefconFunction)(MTDeviceRef, MTTouchRef, int, double, int, void*);

extern "C" CFArrayRef MTDeviceCreateList(void);

extern "C" void MTDeviceGetSensorSurfaceDimensions(MTDeviceRef, int*, int*);

extern "C" void MTDeviceStart(MTDeviceRef, int);
extern "C" void MTDeviceStop(MTDeviceRef);

extern "C" void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
extern "C" void MTRegisterContactFrameCallbackWithRefcon(MTDeviceRef, MTContactCallbackRefconFunction, void*);
extern "C" void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackRefconFunction);

#pragma mark private variables

IONotificationPortRef ioNotificationPort = NULL;
CFArrayRef multitouchDevices = NULL;

std::recursive_mutex registryMutex;
std::recursive_mutex callbackMutex;
LongSetter onTrackpadTap = nil;

std::vector<std::unique_ptr<MultitouchState>> states;
std::vector<MultitouchState*> trackpadStates;
std::vector<MultitouchState*> mousepadStates;

#pragma mark private classes

class TrackpadTouchState final : public MultitouchState {
protected:
    void tapFinished(int touchCount) override {
        std::lock_guard lock(callbackMutex);
        if(onTrackpadTap) {
            onTrackpadTap(touchCount);
        }
    }
};

#pragma mark private functions

static void contactFrameCallbackWithRefcon(MTDeviceRef device, MTTouchRef touches, int count, double time, int frame, void* refcon);
static bool registerContactFrameCallback(void);
static bool registerMultitouchDeviceAddedCallback(void);
static void unregisterContactFrameCallback(void);
static void unregisterMultitouchDeviceAddedCallback(void);

static void contactFrameCallbackWithRefcon(MTDeviceRef device, MTTouchRef touches, int count, double time, int frame, void* refcon) {
    std::lock_guard lock(registryMutex);
    if(MultitouchState* state = static_cast<MultitouchState*>(refcon)) {
        state->contactFrame(touches, count, time);
    }
}

static bool registerContactFrameCallback(void) {
    std::lock_guard lock(registryMutex);
    
    unregisterContactFrameCallback();
    
    multitouchDevices = MTDeviceCreateList();
    
    if(!multitouchDevices) {
        return false;
    }
    
    for(int i=0; i<CFArrayGetCount(multitouchDevices); i++) {
        MTDeviceRef device = CFArrayGetValueAtIndex(multitouchDevices, i);
        int width, height;
        MTDeviceGetSensorSurfaceDimensions(device, &width, &height);
        
        bool isTrackpad = width > height;
        auto state = isTrackpad
                    ? std::unique_ptr<MultitouchState>(new TrackpadTouchState())
                    : std::unique_ptr<MultitouchState>(new MultitouchState());
        
        MultitouchState* statePtr = state.get();
        MTRegisterContactFrameCallbackWithRefcon(device, contactFrameCallbackWithRefcon, statePtr);
        MTDeviceStart(device, 0);
        
        if(isTrackpad)  trackpadStates.push_back(statePtr);
        else            mousepadStates.push_back(statePtr);
        
        states.push_back(std::move(state));
    }
    
    return true;
}

static void unregisterContactFrameCallback(void) {
    std::lock_guard lock(registryMutex);

    if(!multitouchDevices) {
        return;
    }

    for(int i=0; i<CFArrayGetCount(multitouchDevices); i++) {
        MTDeviceRef device = CFArrayGetValueAtIndex(multitouchDevices, i);
        MTUnregisterContactFrameCallback(device, contactFrameCallbackWithRefcon);
        MTDeviceStop(device);
    }
    
    states.clear();
    trackpadStates.clear();
    mousepadStates.clear();
    CFRelease(multitouchDevices);
    multitouchDevices = NULL;
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

static void unregisterMultitouchDeviceAddedCallback(void) {
    if(!ioNotificationPort) {
        return;
    }

    CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(ioNotificationPort),
                          kCFRunLoopDefaultMode);
    IONotificationPortDestroy(ioNotificationPort);
    ioNotificationPort = NULL;
}

#pragma mark implementation

@implementation Multitouch

+ (Multitouch*)shared {
    static Multitouch* instance = nil;
    @synchronized(self) {
        if(!instance) {
            instance = [[self alloc] init];
        }
    }
    return instance;
}

- (instancetype)init {
    self = [super init];

    if(!registerContactFrameCallback() || !registerMultitouchDeviceAddedCallback()) {
        NSLog(@"Cannot start Multitouch Support");
        return nil;
    }

    return self;
}

- (void)dealloc {
    unregisterContactFrameCallback();
    unregisterMultitouchDeviceAddedCallback();
}

- (NSInteger)onMousepad {
    std::lock_guard lock(registryMutex);
    return std::accumulate(mousepadStates.begin(), mousepadStates.end(), 0,
                           [](int currentMax, const auto* state) {
        return std::max(currentMax, state->onSurface());
    });
}

- (NSInteger)onTrackpad {
    std::lock_guard lock(registryMutex);
    return std::accumulate(trackpadStates.begin(), trackpadStates.end(), 0,
                           [](int currentMax, const auto* state) {
        return std::max(currentMax, state->onSurface());
    });
}

- (bool)isOneAndAHalfTap {
    std::lock_guard lock(registryMutex);
    return std::any_of(states.begin(), states.end(), [](const auto& state) {
        return state->isOneAndAHalfTap();
    });
}

- (bool)isDoubleTap {
    std::lock_guard lock(registryMutex);
    return std::any_of(states.begin(), states.end(), [](const auto& state) {
        return state->isDoubleTap();
    });
}

- (void)setOnTrackpadTap:(LongSetter)callback {
    std::lock_guard lock(callbackMutex);
    onTrackpadTap = callback;
}

@end
