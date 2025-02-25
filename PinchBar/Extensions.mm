#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

@implementation NSApplication (activateAndRunModalForWindow)

+ (void) load {
    auto original = class_getInstanceMethod(self.class, @selector(runModalForWindow:));
    auto swizzled = class_getInstanceMethod(self.class, @selector(activateAndRunModalForWindow:));
    method_exchangeImplementations(original, swizzled);
    
    original = class_getInstanceMethod(self.class, @selector(presentError:));
    swizzled = class_getInstanceMethod(self.class, @selector(replacedPresentError:));
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

- (BOOL)replacedPresentError:(NSError *)error {
    auto alert = [NSAlert alertWithError:error];
    NSString* informativeText = error.userInfo[NSDebugDescriptionErrorKey];
    
    if(NSArray* codingPath = error.userInfo[@"NSCodingPath"]) {
//        informativeText = [informativeText stringByAppendingFormat:@"\nin"];
//        for(id codingKey in codingPath) {
//            informativeText = [informativeText stringByAppendingFormat:@"\n%@",
//                               [codingKey performSelector:@selector(description)]];
//        }
        
        informativeText = [informativeText stringByAppendingFormat:@"\nin\n%@",
                           codingPath];
    }
    
    alert.informativeText = informativeText;
    [alert runModal];
    return NO;
}

@end
