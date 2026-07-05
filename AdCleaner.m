#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static int _blocked = 0;

// === 广告类名前缀（更精确） ===
static BOOL isAdClass(NSString *cn) {
    static NSArray *pfx = nil;
    if (!pfx) pfx = @[
        // 穿山甲 Pangle
        @"BUSplashAdView", @"BUNativeExpress", @"BUFullscreen",
        @"BURewarded", @"BUAd",
        // 优量汇 GDT
        @"GDTSplashAd", @"GDTUnifiedBanner", @"GDTUnifiedInterstitial",
        @"GDTUnifiedNative", @"GDTUnifiedRewardAd",
        // AdMob
        @"GADBannerView", @"GADNativeAd", @"GADInterstitial",
        @"GADRewarded", @"GADNativeExpress",
        // 快手
        @"KSAdSplash", @"KSNativeAd", @"KSReward",
        // 其他
        @"UnityAds", @"VungleAd", @"FBAdView",
        @"SigmobSplash", @"MTGReward", @"AdColony"
    ];
    for (NSString *p in pfx) {
        if ([cn hasPrefix:p] || [cn rangeOfString:p].location != NSNotFound) return YES;
    }
    return NO;
}

// === Hook: addSubview ===
static IMP _orig_addSubview = NULL;
static void _h_addSubview(id s, SEL c, UIView *v) {
    if (isAdClass(NSStringFromClass([v class]))) { _blocked++; return; }
    if (_orig_addSubview) ((void(*)(id,SEL,UIView*))_orig_addSubview)(s,c,v);
}

// === Hook: insertSubview:atIndex: ===
static IMP _orig_insertAtIndex = NULL;
static void _h_insertAtIndex(id s, SEL c, UIView *v, NSInteger i) {
    if (isAdClass(NSStringFromClass([v class]))) { _blocked++; return; }
    if (_orig_insertAtIndex) ((void(*)(id,SEL,UIView*,NSInteger))_orig_insertAtIndex)(s,c,v,i);
}

// === Hook: insertSubview:aboveSubview: ===
static IMP _orig_insertAbove = NULL;
static void _h_insertAbove(id s, SEL c, UIView *v, UIView *sv) {
    if (isAdClass(NSStringFromClass([v class]))) { _blocked++; return; }
    if (_orig_insertAbove) ((void(*)(id,SEL,UIView*,UIView*))_orig_insertAbove)(s,c,v,sv);
}

// === Hook: UIWindow.makeKeyAndVisible ===
static IMP _orig_makeKeyAndVisible = NULL;
static void _h_makeKeyAndVisible(id s, SEL c) {
    // 检查是否是广告窗口
    UIWindow *w = (UIWindow *)s;
    id rvc = w.rootViewController;
    NSString *vcName = rvc ? NSStringFromClass([rvc class]) : @"";
    if (isAdClass(vcName)) {
        _blocked++;
        w.hidden = YES;
        return;
    }
    if (_orig_makeKeyAndVisible) ((void(*)(id,SEL))_orig_makeKeyAndVisible)(s,c);
}

// === Hook: presentViewController ===
static IMP _orig_presentVC = NULL;
static void _h_presentVC(id s, SEL c, UIViewController *vc, BOOL anim, id cb) {
    if (isAdClass(NSStringFromClass([vc class]))) { _blocked++; return; }
    if (_orig_presentVC) ((void(*)(id,SEL,UIViewController*,BOOL,id))_orig_presentVC)(s,c,vc,anim,cb);
}

// === Swizzle 工具 ===
static void swizzle(Class cls, SEL sel, IMP newImp, IMP *store) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (store) *store = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

// === Toast ===
static void showToast(const char *ver, int blocked) {
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
        lb.text = [NSString stringWithFormat:@"AdCleaner %s | %d条拦截", ver, blocked];
        lb.textColor = [UIColor greenColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:16];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        [kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}

__attribute__((constructor))
static void init(void) {
    swizzle([UIView class], @selector(addSubview:), (IMP)_h_addSubview, &_orig_addSubview);
    swizzle([UIView class], @selector(insertSubview:atIndex:), (IMP)_h_insertAtIndex, &_orig_insertAtIndex);
    swizzle([UIView class], @selector(insertSubview:aboveSubview:), (IMP)_h_insertAbove, &_orig_insertAbove);
    swizzle([UIWindow class], @selector(makeKeyAndVisible), (IMP)_h_makeKeyAndVisible, &_orig_makeKeyAndVisible);
    swizzle([UIViewController class], NSSelectorFromString(@"presentViewController:animated:completion:"),
            (IMP)_h_presentVC, &_orig_presentVC);

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [@"v3 OK" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];

    showToast("v3", _blocked);

    // 定时更新Toast显示拦截计数
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        showToast("v3", _blocked);
    });
}
