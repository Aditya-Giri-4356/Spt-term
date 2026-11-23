#import "SptProbe.h"
#if SPT_PROBE
#import <objc/runtime.h>
#import <os/lock.h>
#import <dlfcn.h>
#import <pthread.h>
#import <stdatomic.h>

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

static void spt_make_net_key(void) { pthread_key_create(&s_netKey, NULL); }

static void spt_bump(NSMutableDictionary<NSString *, NSNumber *> *d, NSString *k) {
    d[k] = @(d[k].longLongValue + 1);
}

static void spt_note_install(NSString *line) {
    os_unfair_lock_lock(&s_netLock);
    if (!s_installNotes) { s_installNotes = [NSMutableArray new]; }
    if (s_installNotes.count < 500) { [s_installNotes addObject:line]; }
    os_unfair_lock_unlock(&s_netLock);
}

static BOOL spt_class_declares_sel(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) { return NO; }
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = YES; break; }
    }
    free(methods);
    return found;
}

static void spt_record_task(NSURLSessionTask *task) {
    NSURLRequest *req = task.currentRequest ?: task.originalRequest; // KNOWN Foundation
    NSURL *url = req.URL;
    NSString *cls = NSStringFromClass(object_getClass(task));
    if (!url) {
        atomic_fetch_add(&s_noURLCount, 1);
        return;
    }
    NSString *method = req.HTTPMethod ?: @"GET";
    NSString *host = url.host ?: @"unknown-host";
    NSString *keys = [(req.allHTTPHeaderFields.allKeys ?: @[])
                         componentsJoinedByString:@", "];
    os_unfair_lock_lock(&s_netLock);
    BOOL firstOfClass = (s_taskClasses[cls] == nil);
    spt_bump(s_hosts, host);
    spt_bump(s_methods, method);
    spt_bump(s_taskClasses, cls);
    os_unfair_lock_unlock(&s_netLock);
    if (firstOfClass) {
        spt_probe_log("E", "first task of class %s", cls.UTF8String);
    }
    spt_probe_log("E", "%s %s://%s%s [headers: %s] (%s)",
                  method.UTF8String, (url.scheme ?: @"").UTF8String,
                  host.UTF8String, (url.path ?: @"/").UTF8String,
                  keys.UTF8String, cls.UTF8String);
}

static void spt_hook_resume(Class cls) {
    SEL sel = @selector(resume); // KNOWN Foundation selector
    if (!cls || !spt_class_declares_sel(cls, sel)) { return; }
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)cls];
    if ([s_hooked containsObject:key]) { return; }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { return; }
    [s_hooked addObject:key];
    IMP orig = method_getImplementation(m);   // by value: each hook owns its original
    IMP hook = imp_implementationWithBlock(^(NSURLSessionTask *task) {
        BOOL outer = NO;
        if (spt_probe_is_enabled()) {
            pthread_once(&s_netKeyOnce, spt_make_net_key);
            if (pthread_getspecific(s_netKey) == NULL) {   // nested super-calls skipped
                pthread_setspecific(s_netKey, (void *)1);
                outer = YES;
                atomic_fetch_add(&s_resumeCount, 1);
                @try { spt_record_task(task); } @catch (NSException *e) {}
            }
        }
        ((void (*)(id, SEL))orig)(task, sel);
        if (outer) { pthread_setspecific(s_netKey, NULL); }
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
    if (t) { [arr addObject:t]; }
}

void spt_probe_net_install(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s_hosts = [NSMutableDictionary new];
        s_methods = [NSMutableDictionary new];
        s_taskClasses = [NSMutableDictionary new];
        s_hooked = [NSMutableSet new];
        Class base = [NSURLSessionTask class];
        spt_hook_resume(base);

        // Discover concrete task classes from never-resumed sample tasks (no traffic).
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

        // Supplemental bounded scan for any other subclass of NSURLSessionTask.
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
                spt_note_install([NSString stringWithFormat:
                    @"class list truncated: %d of %d", got, total]);
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
        if (atomic_load(&s_resumeCount) == 0) {
            spt_probe_log("E", "ZERO resumes: probe was off while traffic ran, "
                               "or the app does not use NSURLSession tasks");
        }
    });
}
#endif
