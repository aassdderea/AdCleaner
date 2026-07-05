#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static int _skipped = 0;
static int _blocked = 0;

// === 在视图层级中查找包含指定文本的按钮 ===
static UIView *findSkipButton(UIView *root) {
    if (!root || root.hidden || root.alpha < 0.01) return nil;

    NSString *text = @"";
    if ([root isKindOfClass:[UIButton class]]) {
        text = [(UIButton *)root titleForState:UIControlStateNormal] ?: @"";
    } else if ([root isKindOfClass:[UILabel class]]) {
        text = [(UILabel *)root text] ?: @"";
    }
    if ([text rangeOfString:@"跳过"].location != NSNotFound ||
        [text rangeOfString:@"Skip"].location != NSNotFound) {
        return root;
    }

    for (UIView *sub in root.subviews) {
        UIView *found = findSkipButton(sub);
        if (found) return found;
    }
    return nil;
}

// === 查找关闭/×按钮 ===
static UIView *findCloseButton(UIView *root) {
    if (!root || root.hidden || root.alpha < 0.01) return nil;

    NSString *text = @"";
    if ([root isKindOfClass:[UIButton class]]) {
        text = [(UIButton *)root titleForState:UIControlStateNormal] ?: @"";
    } else if ([root isKindOfClass:[UILabel class]]) {
        text = [(UILabel *)root text] ?: @"";
    }
    if ([text isEqualToString:@"×"] ||
        [text isEqualToString:@"✕"] ||
        [text isEqualToString:@"关闭"] ||
        [text rangeOfString:@"关闭"].location != NSNotFound ||
        [text rangeOfString:@"Close"].location != NSNotFound) {
        return root;
    }

    for (UIView *sub in root.subviews) {
        UIView *found = findCloseButton(sub);
        if (found) return found;
    }
    return nil;
}

// === 模拟点击 ===
static void tapView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UIControl class]]) {
        [(UIControl *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    // 也尝试触发手势
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            // 手动设置状态触发
            [gr touchesBegan:[NSSet set] withEvent:nil];
            [gr touchesEnded:[NSSet set] withEvent:nil];
        }
    }
    // 如果按钮在父视图中，也点父视图
    if (view.superview && [view.superview isKindOfClass:[UIControl class]]) {
        [(UIControl *)view.superview sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

// === 扫描所有窗口找跳过按钮 ===
static void scanAllWindows(void) {
    NSArray *windows = nil;
    if (@available(iOS 13.0, *)) {
        NSMutableArray *ws = [NSMutableArray array];
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                [ws addObjectsFromArray:[(UIWindowScene *)s windows]];
            }
        }
        windows = ws;
    } else {
        windows = [UIApplication sharedApplication].windows;
    }

    for (UIWindow *w in windows) {
        if (w.hidden || w.alpha < 0.01) continue;

        // 先找"跳过"
        UIView *skipBtn = findSkipButton(w);
        if (skipBtn) {
            tapView(skipBtn);
            _skipped++;
            return; // 一次只点一个
        }

        // 再找"关闭/×"
        UIView *closeBtn = findCloseButton(w);
        if (closeBtn) {
            tapView(closeBtn);
            _blocked++;
            return;
        }
    }
}

// === Hook: UIWindow.makeKeyAndVisible（开屏广告出现时密集扫描） ===
static IMP _orig_makeKV = NULL;
static void _h_makeKV(id s, SEL c) {
    if (_orig_makeKV) ((void(*)(id,SEL))_orig_makeKV)(s, c);

    // 新窗口出现，密集扫描找跳过按钮
    for (int i = 0; i < 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ scanAllWindows(); });
    }
}

// === Hook: UIViewController.viewDidAppear（广告VC出现时扫描） ===
static IMP _orig_viewDidAppear = NULL;
static void _h_viewDidAppear(id s, SEL c, BOOL anim) {
    if (_orig_viewDidAppear) ((void(*)(id,SEL,BOOL))_orig_viewDidAppear)(s,c,anim);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ scanAllWindows(); });
}

static void swizzle(Class cls, SEL sel, IMP newImp, IMP *store) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (store) *store = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

// === Toast ===
static void showToast(const char *ver) {
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
        lb.text = [NSString stringWithFormat:@"AdCleaner %s | 跳过%d 关闭%d", ver, _skipped, _blocked];
        lb.textColor = [UIColor greenColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:15];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        [kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}

__attribute__((constructor))
static void init(void) {
    // Hook window出现 + VC出现 → 扫描跳过按钮
    swizzle([UIWindow class], @selector(makeKeyAndVisible), (IMP)_h_makeKV, &_orig_makeKV);
    swizzle([UIViewController class], @selector(viewDidAppear:), (IMP)_h_viewDidAppear, &_orig_viewDidAppear);

    // 定时扫描（兜底）
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { scanAllWindows(); }];

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [@"v4 OK" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];

    showToast("v4");
}
