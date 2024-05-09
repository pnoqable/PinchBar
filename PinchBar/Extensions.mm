#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

@implementation NSApplication (activateAndRunModalForWindow)

+ (void) load {
    auto original = class_getInstanceMethod(self.class, @selector(runModalForWindow:));
    auto swizzled = class_getInstanceMethod(self.class, @selector(activateAndRunModalForWindow:));
    method_exchangeImplementations(original, swizzled);
}

- (NSModalResponse)activateAndRunModalForWindow:(NSWindow*)window {
    auto formerActivationPolicy = self.activationPolicy;
    
    [self activateIgnoringOtherApps: true];
    [self setActivationPolicy: NSApplicationActivationPolicyRegular];
    
    auto result = [self activateAndRunModalForWindow: window];
    
    [self setActivationPolicy: formerActivationPolicy];
    
    return result;
}

@end
