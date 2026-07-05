#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <netdb.h>
#import <arpa/inet.h>

static NSMutableSet *_bl = nil, *_suspects = nil;
static int _http = 0, _win = 0;
static NSString *_suspectFile = nil, *_blockedFile = nil;

static void loadBL(void) {
    _bl = [NSMutableSet set]; _suspects = [NSMutableSet set];
    for (NSString *d in @[
        @"pangolin-sdk-toutiao.com",@"pangolin-sdk-toutiao1.com",@"pangolin-sdk-toutiao-b.com",
        @"pangle.io",@"pangle-b.com",@"pglstatp-toutiao.com",@"pangolin16-drcn.dtive.com",
        @"pangolin.snssdk.com",@"pangolin-ad.toutiaoapi.com",
        @"mon.snssdk.com",@"log.snssdk.com",@"snssdk.com",@"toutiaoapi.com",
        @"gdtimg.com",@"gdt.qq.com",@"qzs.qq.com",@"qzs.gdtimg.com",
        @"ttc.gdt.qq.com",@"splash.gdtimg.com",@"wa.gdt.qq.com",
        @"doubleclick.net",@"googlesyndication.com",@"googleadservices.com",
        @"adservice.google.com",@"mobileads.google.com",@"media.admob.com",
        @"pubads.g.doubleclick.net",@"googleads.g.doubleclick.net",
        @"unityads.unity3d.com",@"config.unityads.unity3d.com",
        @"vungle.com",@"vungle.akadns.net",
        @"applovin.com",@"rt.applovin.com",@"d.applovin.com",@"ironsrc.com",
        @"ksad.com",@"api.ksad.com",@"mobads.baidu.com",@"an.facebook.com",
        @"mintegral.com",@"mobvista.com",@"rayjump.com",
        @"adcolony.com",@"sigmob.com",@"chartboost.com",@"tapjoy.com",
        @"inmobi.com",@"taboola.com",@"criteo.com",@"adnxs.com",@"mopub.com",
        @"smaato.net",@"startapp.com",@"ogury.com",@"fyber.com",
        @"crashlytics.com",@"appsflyer.com",@"adjust.com",@"singular.net",
        @"branch.io",@"kochava.com",@"moengage.com",
    ]) [_bl addObject:d];

    NSString *dir = @"/Library/Application Support/AdCleaner";
    if (![NSFileManager.defaultManager fileExistsAtPath:dir])
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    _suspectFile = [dir stringByAppendingPathComponent:@"可疑域名.txt"];
    _blockedFile = [dir stringByAppendingPathComponent:@"已拦截域名.txt"];

    // 读用户自定义黑名单
    NSString *t = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"adcleaner.txt"] encoding:NSUTF8StringEncoding error:nil];
    if (!t) t = [NSString stringWithContentsOfFile:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject] stringByAppendingPathComponent:@"adcleaner.txt"] encoding:NSUTF8StringEncoding error:nil];
    for (NSString *l in [t componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *x = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (x.length && ![x hasPrefix:@"#"]) [_bl addObject:[x lowercaseString]];
    }

    // 读已保存的可疑域名
    NSString *s = [NSString stringWithContentsOfFile:_suspectFile encoding:NSUTF8StringEncoding error:nil];
    for (NSString *l in [s componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *x = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (x.length && ![x hasPrefix:@"#"]) [_suspects addObject:x];
    }
}

static BOOL blocked(NSString *h) {
    if (!h.length) return NO;
    h = [h lowercaseString];
    for (NSString *d in _bl) if ([h isEqualToString:d] || [h hasSuffix:[@"." stringByAppendingString:d]]) return YES;
    return NO;
}

// 保存可疑域名到文件
static void saveSuspects(void) {
    NSMutableArray *a = [NSMutableArray arrayWithArray:[_suspects allObjects]];
    [a sortUsingSelector:@selector(compare:)];
    [@"# 可疑域名（可能是广告，复制到adcleaner.txt加入黑名单）\n" writeToFile:_suspectFile atomically:NO encoding:NSUTF8StringEncoding error:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:_suspectFile];
    [fh seekToEndOfFile];
    for (NSString *d in a) [fh writeData:[[NSString stringWithFormat:@"%@\n", d] dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// 保存已拦截域名
static void saveBlocked(NSString *domain) {
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:_blockedFile];
    if (!fh) { [@"" writeToFile:_blockedFile atomically:NO encoding:NSUTF8StringEncoding error:nil]; fh = [NSFileHandle fileHandleForWritingAtPath:_blockedFile]; }
    [fh seekToEndOfFile];
    [fh writeData:[[NSString stringWithFormat:@"%@\n", domain] dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// DNS层
static int (*_real_ga)(const char*,const char*,const struct addrinfo*,struct addrinfo**) = NULL;
static int _my_ga(const char *h, const char *s, const struct addrinfo *hi, struct addrinfo **r) {
    if (h && _bl && blocked([NSString stringWithUTF8String:h])) {
        saveBlocked([NSString stringWithUTF8String:h]);
        struct addrinfo *f = calloc(1,sizeof(struct addrinfo));
        if (f) { f->ai_family=AF_INET; f->ai_socktype=SOCK_STREAM; f->ai_addrlen=sizeof(struct sockaddr_in);
            f->ai_addr=calloc(1,sizeof(struct sockaddr_in));
            if (f->ai_addr) { ((struct sockaddr_in*)f->ai_addr)->sin_family=AF_INET; inet_pton(AF_INET,"127.0.0.1",&((struct sockaddr_in*)f->ai_addr)->sin_addr); }
            *r=f; } return 0;
    }
    if (!_real_ga) _real_ga = dlsym(RTLD_NEXT, "getaddrinfo");
    return _real_ga ? _real_ga(h,s,hi,r) : EAI_FAIL;
}
typedef struct{void*rep;void*orig;}ipt;
__attribute__((used,section("__DATA,__interpose")))
static const ipt _ipt[] = {{(void*)_my_ga,(void*)getaddrinfo}};

// HTTP层
static IMP _o_dt=NULL;
static id _h_dt(id s, SEL c, NSURLRequest *r, id h) {
    if (r.URL && r.URL.host) {
        if (blocked(r.URL.host)) { _http++; saveBlocked(r.URL.host); return nil; }
        // 自动发现可疑域名
        NSString *ho = [r.URL.host lowercaseString];
        NSArray *kw = @[@"ad",@"sdk",@"api",@"track",@"stat",@"analytics",@"log",@"med",@"ads",@"traffic",@"click",@"imp"];
        BOOL sus = NO;
        for (NSString *k in kw) if ([ho containsString:k]) { sus=YES; break; }
        if (sus && ![ho hasSuffix:@".com"]==NO) { if (![_suspects containsObject:ho]) { [_suspects addObject:ho]; saveSuspects(); } }
    }
    return _o_dt ? ((id(*)(id,SEL,NSURLRequest*,id))_o_dt)(s,c,r,h) : nil;
}
static IMP _o_du=NULL;
static id _h_du(id s, SEL c, NSURL *u, id h) {
    if (u && u.host && blocked(u.host)) { _http++; saveBlocked(u.host); return nil; }
    return _o_du ? ((id(*)(id,SEL,NSURL*,id))_o_du)(s,c,u,h) : nil;
}

// UI层
static IMP _o_mkv=NULL;
static void _h_mkv(id s, SEL c) {
    UIWindow *w=(UIWindow*)s; BOOL ad=NO;
    NSMutableArray *st = [NSMutableArray arrayWithObject:w];
    while (st.count&&!ad) { UIView *v=[st lastObject];[st removeLastObject];
        NSString *t=@""; if([v isKindOfClass:UILabel.class])t=[(UILabel*)v text]?:@"";
        if([v isKindOfClass:UIButton.class])t=[(UIButton*)v titleForState:UIControlStateNormal]?:@"";
        if(([t rangeOfString:@"跳过"].location!=NSNotFound&&t.length<12)||([t rangeOfString:@"广告"].location!=NSNotFound&&t.length<20))ad=YES;
        [st addObjectsFromArray:v.subviews]; }
    if(ad){w.hidden=YES;_win++;return;}
    if(_o_mkv)((void(*)(id,SEL))_o_mkv)(s,c);
}

static void sw(Class cls, SEL sel, IMP imp, IMP *store) {
    Method m=class_getInstanceMethod(cls,sel);
    if(m){if(store)*store=method_getImplementation(m);method_setImplementation(m,imp);}
}

static void toast(NSString *s) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        UIWindow *kw=nil;
        if(@available(iOS 13.0,*))for(UIScene *sc in UIApplication.sharedApplication.connectedScenes)
            if([sc isKindOfClass:UIWindowScene.class])for(UIWindow *w in [(UIWindowScene*)sc windows])
                if(!w.hidden&&w.alpha>0){kw=w;break;}
        if(!kw)kw=UIApplication.sharedApplication.keyWindow;if(!kw)return;
        UILabel *lb=[[UILabel alloc]initWithFrame:CGRectMake(0,100,kw.bounds.size.width,44)];
        lb.text=s;lb.textColor=UIColor.greenColor;lb.numberOfLines=2;
        lb.textAlignment=NSTextAlignmentCenter;lb.font=[UIFont boldSystemFontOfSize:12];
        lb.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.85];[kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[lb removeFromSuperview];});
    });
}
static void updToast(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        toast([NSString stringWithFormat:@"AdCleaner | 拦%d次 | 疑%lu条 | %lu域名",
               _http+_win,(unsigned long)_suspects.count,(unsigned long)_bl.count]);
        updToast();
    });
}

__attribute__((constructor))
static void init(void) {
    _real_ga = dlsym(RTLD_NEXT,"getaddrinfo");
    loadBL();
    sw(NSURLSession.class,@selector(dataTaskWithRequest:completionHandler:),(IMP)_h_dt,&_o_dt);
    sw(NSURLSession.class,@selector(dataTaskWithURL:completionHandler:),(IMP)_h_du,&_o_du);
    sw(UIWindow.class,@selector(makeKeyAndVisible),(IMP)_h_mkv,&_o_mkv);
    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [@"v11" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    toast([NSString stringWithFormat:@"AdCleaner已激活\n日志:/Library/Application Support/AdCleaner/"]);
    updToast();
}
