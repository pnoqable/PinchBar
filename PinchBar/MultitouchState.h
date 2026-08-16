#pragma once

#import <array>
#import <map>
#import <mutex>
#import <vector>

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

typedef const MTTouch* MTTouchRef;

class MultitouchState {
public:
    MultitouchState();
    virtual ~MultitouchState();

    void contactFrame(MTTouchRef touches, int newTouchCount, double time);
    int onSurface() const;
    bool isOneAndAHalfTap() const;
    bool isDoubleTap() const;

protected:
    virtual void tapFinished(int touchCount);

private:
    mutable std::recursive_mutex stateMutex;
    int touchCount = 0;
    std::map<int, std::array<float, 2>> touchStartPositions;
    double lastTouchTime = 0;
    std::vector<int> lastTouchCounts;
};
