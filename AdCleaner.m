#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void init(void) {
    NSLog(@"[AdCleaner] 加载成功");

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [@"OK" writeToFile:[docs stringByAppendingPathComponent:@"adcleaner.log"]
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
        lb.text = @"AdCleaner 已激活";
        lb.textColor = [UIColor greenColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:20];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        [kw addSubview:lb];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}
