#import "SptProbe.h"

#if SPT_PROBE

#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <mach/mach.h>

typedef struct {
    int lineCount;
    size_t byteCount;
    BOOL exceededLogged;
} SptBBudget;

static void spt_b_budget_log(SptBBudget *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

static void spt_b_budget_log(SptBBudget *b, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[2048];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    size_t len = strlen(buf);
    if (b->lineCount >= 450 || b->byteCount + len >= 58 * 1024) {
        if (!b->exceededLogged) {
            b->exceededLogged = YES;
            spt_probe_log("B", "budget exceeded");
        }
        return;
    }
    b->lineCount++;
    b->byteCount += len + 30;
    spt_probe_log("B", "%s", buf);
}

typedef struct {
    void *obj;
    Class cls;
} SptHeapObj;

typedef struct {
    CFSetRef classSet;
    SptHeapObj *objects;
    size_t count;
    size_t cap;
    uint64_t totalBlocks;
} SptBEnumContext;

static kern_return_t spt_b_reader(task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory) {
    (void)task;
    (void)size;
    *local_memory = (void *)remote_address;
    return KERN_SUCCESS;
}

static void spt_b_recorder(task_t __unused task, void *context, unsigned type, vm_range_t *ranges, unsigned range_count) {
    (void)type;
    SptBEnumContext *ctx = (SptBEnumContext *)context;
    task_t selfTask = mach_task_self();
    for (unsigned i = 0; i < range_count; i++) {
        ctx->totalBlocks++;
        vm_range_t r = ranges[i];
        if (r.size >= 16 && (r.address & 0xF) == 0 && ctx->count < ctx->cap) {
            uintptr_t word = 0;
            vm_size_t outSize = 0;
            if (vm_read_overwrite(selfTask, r.address, sizeof(uintptr_t), (vm_address_t)&word, &outSize) == KERN_SUCCESS && outSize == sizeof(uintptr_t)) {
                uintptr_t isaMasked = word & 0x0000000ffffffff8ULL;
                Class cls = NULL;
                if (CFSetContainsValue(ctx->classSet, (const void *)isaMasked)) {
                    cls = (__bridge Class)(void *)isaMasked;
                } else if ((word & 1) == 0 && CFSetContainsValue(ctx->classSet, (const void *)word)) {
                    cls = (__bridge Class)(void *)word;
                }
                if (cls) {
                    ctx->objects[ctx->count].obj = (void *)r.address;
                    ctx->objects[ctx->count].cls = cls;
                    ctx->count++;
                }
            }
        }
    }
}

static BOOL spt_b_is_sensitive(const char *name) {
    if (!name) return NO;
    NSString *s = [[NSString stringWithUTF8String:name] lowercaseString];
    return [s containsString:@"token"] || [s containsString:@"auth"] ||
           [s containsString:@"password"] || [s containsString:@"secret"] ||
           [s containsString:@"bearer"] || [s containsString:@"credential"] ||
           [s containsString:@"cookie"];
}

static BOOL spt_b_recurse_matches(NSString *clsName) {
    if (!clsName) return NO;
    return [clsName containsString:@"Player"] || [clsName containsString:@"Loader"] ||
           [clsName containsString:@"Controller"] || [clsName containsString:@"Service"] ||
           [clsName containsString:@"Client"] || [clsName containsString:@"Model"] ||
           [clsName containsString:@"Platform"] || [clsName containsString:@"Esperanto"];
}

static BOOL spt_b_interest_matches(const char *name) {
    if (!name) return NO;
    NSString *s = [[NSString stringWithUTF8String:name] lowercaseString];
    return [s containsString:@"player"] || [s containsString:@"playback"] ||
           [s containsString:@"loader"] || [s containsString:@"controller"] ||
           [s containsString:@"service"] || [s containsString:@"esperanto"] ||
           [s containsString:@"rootlist"] || [s containsString:@"collection"] ||
           [s containsString:@"library"];
}

static NSString *spt_b_summarize_obj(id val) {
    if (!val) return @"(nil)";
    @try {
        if ([val isKindOfClass:[NSString class]]) {
            NSString *s = (NSString *)val;
            NSString *cut = (s.length > 60) ? [s substringToIndex:60] : s;
            return [NSString stringWithFormat:@"\"%@\"", cut];
        } else if ([val isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"%@", val];
        } else if ([val isKindOfClass:[NSArray class]]) {
            return [NSString stringWithFormat:@"[NSArray count=%lu]", (unsigned long)[(NSArray *)val count]];
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            return [NSString stringWithFormat:@"[NSDictionary count=%lu]", (unsigned long)[(NSDictionary *)val count]];
        } else if ([val isKindOfClass:[NSSet class]]) {
            return [NSString stringWithFormat:@"[NSSet count=%lu]", (unsigned long)[(NSSet *)val count]];
        } else {
            return NSStringFromClass(object_getClass(val));
        }
    } @catch (NSException *e) {
        return @"(exception)";
    }
}

static void spt_b_dump_ivars(id inst, Class c, NSString *prefix, SptBBudget *budget, int *dumpedObjectsCount, BOOL canRecurse) {
    if (!inst || !c || *dumpedObjectsCount >= 200) return;
    (*dumpedObjectsCount)++;
    
    task_t selfTask = mach_task_self();
    Class cur = c;
    while (cur && cur != [NSObject class]) {
        unsigned int ivCount = 0;
        Ivar *ivList = class_copyIvarList(cur, &ivCount);
        if (ivList) {
            unsigned int loggedIv = 0;
            for (unsigned int i = 0; i < ivCount && loggedIv < 40; i++) {
                Ivar iv = ivList[i];
                const char *inm = ivar_getName(iv);
                if (!inm || spt_b_is_sensitive(inm)) continue;
                ptrdiff_t ioff = ivar_getOffset(iv);
                const char *ienc = ivar_getTypeEncoding(iv);
                
                if (!ienc || ienc[0] == '\0') {
                    spt_b_budget_log(budget, "%s %s swift off=%td", prefix.UTF8String, inm, ioff);
                    loggedIv++;
                } else if (ienc[0] == '@') {
                    id val = nil;
                    @try {
                        val = object_getIvar(inst, iv);
                    } @catch (NSException *e) {}
                    NSString *summary = spt_b_summarize_obj(val);
                    spt_b_budget_log(budget, "inst: %s %s = %s", prefix.UTF8String, inm, summary.UTF8String);
                    loggedIv++;
                    
                    if (canRecurse && val && [val class] && *dumpedObjectsCount < 200) {
                        Class valCls = object_getClass(val);
                        NSString *valClsName = NSStringFromClass(valCls);
                        if (spt_b_recurse_matches(valClsName)) {
                            NSString *subPrefix = [NSString stringWithFormat:@"%@.%@", prefix, [NSString stringWithUTF8String:inm]];
                            spt_b_dump_ivars(val, valCls, subPrefix, budget, dumpedObjectsCount, NO);
                        }
                    }
                } else {
                    // Scalar 1, 4, or 8 bytes
                    size_t sz = 0;
                    if (strchr("cCBb", ienc[0])) sz = 1;
                    else if (strchr("sSiI", ienc[0])) sz = 4;
                    else if (strchr("qQlLfd", ienc[0])) sz = 8;
                    else sz = sizeof(void *);
                    
                    if (sz == 1 || sz == 4 || sz == 8) {
                        uint64_t val = 0;
                        vm_size_t readSz = 0;
                        vm_address_t addr = (vm_address_t)((char *)(__bridge void *)inst + ioff);
                        if (vm_read_overwrite(selfTask, addr, sz, (vm_address_t)&val, &readSz) == KERN_SUCCESS && readSz == sz) {
                            spt_b_budget_log(budget, "inst: %s %s = 0x%llx", prefix.UTF8String, inm, (unsigned long long)val);
                            loggedIv++;
                        }
                    }
                }
            }
            free(ivList);
        }
        cur = class_getSuperclass(cur);
    }
}

void spt_probe_heap_run(void) {
    if (!spt_probe_is_enabled()) return;
    
    // Log marker BEFORE enumeration
    spt_probe_log("B", "B: starting heap enumeration");
    
    SptBBudget budget = {0, 0, NO};
    
    // 1. Class set (cap 250000)
    unsigned int totalClasses = 0;
    Class *classList = objc_copyClassList(&totalClasses);
    unsigned int cappedClasses = MIN(totalClasses, (unsigned int)250000);
    CFMutableSetRef classSet = CFSetCreateMutable(kCFAllocatorDefault, (CFIndex)cappedClasses, NULL);
    for (unsigned int i = 0; i < cappedClasses; i++) {
        if (classList[i]) {
            CFSetAddValue(classSet, (__bridge const void *)classList[i]);
        }
    }
    
    // 2. Enumerate zones
    size_t objCap = 400000;
    SptHeapObj *heapObjs = (SptHeapObj *)malloc(sizeof(SptHeapObj) * objCap);
    SptBEnumContext ctx;
    ctx.classSet = classSet;
    ctx.objects = heapObjs;
    ctx.count = 0;
    ctx.cap = objCap;
    ctx.totalBlocks = 0;
    
    vm_address_t *zones = NULL;
    unsigned int zoneCount = 0;
    if (malloc_get_all_zones(mach_task_self(), spt_b_reader, &zones, &zoneCount) == KERN_SUCCESS) {
        for (unsigned int z = 0; z < zoneCount && ctx.count < ctx.cap; z++) {
            malloc_zone_t *zone = (malloc_zone_t *)zones[z];
            if (zone && zone->introspect && zone->introspect->enumerator) {
                zone->introspect->enumerator(mach_task_self(), &ctx, MALLOC_PTR_IN_USE_RANGE_TYPE, (vm_address_t)zone, spt_b_reader, spt_b_recorder);
            }
        }
    }
    
    spt_b_budget_log(&budget, "B: zones=%u blocks=%llu objects=%zu", zoneCount, (unsigned long long)ctx.totalBlocks, ctx.count);
    
    // 3. Targets (the 12 Experiment I classes plus subclasses)
    NSArray<NSString *> *targetNames = @[
        @"SPTExternalIntegrationPlaybackControllerImplementation",
        @"SPTEsperantoPlayer",
        @"SPTPlayerServiceImplementation",
        @"SPTPlaylistPlatformEsperantoDataLoader",
        @"SPTCollectionPlatformDataLoaderImplementation",
        @"SPTMobileMediaKitAudioPlaybackManager",
        @"SPTPlayerStateImplementation",
        @"ESPContextPlayerState",
        @"SPTPlaylistPlatformModelImplementation",
        @"SPTPlayerRestrictionsImplementation",
        @"SPTFreeTierEntityPlaybackToggleContentOperation",
        @"NowPlaying_PlatformImpl.StatefulPlayerImplementation"
    ];
    
    NSMutableSet<NSValue *> *targetClassPtrs = [NSMutableSet new];
    for (NSString *tName in targetNames) {
        Class tc = objc_getClass(tName.UTF8String);
        if (!tc) {
            for (unsigned int i = 0; i < cappedClasses; i++) {
                const char *cn = class_getName(classList[i]);
                if (cn) {
                    char *dem = spt_probe_demangle(cn);
                    if (dem) {
                        if (strcmp(dem, tName.UTF8String) == 0 || strstr(dem, tName.UTF8String)) {
                            tc = classList[i];
                            free(dem);
                            break;
                        }
                        free(dem);
                    }
                }
            }
        }
        if (tc) {
            [targetClassPtrs addObject:[NSValue valueWithPointer:(__bridge const void *)tc]];
        }
    }
    
    // Also include any subclasses of targets
    NSMutableSet<NSValue *> *allTargetHierarchy = [NSMutableSet setWithSet:targetClassPtrs];
    for (unsigned int i = 0; i < cappedClasses; i++) {
        Class c = classList[i];
        Class cur = class_getSuperclass(c);
        int depth = 0;
        while (cur && depth < 10) {
            if ([targetClassPtrs containsObject:[NSValue valueWithPointer:(__bridge const void *)cur]]) {
                [allTargetHierarchy addObject:[NSValue valueWithPointer:(__bridge const void *)c]];
                break;
            }
            cur = class_getSuperclass(cur);
            depth++;
        }
    }
    
    // Map objects to targets
    NSMutableDictionary<NSValue *, NSMutableArray<NSValue *> *> *targetInstances = [NSMutableDictionary new];
    NSMutableDictionary<NSValue *, NSNumber *> *classLiveCounts = [NSMutableDictionary new];
    
    for (size_t i = 0; i < ctx.count; i++) {
        Class c = heapObjs[i].cls;
        if (!c) continue;
        NSValue *cv = [NSValue valueWithPointer:(__bridge const void *)c];
        classLiveCounts[cv] = @(classLiveCounts[cv].integerValue + 1);
        
        if ([allTargetHierarchy containsObject:cv]) {
            NSMutableArray *arr = targetInstances[cv];
            if (!arr) {
                arr = [NSMutableArray new];
                targetInstances[cv] = arr;
            }
            if (arr.count < 4) {
                [arr addObject:[NSValue valueWithPointer:heapObjs[i].obj]];
            }
        }
    }
    
    uint64_t totalTargetInstances = 0;
    int dumpedObjectsCount = 0;
    
    for (NSValue *cv in targetInstances) {
        Class c = (__bridge Class)[cv pointerValue];
        const char *cName = class_getName(c);
        char *dem = spt_probe_demangle(cName);
        NSString *cNameStr = [NSString stringWithUTF8String:dem ? dem : cName];
        if (dem) free(dem);
        
        NSInteger instCount = [classLiveCounts[cv] integerValue];
        totalTargetInstances += (uint64_t)instCount;
        spt_b_budget_log(&budget, "B: %s instances=%ld", cNameStr.UTF8String, (long)instCount);
        
        NSArray<NSValue *> *samples = targetInstances[cv];
        for (NSUInteger k = 0; k < samples.count && k < 4; k++) {
            id inst = (__bridge id)[samples[k] pointerValue];
            NSString *prefix = [NSString stringWithFormat:@"%@#%lu", cNameStr, (unsigned long)k];
            spt_b_dump_ivars(inst, c, prefix, &budget, &dumpedObjectsCount, YES);
        }
    }
    
    // 4. Live classes of interest (top 80)
    spt_b_budget_log(&budget, "--- live classes of interest ---");
    NSMutableArray<NSValue *> *interestClasses = [NSMutableArray new];
    for (NSValue *cv in classLiveCounts) {
        Class c = (__bridge Class)[cv pointerValue];
        const char *img = class_getImageName(c);
        if (img && (strncmp(img, "/System/", 8) == 0 || strncmp(img, "/usr/lib/", 9) == 0)) {
            continue;
        }
        const char *cn = class_getName(c);
        if (spt_b_interest_matches(cn)) {
            [interestClasses addObject:cv];
        } else {
            char *dem = spt_probe_demangle(cn);
            if (dem) {
                if (spt_b_interest_matches(dem)) {
                    [interestClasses addObject:cv];
                }
                free(dem);
            }
        }
    }
    
    [interestClasses sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        NSInteger ca = [classLiveCounts[a] integerValue];
        NSInteger cb = [classLiveCounts[b] integerValue];
        if (ca > cb) return NSOrderedAscending;
        if (ca < cb) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    NSInteger topInterest = MIN((NSInteger)interestClasses.count, (NSInteger)80);
    for (NSInteger i = 0; i < topInterest; i++) {
        Class c = (__bridge Class)[interestClasses[i] pointerValue];
        const char *cn = class_getName(c);
        char *dem = spt_probe_demangle(cn);
        const char *useName = dem ? dem : cn;
        spt_b_budget_log(&budget, "live: %ld %s", (long)[classLiveCounts[interestClasses[i]] integerValue], useName);
        if (dem) free(dem);
    }
    
    if (heapObjs) free(heapObjs);
    if (classList) free(classList);
    CFRelease(classSet);
    
    // 5. Summary LAST
    spt_probe_log("B", "--- B summary --- zones=%u blocks=%llu objects=%zu target_instances=%llu",
                  zoneCount, (unsigned long long)ctx.totalBlocks, ctx.count, (unsigned long long)totalTargetInstances);
}

#endif
