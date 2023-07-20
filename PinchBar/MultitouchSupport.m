#import "MultitouchSupport.h"

#pragma mark linked symbols

typedef const void* MTDeviceRef;
typedef const void* MTTouchRef;

typedef void (*MTContactCallbackFunction)(MTDeviceRef, MTTouchRef, int, double, int);

CFArrayRef MTDeviceCreateList(void);

void MTDeviceGetSensorDimensions(MTDeviceRef, int*, int*);

void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);

void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);

#pragma mark static variables

static IONotificationPortRef ioNotificationPort = NULL;

static CFArrayRef multitouchDevices = NULL;

static int sensorCols = 0;
static int sensorRows = 0;
static int touchCount = 0;

#pragma mark private functions

static void contactFrameCallback(MTDeviceRef device, MTTouchRef touches, int touchesCount, double time, int frame) {
    MTDeviceGetSensorDimensions(device, &sensorRows, &sensorCols);
    touchCount = touchesCount;
}

static bool registerContactFrameCallback() {
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

static bool registerMultitouchDeviceAddedCallback() {
    if(ioNotificationPort) {
        return true;
    }
    
    ioNotificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(ioNotificationPort), kCFRunLoopDefaultMode);
    
    io_iterator_t iterator;
    kern_return_t error = IOServiceAddMatchingNotification(ioNotificationPort, kIOFirstMatchNotification,
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

bool MultitouchSupportStart() {
    return registerContactFrameCallback() && registerMultitouchDeviceAddedCallback();
}

bool MultitouchSupportIsTouchCount(int trackpad, int mouse) {
    return sensorCols > sensorRows ? trackpad == touchCount : mouse == touchCount;
}
