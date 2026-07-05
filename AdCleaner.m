#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP _orig_addSubview = NULL;
static int _blockedCount = 0;

static void _hook_addSubview(id self, SEL _cmd, UIView *view) {
    NSString *cn = NSStringFromClass([view class]);
    NSArray *keywords = @[
        @"BUSplash", @"BUNativeExpress", @"BURewarded", @"BUFullscreen",
        @"GDTSplash", @"GDTUnifiedNative", @"GDTUnifiedInterstitial",
        @"GADBanner", @"GADNative", @"GADInterstitial", @"GADRewarded",
        @"KSAdSplash", @"KSNative", @"KSReward",
        @"UnityAds", @"VungleAd", @"AdColonyAd", @"ALSdk",
        @"FBAdView", @"FBInterstitial", @"SigmobSplash",
        @"MTGReward", @"MTGNative", @"IronSource"
    ];
    BOOL isAd = NO;
    for (NSString *kw in keywords) {
        if ([cn rangeOfString:kw].location != NSNotFound) { isAd = YES; break; }
    }
    if (isAd) { _blockedCount++; return; }

    if (_orig_addSubview) {
        ((void(*)(id, SEL, UIView *))_orig_addSubview)(self, _cmd, view);
    }
}

__attribute__((constructor))
static void init(void) {
    Method m = class_getInstanceMethod([UIView class], @selector(addSubview:));
    if (m) {
        _orig_addSubview = method_getImplementation(m);
        method_setImplementation(m, (IMP)_hook_addSubview);
    }

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [@"v2 OK" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in [(UIWindowScene *)s windows]) {
                        if (!w.hidden && w.alpha > 0) { kw = w; break; }
                    }
                }
                if (kw) break;
            }
        }
        if (!kw) kw = [UIApplication sharedApplication].keyWindow;
        if (!kw) return;

        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, kw.bounds.size.width, 50)];
        lb.text = @"AdCleaner v2 已激活";
        lb.textColor = [UIColor greenColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:20];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        [kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}
