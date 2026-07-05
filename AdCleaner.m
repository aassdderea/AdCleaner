#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static int _skipped = 0, _closed = 0;

// === 获取指定view的window ===
static UIWindow *windowForView(UIView *v) {
    return v.window;
}

// === 查找跳过按钮（只在刚出现的window内） ===
static UIView *findSkipInWindow(UIWindow *win) {
    if (!win || win.hidden || win.alpha < 0.01) return nil;

    NSMutableArray *stack = [NSMutableArray arrayWithObject:win];
    while (stack.count > 0) {
        UIView *v = [stack lastObject]; [stack removeLastObject];
        if (v.hidden || v.alpha < 0.01) continue;

        NSString *t = @"";
        if ([v isKindOfClass:[UIButton class]])
            t = [(UIButton *)v titleForState:UIControlStateNormal] ?: @"";
        else if ([v isKindOfClass:[UILabel class]])
            t = [(UILabel *)v text] ?: @"";

        // 找到"跳过"
        if ([t rangeOfString:@"跳过"].location != NSNotFound && t.length < 10) {
            // 如果当前是UILabel，上溯父视图找可点击的
            if ([v isKindOfClass:[UILabel class]]) {
                UIView *p = v.superview;
                while (p) {
                    if ([p isKindOfClass:[UIControl class]]) return p;
                    p = p.superview;
                }
            }
            return v;
        }

        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// === 查找关闭按钮 ===
static UIView *findCloseInWindow(UIWindow *win) {
    if (!win || win.hidden || win.alpha < 0.01) return nil;

    NSMutableArray *stack = [NSMutableArray arrayWithObject:win];
    while (stack.count > 0) {
        UIView *v = [stack lastObject]; [stack removeLastObject];
        if (v.hidden || v.alpha < 0.01) continue;

        NSString *t = @"";
        if ([v isKindOfClass:[UIButton class]])
            t = [(UIButton *)v titleForState:UIControlStateNormal] ?: @"";
        else if ([v isKindOfClass:[UILabel class]])
            t = [(UILabel *)v text] ?: @"";
        if (v.accessibilityLabel) t = [t stringByAppendingString:v.accessibilityLabel];

        if ([t isEqualToString:@"×"] || [t isEqualToString:@"✕"] ||
            [t rangeOfString:@"关闭"].location != NSNotFound ||
            [t rangeOfString:@"Close"].location != NSNotFound) {
            return v;
        }

        // 右上角小按钮（可能是图片关闭按钮）
        if ([v isKindOfClass:[UIButton class]] && t.length == 0 &&
            v.frame.size.width < 50 && v.frame.size.height < 50 &&
            v.superview && v.frame.origin.x > v.superview.bounds.size.width * 0.7) {
            return v;
        }

        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// === 真实模拟点击 ===
static void realTap(UIView *v) {
    if (!v) return;

    // 1. sendActionsForControlEvents
    if ([v isKindOfClass:[UIControl class]]) {
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }

    // 2. 上溯到父UIControl
    UIView *p = v.superview;
    while (p) {
        if ([p isKindOfClass:[UIControl class]]) {
            [(UIControl *)p sendActionsForControlEvents:UIControlEventTouchUpInside];
            return;
        }
        p = p.superview;
    }

    // 3. 通过手势触发
    for (UIGestureRecognizer *g in v.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
            [g setState:UIGestureRecognizerStateBegan];
            [g setState:UIGestureRecognizerStateEnded];
            [g performSelector:NSSelectorFromString(@"ignoreTouch:forEvent:") withObject:nil withObject:nil];
        }
    }

    // 4. accessibility
    if (v.isAccessibilityElement && [v respondsToSelector:@selector(accessibilityActivate)]) {
        [v performSelector:@selector(accessibilityActivate)];
    }
}

// === 只在指定window内扫描 ===
static void scanWindow(UIWindow *w) {
    UIView *skip = findSkipInWindow(w);
    if (skip) { realTap(skip); _skipped++; return; }

    UIView *close = findCloseInWindow(w);
    if (close) { realTap(close); _closed++; return; }
}

// === Hook: makeKeyAndVisible — 新窗口出现时在自己的层级内扫描 ===
static IMP _o_makeKV = NULL;
static void _h_makeKV(id s, SEL c) {
    if (_o_makeKV) ((void(*)(id,SEL))_o_makeKV)(s, c);
    UIWindow *w = (UIWindow *)s;
    for (int i = 0; i < 12; i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ scanWindow(w); });
}

// === Hook: viewDidAppear — 在刚出现的VC内扫描 ===
static IMP _o_vda = NULL;
static void _h_vda(id s, SEL c, BOOL a) {
    if (_o_vda) ((void(*)(id,SEL,BOOL))_o_vda)(s, c, a);
    UIViewController *vc = (UIViewController *)s;
    if (vc.view.window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *skip = findSkipInWindow(vc.view.window);
            if (skip) { realTap(skip); _skipped++; }
        });
    }
}

static void swizzle(Class cls, SEL sel, IMP imp, IMP *store) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (store) *store = method_getImplementation(m);
    method_setImplementation(m, imp);
}

// === Toast ===
static void show(NSString *s) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
                if ([sc isKindOfClass:[UIWindowScene class]])
                    for (UIWindow *w in [(UIWindowScene *)sc windows])
                        if (!w.hidden && w.alpha > 0) { kw = w; break; }
                if (kw) break;
            }
        }
        if (!kw) kw = [UIApplication sharedApplication].keyWindow;
        if (!kw) return;
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, kw.bounds.size.width, 44)];
        lb.text = s; lb.textColor = [UIColor greenColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:15];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        [kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}

static void updToast(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        show([NSString stringWithFormat:@"AdCleaner v6 | 跳过%d 关闭%d", _skipped, _closed]);
        updToast();
    });
}

__attribute__((constructor))
static void init(void) {
    swizzle([UIWindow class], @selector(makeKeyAndVisible), (IMP)_h_makeKV, &_o_makeKV);
    swizzle([UIViewController class], @selector(viewDidAppear:), (IMP)_h_vda, &_o_vda);

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [@"v6" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    show(@"AdCleaner v6 已激活");
    updToast();
}
