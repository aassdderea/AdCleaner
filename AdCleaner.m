#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSMutableSet *_bl = nil, *_suspects = nil;
static int _http = 0, _win = 0;

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
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *t = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"adcleaner.txt"] encoding:NSUTF8StringEncoding error:nil];
    if (!t) t = [NSString stringWithContentsOfFile:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject] stringByAppendingPathComponent:@"adcleaner.txt"] encoding:NSUTF8StringEncoding error:nil];
    for (NSString *l in [t componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *x = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (x.length && ![x hasPrefix:@"#"]) [_bl addObject:[x lowercaseString]];
    }
}

static BOOL blocked(NSString *h) {
    if (!h.length) return NO; h = [h lowercaseString];
    for (NSString *d in _bl) if ([h isEqualToString:d] || [h hasSuffix:[@"." stringByAppendingString:d]]) return YES;
    return NO;
}

static IMP _o_dt=NULL;
static id _h_dt(id s, SEL c, NSURLRequest *r, id h) {
    if (r.URL && r.URL.host && blocked(r.URL.host)) { _http++; return nil; }
    return _o_dt ? ((id(*)(id,SEL,NSURLRequest*,id))_o_dt)(s,c,r,h) : nil;
}
static IMP _o_du=NULL;
static id _h_du(id s, SEL c, NSURL *u, id h) {
    if (u && u.host && blocked(u.host)) { _http++; return nil; }
    return _o_du ? ((id(*)(id,SEL,NSURL*,id))_o_du)(s,c,u,h) : nil;
}

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
    @try {
        Method m=class_getInstanceMethod(cls,sel);
        if(m){if(store)*store=method_getImplementation(m);method_setImplementation(m,imp);}
    } @catch (NSException *e) {}
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
        toast([NSString stringWithFormat:@"AdCleaner | 拦%d次 | %lu域名",_http+_win,(unsigned long)_bl.count]);
        updToast();
    });
}

__attribute__((constructor))
static void init(void) {
    @try {
        loadBL();
        sw(NSURLSession.class,@selector(dataTaskWithRequest:completionHandler:),(IMP)_h_dt,&_o_dt);
        sw(NSURLSession.class,@selector(dataTaskWithURL:completionHandler:),(IMP)_h_du,&_o_du);
        sw(UIWindow.class,@selector(makeKeyAndVisible),(IMP)_h_mkv,&_o_mkv);
        NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        [@"v12" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        toast(@"AdCleaner已激活");
        updToast();
    } @catch (NSException *e) {}
}
