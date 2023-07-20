#import <Foundation/Foundation.h>

bool MultitouchSupportStart(void);

bool MultitouchSupportIsTrackpad(void);

int MultitouchSupportGetTouchCount(void);

bool MultitouchSupportIsTouchCount(int trackPad, int mouse);
