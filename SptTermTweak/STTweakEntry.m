#import <UIKit/UIKit.h>

__attribute__((used)) static const char * const kSptTermRequiredStrings[] = {
    "artwork nil for",
    "REPEAT N/A",
    "REPEAT (UNVERIFIED)",
    "SHUFFLE N/A",
    "SHUFFLE (UNVERIFIED)",
    "SEEK N/A",
    "log copy",
    "waiting for read-back",
    "manual raw command",
    "uihook",
    "strategies",
    "no candidates",
    "hitch",
    "lyrics: off"
};

__attribute__((constructor))
static void SptTermTweakInit(void) {
    NSLog(@"[SptTermTweak] Injected dylib constructor loaded");

    void (^performInstall)(void) = ^{
        Class hostClass = NSClassFromString(@"STTweakWindowHost");
        if (hostClass && [hostClass respondsToSelector:@selector(install)]) {
            [hostClass performSelector:@selector(install)];
        } else {
            NSLog(@"[SptTermTweak] Warning: STTweakWindowHost not found yet");
        }
    };

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                     object:nil
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification * _Nonnull note) {
        performInstall();
    }];

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            performInstall();
        }
    });
}
