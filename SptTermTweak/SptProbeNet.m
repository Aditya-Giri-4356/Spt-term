#import "SptProbe.h"

#if SPT_PROBE

#import <objc/runtime.h>
#import <os/lock.h>
#import <dlfcn.h>
#import <pthread.h>
#import <stdatomic.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface SptProbePathEntry : NSObject
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) double firstOffset;
@property (nonatomic, assign) double lastOffset;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *delegateClass;
@end

@implementation SptProbePathEntry
@end

static double s_installTime = 0.0;
static pthread_key_t s_netKey;
static pthread_once_t s_netKeyOnce = PTHREAD_ONCE_INIT;
static atomic_llong s_resumeCount;
static atomic_llong s_noURLCount;
static os_unfair_lock s_netLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *s_hosts;
static NSMutableDictionary<NSString *, NSNumber *> *s_methods;
static NSMutableDictionary<NSString *, NSNumber *> *s_taskClasses;
static NSMutableArray<NSString *> *s_installNotes;
static NSMutableSet<NSValue *> *s_hooked;
static NSMutableDictionary<NSString *, SptProbePathEntry *> *s_pathHistogram;
static NSMutableSet<NSString *> *s_sessionKeys;
static NSMutableArray<NSString *> *s_sessionLines;
static NSMutableDictionary<NSValue *, NSString *> *s_sessionDelegateCache;

static void spt_make_net_key(void) {
    pthread_key_create(&s_netKey, NULL);
}

static void spt_ensure_net_init(void) {
    if (!s_hosts) { s_hosts = [NSMutableDictionary new]; }
    if (!s_methods) { s_methods = [NSMutableDictionary new]; }
    if (!s_taskClasses) { s_taskClasses = [NSMutableDictionary new]; }
    if (!s_installNotes) { s_installNotes = [NSMutableArray new]; }
    if (!s_hooked) { s_hooked = [NSMutableSet new]; }
    if (!s_pathHistogram) { s_pathHistogram = [NSMutableDictionary new]; }
    if (!s_sessionKeys) { s_sessionKeys = [NSMutableSet new]; }
    if (!s_sessionLines) { s_sessionLines = [NSMutableArray new]; }
    if (!s_sessionDelegateCache) { s_sessionDelegateCache = [NSMutableDictionary new]; }
}

static void spt_bump(NSMutableDictionary<NSString *, NSNumber *> *d, NSString *k) {
    d[k] = @(d[k].longLongValue + 1);
}

static void spt_note_install(NSString *line) {
    os_unfair_lock_lock(&s_netLock);
    spt_ensure_net_init();
    if (s_installNotes.count < 500) {
        [s_installNotes addObject:line];
    }
    os_unfair_lock_unlock(&s_netLock);
}

static BOOL spt_class_declares_sel(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) {
        return NO;
    }
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

NSString *spt_probe_norm_path(NSString * _Nullable path) {
    if (!path || path.length == 0) {
        return @"/";
    }
    NSRange q = [path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (q.location != NSNotFound) {
        path = [path substringToIndex:q.location];
    }
    static NSCharacterSet *s_invAlnum = nil;
    static NSCharacterSet *s_invHex = nil;
    static NSCharacterSet *s_invDigits = nil;
    static dispatch_once_t s_csetOnce;
    dispatch_once(&s_csetOnce, ^{
        s_invAlnum = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet];
        s_invHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
        s_invDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    });
    
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *norm = [NSMutableArray arrayWithCapacity:parts.count];
    BOOL prevIsUser = NO;
    for (NSString *s in parts) {
        if (s.length == 0) {
            [norm addObject:@""];
            continue;
        }
        if (prevIsUser) {
            [norm addObject:@"{user}"];
            prevIsUser = NO;
            continue;
        }
        NSString *lower = [s lowercaseString];
        if ([lower isEqualToString:@"user"] || [lower isEqualToString:@"users"] || [lower isEqualToString:@"username"]) {
            prevIsUser = YES;
            [norm addObject:s];
            continue;
        }
        if (s.length == 22 && [s rangeOfCharacterFromSet:s_invAlnum].location == NSNotFound) {
            [norm addObject:@"{b62}"];
            continue;
        }
        if (s.length >= 16 && [s rangeOfCharacterFromSet:s_invHex].location == NSNotFound) {
            [norm addObject:@"{hex}"];
            continue;
        }
        if (s.length > 0 && [s rangeOfCharacterFromSet:s_invDigits].location == NSNotFound) {
            [norm addObject:@"{n}"];
            continue;
        }
        if ([lower hasPrefix:@"spotify:"] || [lower hasPrefix:@"spotify%3a"]) {
            [norm addObject:@"{uri}"];
            continue;
        }
        if (s.length > 40) {
            [norm addObject:@"{long}"];
            continue;
        }
        [norm addObject:s];
    }
    NSString *res = [norm componentsJoinedByString:@"/"];
    return res.length > 0 ? res : @"/";
}

static NSURLSession *spt_get_session_for_task(NSURLSessionTask *task, BOOL *outHasSel, BOOL *outHasIvar) {
    NSURLSession *session = nil;
    BOOL hasSel = NO;
    BOOL hasIvar = NO;
    @try {
        if ([task respondsToSelector:@selector(session)]) {
            hasSel = YES;
            session = [task performSelector:@selector(session)];
        }
    } @catch (NSException *e) {}
    if (!session) {
        @try {
            session = [task valueForKey:@"session"];
        } @catch (NSException *e) {}
    }
    if (!session) {
        @try {
            Ivar ivar = class_getInstanceVariable(object_getClass(task), "_session");
            if (ivar) {
                hasIvar = YES;
                session = object_getIvar(task, ivar);
            }
        } @catch (NSException *e) {}
    }
    if (outHasSel) *outHasSel = hasSel;
    if (outHasIvar) *outHasIvar = hasIvar;
    return session;
}

static NSString *spt_get_session_delegate_class(NSURLSession *session) {
    if (!session) {
        return @"(no-session)";
    }
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)session];
    os_unfair_lock_lock(&s_netLock);
    spt_ensure_net_init();
    NSString *cached = s_sessionDelegateCache[key];
    os_unfair_lock_unlock(&s_netLock);
    if (cached) {
        return cached;
    }
    
    id delegate = nil;
    @try { delegate = session.delegate; } @catch (NSException *e) {}
    Class delCls = delegate ? object_getClass(delegate) : Nil;
    NSString *delClsName = delCls ? NSStringFromClass(delCls) : @"(nil)";
    
    os_unfair_lock_lock(&s_netLock);
    s_sessionDelegateCache[key] = delClsName;
    os_unfair_lock_unlock(&s_netLock);
    return delClsName;
}

static void spt_probe_discover_session(NSURLSessionTask * __unused task, NSURLSession *session, BOOL hasSessionSel, BOOL hasSessionIvar) {
    if (!session) {
        static dispatch_once_t s_sessionUnavailOnce;
        dispatch_once(&s_sessionUnavailOnce, ^{
            spt_probe_log("E", "session: unavailable (session=%s _session=%s)",
                          hasSessionSel ? "Y" : "N", hasSessionIvar ? "Y" : "N");
        });
        return;
    }
    
    id delegate = nil;
    @try { delegate = session.delegate; } @catch (NSException *e) {}
    Class delCls = delegate ? object_getClass(delegate) : Nil;
    NSString *delClsName = delCls ? NSStringFromClass(delCls) : @"(nil)";
    
    NSURLSessionConfiguration *config = nil;
    @try { config = session.configuration; } @catch (NSException *e) {}
    NSString *configId = config.identifier ?: @"default";
    
    NSString *sessionKey = [NSString stringWithFormat:@"%@|%@", delClsName, configId];
    
    os_unfair_lock_lock(&s_netLock);
    spt_ensure_net_init();
    BOOL alreadySeen = [s_sessionKeys containsObject:sessionKey];
    BOOL canAddKey = (!alreadySeen && s_sessionKeys.count < 200);
    if (canAddKey) {
        [s_sessionKeys addObject:sessionKey];
    }
    os_unfair_lock_unlock(&s_netLock);
    
    if (!canAddKey) {
        return;
    }
    
    const char *delImg = "unknown";
    if (delCls) {
        Dl_info info;
        if (dladdr((__bridge const void *)delCls, &info) && info.dli_fname) {
            const char *slash = strrchr(info.dli_fname, '/');
            delImg = slash ? slash + 1 : info.dli_fname;
        }
    }
    
    NSString *qName = @"(unnamed)";
    @try {
        NSOperationQueue *q = session.delegateQueue;
        if (q.name.length > 0) {
            qName = q.name;
        }
    } @catch (NSException *e) {}
    
    NSMutableArray<NSString *> *protoStrs = [NSMutableArray new];
    @try {
        NSArray *protoClasses = config.protocolClasses;
        for (Class pCls in protoClasses) {
            Dl_info pInfo;
            const char *pImg = "unknown";
            if (dladdr((__bridge const void *)pCls, &pInfo) && pInfo.dli_fname) {
                const char *slash = strrchr(pInfo.dli_fname, '/');
                pImg = slash ? slash + 1 : pInfo.dli_fname;
            }
            [protoStrs addObject:[NSString stringWithFormat:@"%s (%s)", class_getName(pCls), pImg]];
        }
    } @catch (NSException *e) {}
    
    BOOL rData = NO;
    BOOL rResp = NO;
    BOOL rErr = NO;
    BOOL rDown = NO;
    if (delegate) {
        @try {
            rData = [delegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)];
            rResp = [delegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)];
            rErr = [delegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)];
            rDown = [delegate respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)];
        } @catch (NSException *e) {}
    }
    
    NSString *line = [NSString stringWithFormat:@"session: delegate=%@ (%s) queue=%@ protocols=[%@] responds: dataTask.didReceiveData=%s dataTask.didReceiveResponse=%s task.didCompleteWithError=%s downloadTask.didFinish=%s", delClsName, delImg, qName, [protoStrs componentsJoinedByString:@", "], rData ? "Y" : "N", rResp ? "Y" : "N", rErr ? "Y" : "N", rDown ? "Y" : "N"];
    
    spt_probe_log("E", "%s", line.UTF8String);
    
    os_unfair_lock_lock(&s_netLock);
    if (s_sessionLines.count < 100) {
        [s_sessionLines addObject:line];
    }
    os_unfair_lock_unlock(&s_netLock);
}

static void spt_record_task(NSURLSessionTask *task) {
    NSURLRequest *req = task.currentRequest ?: task.originalRequest;
    NSURL *url = req.URL;
    NSString *cls = NSStringFromClass(object_getClass(task));
    if (!url) {
        atomic_fetch_add(&s_noURLCount, 1);
        return;
    }
    NSString *method = req.HTTPMethod ?: @"GET";
    NSString *host = url.host ?: @"unknown-host";
    NSString *normPath = spt_probe_norm_path(url.path ?: @"/");
    NSString *keys = [(req.allHTTPHeaderFields.allKeys ?: @[]) componentsJoinedByString:@", "];
    
    BOOL hasSel = NO;
    BOOL hasIvar = NO;
    NSURLSession *session = spt_get_session_for_task(task, &hasSel, &hasIvar);
    NSString *delClsName = spt_get_session_delegate_class(session);
    
    double nowOffset = (s_installTime > 0.0) ? (CACurrentMediaTime() - s_installTime) : 0.0;
    NSString *histKey = [NSString stringWithFormat:@"%@ %@ %@ %@", method, host, normPath, delClsName];
    
    os_unfair_lock_lock(&s_netLock);
    spt_ensure_net_init();
    BOOL firstOfClass = (s_taskClasses[cls] == nil);
    spt_bump(s_hosts, host);
    spt_bump(s_methods, method);
    spt_bump(s_taskClasses, cls);
    
    SptProbePathEntry *entry = s_pathHistogram[histKey];
    if (!entry) {
        if (s_pathHistogram.count < 2000) {
            entry = [SptProbePathEntry new];
            entry.count = 1;
            entry.firstOffset = nowOffset;
            entry.lastOffset = nowOffset;
            entry.method = method;
            entry.host = host;
            entry.path = normPath;
            entry.delegateClass = delClsName;
            s_pathHistogram[histKey] = entry;
        } else {
            entry = s_pathHistogram[@"(overflow)"];
            if (!entry) {
                entry = [SptProbePathEntry new];
                entry.count = 1;
                entry.firstOffset = nowOffset;
                entry.lastOffset = nowOffset;
                entry.method = @"";
                entry.host = @"";
                entry.path = @"(overflow)";
                entry.delegateClass = @"";
                s_pathHistogram[@"(overflow)"] = entry;
            } else {
                entry.count += 1;
                entry.lastOffset = nowOffset;
            }
        }
    } else {
        entry.count += 1;
        entry.lastOffset = nowOffset;
    }
    os_unfair_lock_unlock(&s_netLock);
    
    if (firstOfClass) {
        spt_probe_log("E", "first task of class %s", cls.UTF8String);
    }
    spt_probe_log("E", "%s %s://%s%s [headers: %s] (%s) d=%s",
                  method.UTF8String, (url.scheme ?: @"").UTF8String,
                  host.UTF8String, normPath.UTF8String,
                  keys.UTF8String, cls.UTF8String, delClsName.UTF8String);
    
    spt_probe_discover_session(task, session, hasSel, hasIvar);
}

static void spt_hook_resume(Class cls) {
    SEL sel = @selector(resume);
    if (!cls || !spt_class_declares_sel(cls, sel)) {
        return;
    }
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)cls];
    if ([s_hooked containsObject:key]) {
        return;
    }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        return;
    }
    [s_hooked addObject:key];
    IMP orig = method_getImplementation(m);
    IMP hook = imp_implementationWithBlock(^(NSURLSessionTask *task) {
        BOOL outer = NO;
        if (spt_probe_is_enabled()) {
            pthread_once(&s_netKeyOnce, spt_make_net_key);
            if (pthread_getspecific(s_netKey) == NULL) {
                pthread_setspecific(s_netKey, (void *)1);
                outer = YES;
                atomic_fetch_add(&s_resumeCount, 1);
                @try { spt_record_task(task); } @catch (NSException *e) {}
            }
        }
        ((void (*)(id, SEL))orig)(task, sel);
        if (outer) {
            pthread_setspecific(s_netKey, NULL);
        }
    });
    method_setImplementation(m, hook);
    Dl_info info;
    const char *img = (dladdr((const void *)orig, &info) && info.dli_fname)
                          ? info.dli_fname : "unknown";
    spt_note_install([NSString stringWithFormat:@"hooked -[%s resume] orig=%p (%s)",
                                                class_getName(cls), orig, img]);
}

static void spt_hook_chain(Class c, Class base) {
    while (c && c != base) {
        spt_hook_resume(c);
        c = class_getSuperclass(c);
    }
}

static void spt_add_sample(NSMutableArray<NSURLSessionTask *> *arr, NSURLSessionTask *t) {
    if (t) {
        [arr addObject:t];
    }
}

void spt_probe_net_early_install(void) {
    if (!NSClassFromString(@"NSURLSessionTask")) {
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s_installTime = CACurrentMediaTime();
        os_unfair_lock_lock(&s_netLock);
        spt_ensure_net_init();
        os_unfair_lock_unlock(&s_netLock);
        
        Class base = [NSURLSessionTask class];
        spt_hook_resume(base);
        spt_note_install(@"transport probe early-installed (base resume)");
    });
}

void spt_probe_net_install(void) {
    spt_probe_net_early_install();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        os_unfair_lock_lock(&s_netLock);
        spt_ensure_net_init();
        os_unfair_lock_unlock(&s_netLock);
        
        Class base = [NSURLSessionTask class];
        spt_hook_resume(base);

        NSURLSession *probeSession = [NSURLSession sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURL *u = [NSURL URLWithString:@"https://localhost.invalid/"];
        NSMutableArray<NSURLSessionTask *> *samples = [NSMutableArray new];
        spt_add_sample(samples, [probeSession dataTaskWithURL:u]);
        spt_add_sample(samples, [probeSession uploadTaskWithRequest:
                                    [NSURLRequest requestWithURL:u] fromData:[NSData data]]);
        spt_add_sample(samples, [probeSession downloadTaskWithURL:u]);
        if (@available(iOS 13.0, *)) {
            spt_add_sample(samples, [probeSession webSocketTaskWithURL:
                                        [NSURL URLWithString:@"wss://localhost.invalid/"]]);
        }
        for (NSURLSessionTask *t in samples) {
            spt_note_install([NSString stringWithFormat:@"sample task class: %s",
                              class_getName(object_getClass(t))]);
            spt_hook_chain(object_getClass(t), base);
        }
        [probeSession invalidateAndCancel];

        const int cap = 40000;
        int total = objc_getClassList(NULL, 0);
        int n = total < cap ? total : cap;
        Class *list = n > 0 ? (Class *)malloc(sizeof(Class) * (size_t)n) : NULL;
        if (list) {
            int got = objc_getClassList(list, n);
            if (got > n) { got = n; }
            for (int i = 0; i < got; i++) {
                Class c = list[i];
                if (c == base) { continue; }
                Class cur = class_getSuperclass(c);
                while (cur && cur != base) { cur = class_getSuperclass(cur); }
                if (cur == base) { spt_hook_resume(c); }
            }
            free(list);
            if (total > cap) {
                spt_note_install([NSString stringWithFormat:@"class list truncated: %d of %d", got, total]);
            }
        } else if (n > 0) {
            spt_note_install(@"class list malloc failed; relying on sample tasks only");
        }
        spt_note_install(@"transport probe installed (resume-only)");
    });
}

void spt_probe_net_run(void) {
    if (!spt_probe_is_enabled()) { return; }
    dispatch_async(spt_probe_get_queue(), ^{
        os_unfair_lock_lock(&s_netLock);
        NSDictionary *hosts = [s_hosts copy];
        NSDictionary *methods = [s_methods copy];
        NSDictionary *classes = [s_taskClasses copy];
        NSArray *notes = [s_installNotes copy];
        NSArray<SptProbePathEntry *> *entries = [s_pathHistogram.allValues copy];
        NSArray<NSString *> *sessionLines = [s_sessionLines copy];
        os_unfair_lock_unlock(&s_netLock);
        
        for (NSString *note in notes) {
            spt_probe_log("E", "install: %s", note.UTF8String);
        }
        spt_probe_log("E", "--- transport summary: resumes=%lld, tasks-without-URL=%lld ---",
                      (long long)atomic_load(&s_resumeCount),
                      (long long)atomic_load(&s_noURLCount));
        for (NSString *h in hosts) {
            spt_probe_log("E", "host %s: %ld", h.UTF8String, (long)[hosts[h] integerValue]);
        }
        for (NSString *k in methods) {
            spt_probe_log("E", "method %s: %ld", k.UTF8String, (long)[methods[k] integerValue]);
        }
        for (NSString *c in classes) {
            spt_probe_log("E", "task class %s: %ld", c.UTF8String, (long)[classes[c] integerValue]);
        }
        
        NSArray<SptProbePathEntry *> *sortedByCount = [entries sortedArrayUsingComparator:
            ^NSComparisonResult(SptProbePathEntry *a, SptProbePathEntry *b) {
                if (a.count > b.count) return NSOrderedAscending;
                if (a.count < b.count) return NSOrderedDescending;
                return NSOrderedSame;
            }];
        
        spt_probe_log("E", "--- path histogram: top 40 by count ---");
        NSInteger topCount = MIN((NSInteger)sortedByCount.count, 40);
        for (NSInteger i = 0; i < topCount; i++) {
            SptProbePathEntry *e = sortedByCount[i];
            spt_probe_log("E", "%ld %s %s %s first=+%.1fs last=+%.1fs d=%s",
                          (long)e.count, e.method.UTF8String, e.host.UTF8String,
                          e.path.UTF8String, e.firstOffset, e.lastOffset,
                          (e.delegateClass ?: @"(none)").UTF8String);
        }
        
        NSMutableArray<SptProbePathEntry *> *nonImage = [NSMutableArray new];
        for (SptProbePathEntry *e in entries) {
            NSString *h = [e.host lowercaseString];
            if ([h containsString:@"image-cdn"] ||
                [h containsString:@"scdn.co/image"] ||
                [h containsString:@"mosaic"] ||
                [h containsString:@"pickasso"] ||
                [h containsString:@"canvaz"]) {
                continue;
            }
            [nonImage addObject:e];
        }
        [nonImage sortUsingComparator:^NSComparisonResult(SptProbePathEntry *a, SptProbePathEntry *b) {
            if (a.firstOffset < b.firstOffset) return NSOrderedAscending;
            if (a.firstOffset > b.firstOffset) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        spt_probe_log("E", "--- first appearance order, non-image hosts (cap 150) ---");
        NSInteger nonImageCount = MIN((NSInteger)nonImage.count, 150);
        for (NSInteger i = 0; i < nonImageCount; i++) {
            SptProbePathEntry *e = nonImage[i];
            spt_probe_log("E", "%ld %s %s %s first=+%.1fs last=+%.1fs d=%s",
                          (long)e.count, e.method.UTF8String, e.host.UTF8String,
                          e.path.UTF8String, e.firstOffset, e.lastOffset,
                          (e.delegateClass ?: @"(none)").UTF8String);
        }
        
        for (NSString *line in sessionLines) {
            spt_probe_log("E", "%s", line.UTF8String);
        }
        
        if (atomic_load(&s_resumeCount) == 0) {
            spt_probe_log("E", "ZERO resumes: probe was off while traffic ran, or the app does not use NSURLSession tasks");
        }
    });
}

#endif
