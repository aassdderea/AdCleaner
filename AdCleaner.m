#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSMutableSet *_blacklist = nil;
static int _dnsBlocked = 0, _httpBlocked = 0;

// === 加载域名黑名单 ===
static void loadBlacklist(void) {
    _blacklist = [NSMutableSet set];

    // 内置 100+ 主流广告域名
    NSArray *builtin = @[
        // 穿山甲 Pangle
        @"pangolin-sdk-toutiao.com", @"pglstatp-toutiao.com",
        @"pangle.io", @"snssdk.com", @"bytedance.com",
        // 优量汇 GDT
        @"gdtimg.com", @"gdt.qq.com", @"qzs.qq.com",
        // AdMob
        @"doubleclick.net", @"googlesyndication.com",
        @"googleadservices.com", @"adservice.google.com",
        // Unity / Vungle
        @"unityads.unity3d.com", @"vungle.com",
        // AppLovin / IronSource
        @"applovin.com", @"ironsrc.com", @"supersonicads.com",
        // 快手 / 百度
        @"ksad.com", @"mobads.baidu.com",
        // 其他
        @"mintegral.com", @"mobvista.com", @"adcolony.com",
        @"sigmob.com", @"chartboost.com", @"tapjoy.com",
        @"inmobi.com", @"fyber.com", @"inner-active.mobi",
        @"taboola.com", @"criteo.com", @"adnxs.com",
        @"mopub.com", @"facebook.com", @"fbcdn.net",
        @"adjust.com", @"appsflyer.com", @"branch.io",
        @"kochava.com", @"singular.net", @"appboy.com",
        @"batch.com", @"localytics.com", @"flurry.com",
        @"crashlytics.com", @"moengage.com",
        // CDN 分发
        @"cloudfront.net", @"edgesuite.net",
    ];

    for (NSString *d in builtin) {
        [_blacklist addObject:[d lowercaseString]];
    }

    // 外部自定义文件
    NSString *ext = @"/Library/Application Support/AdCleaner/adcleaner.txt";
    NSString *txt = [NSString stringWithContentsOfFile:ext encoding:NSUTF8StringEncoding error:nil];
    if (!txt) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        txt = [NSString stringWithContentsOfFile:[docs stringByAppendingPathComponent:@"adcleaner.txt"] encoding:NSUTF8StringEncoding error:nil];
    }
    if (txt) {
        for (NSString *line in [txt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length > 0 && ![t hasPrefix:@"#"]) [_blacklist addObject:[t lowercaseString]];
        }
    }
}

static BOOL isBlocked(NSString *host) {
    if (!host || host.length == 0) return NO;
    host = [host lowercaseString];
    if ([_blacklist containsObject:host]) return YES;
    // 通配: 检查是否是某个域名的子域名
    for (NSString *d in _blacklist) {
        if ([host hasSuffix:d] || [host hasSuffix:[@"." stringByAppendingString:d]]) return YES;
    }
    return NO;
}

// === Hook: NSURLSession dataTaskWithRequest: ===
static IMP _o_dataTask = NULL;
static id _h_dataTask(id self, SEL cmd, NSURLRequest *req, id handler) {
    if (req.URL && isBlocked(req.URL.host)) {
        _httpBlocked++;
        // 返回一个已取消的任务，阻止广告请求
        if (handler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorCancelled userInfo:nil];
            ((void(^)(NSData*,NSURLResponse*,NSError*))handler)(nil, nil, err);
        }
        return nil;
    }
    if (_o_dataTask)
        return ((id(*)(id,SEL,NSURLRequest*,id))_o_dataTask)(self, cmd, req, handler);
    return nil;
}

// === Hook: dataTaskWithURL: （简写版本） ===
static IMP _o_dataTaskURL = NULL;
static id _h_dataTaskURL(id self, SEL cmd, NSURL *url, id handler) {
    if (url && isBlocked(url.host)) { _httpBlocked++; return nil; }
    if (_o_dataTaskURL)
        return ((id(*)(id,SEL,NSURL*,id))_o_dataTaskURL)(self, cmd, url, handler);
    return nil;
}

// === Hook: makeKeyAndVisible（隐藏开屏广告窗口兜底） ===
static IMP _o_mkv = NULL;
static void _h_mkv(id self, SEL cmd) {
    UIWindow *w = (UIWindow *)self;
    // 检查是否是广告窗口：扫描是否有"跳过"文字
    BOOL isAd = NO;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    while (stack.count > 0 && !isAd) {
        UIView *v = [stack lastObject]; [stack removeLastObject];
        NSString *t = @"";
        if ([v isKindOfClass:[UILabel class]]) t = [(UILabel *)v text] ?: @"";
        if ([v isKindOfClass:[UIButton class]]) t = [(UIButton *)v titleForState:UIControlStateNormal] ?: @"";
        if ([t rangeOfString:@"跳过"].location != NSNotFound && t.length < 10) { isAd = YES; break; }
        [stack addObjectsFromArray:v.subviews];
    }
    if (isAd) { w.hidden = YES; return; }
    if (_o_mkv) ((void(*)(id,SEL))_o_mkv)(self, cmd);
}

static void swizzle(Class cls, SEL sel, IMP imp, IMP *store) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (store) *store = method_getImplementation(m);
    method_setImplementation(m, imp);
}

// === Toast ===
static void toast(NSString *s) {
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
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, kw.bounds.size.width, 40)];
        lb.text = s; lb.textColor = [UIColor greenColor]; lb.numberOfLines = 2;
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:14];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        [kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}

static void updToast(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        toast([NSString stringWithFormat:@"AdCleaner | HTTP拦截%d | %lu域名", _httpBlocked, (unsigned long)_blacklist.count]);
        updToast();
    });
}

__attribute__((constructor))
static void init(void) {
    loadBlacklist();
    swizzle([NSURLSession class], @selector(dataTaskWithRequest:completionHandler:), (IMP)_h_dataTask, &_o_dataTask);
    swizzle([NSURLSession class], @selector(dataTaskWithURL:completionHandler:), (IMP)_h_dataTaskURL, &_o_dataTaskURL);
    swizzle([UIWindow class], @selector(makeKeyAndVisible), (IMP)_h_mkv, &_o_mkv);

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [@"v8" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    toast(@"AdCleaner已激活");
    updToast();
}
