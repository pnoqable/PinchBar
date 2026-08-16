#import "MultitouchState.h"

#import <Cocoa/Cocoa.h>

#import <cmath>

MultitouchState::MultitouchState() = default;

MultitouchState::~MultitouchState() = default;

void MultitouchState::contactFrame(MTTouchRef touches, int newTouchCount, double time) {
    std::lock_guard lock(stateMutex);
    if(touchCount == 0 && newTouchCount > 0) {
        if(time - lastTouchTime > NSEvent.doubleClickInterval) {
            lastTouchCounts.clear();
        }

        lastTouchTime = time;
    }

    if(newTouchCount > touchCount && touchStartPositions.size() > touchCount) {
        touchStartPositions.clear();
    }

    touchCount = newTouchCount;

    if(lastTouchTime != 0) {
        for(const MTTouch* t = touches; t < touches + newTouchCount; t++) {
            auto p = touchStartPositions.emplace(t->fid, std::to_array(t->mm)).first->second;
            if(std::fmax(std::fabs(p[0] - t->mm[0]), std::fabs(p[1] - t->mm[1])) > 2) {
                lastTouchTime = 0;
            }
        }
    }

    if(newTouchCount == 0) {
        if(time - lastTouchTime < NSEvent.doubleClickInterval) {
            int tapTouchCount = (int)touchStartPositions.size();
            lastTouchCounts.push_back(tapTouchCount);
            tapFinished(tapTouchCount);
        } else {
            lastTouchCounts.clear();
        }
    }
}

int MultitouchState::onSurface() const {
    std::lock_guard lock(stateMutex);
    return touchCount;
}

bool MultitouchState::isOneAndAHalfTap() const {
    std::lock_guard lock(stateMutex);
    return touchCount && lastTouchCounts.size() == 1 && lastTouchCounts.back() < touchCount;
}

bool MultitouchState::isDoubleTap() const {
    std::lock_guard lock(stateMutex);
    return touchCount && lastTouchCounts == std::vector{touchCount};
}

void MultitouchState::tapFinished(int touchCount) {}
