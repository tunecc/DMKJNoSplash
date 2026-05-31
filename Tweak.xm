#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface NSObject (DMKJNoSplashSelectors)
- (void)countDownClick;
- (void)setTimeout:(long long)timeout;
@end

static void DMKJSendVoid(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return;
    }

    ((void (*)(id, SEL))objc_msgSend)(target, selector);
}

static void DMKJSendInteger(id target, SEL selector, long long value) {
    if (!target || ![target respondsToSelector:selector]) {
        return;
    }

    ((void (*)(id, SEL, long long))objc_msgSend)(target, selector, value);
}

static void DMKJSkipBusinessSplash(id target) {
    if (!target) {
        return;
    }

    void (^skip)(void) = ^{
        DMKJSendInteger(target, @selector(setTimeout:), -1);
        DMKJSendVoid(target, @selector(countDownClick));
    };

    if ([NSThread isMainThread]) {
        skip();
    } else {
        dispatch_async(dispatch_get_main_queue(), skip);
    }
}

%hook DMKJCoopenAdvertVC

- (void)viewDidLoad {
    %orig;
}

- (void)createUI {
    %orig;
}

- (void)createJumpView {
    %orig;
}

- (void)showAdImg:(id)arg1 {
    DMKJSkipBusinessSplash(self);
}

- (void)showAdVideo:(id)arg1 {
    DMKJSkipBusinessSplash(self);
}

- (void)playNetVideo {
    DMKJSkipBusinessSplash(self);
}

- (void)downloadVideo {
    DMKJSkipBusinessSplash(self);
}

- (void)playLocalVideo:(id)arg1 {
    DMKJSkipBusinessSplash(self);
}

- (void)startTimer {
    DMKJSkipBusinessSplash(self);
}

- (void)starCountdown {
    DMKJSkipBusinessSplash(self);
}

- (void)netRequestCallBackDidSuccess:(id)arg1 ClassName:(id)arg2 {
    %orig;
}

- (void)netRequestCallBackDidFailed:(id)arg1 ClassName:(id)arg2 {
    %orig;
}

%end
