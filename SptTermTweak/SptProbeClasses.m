#import "SptProbe.h"

#if SPT_PROBE

#import <objc/runtime.h>

@interface SptClassScore : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, strong) NSMutableArray<NSString *> *matchingSelectors;
@end

@implementation SptClassScore
@end

static BOOL spt_contains_keyword(NSString *str, NSArray<NSString *> *kw) {
    NSString *lower = [str lowercaseString];
    for (NSString *k in kw) {
        if ([lower containsString:k]) return YES;
    }
    return NO;
}

static NSInteger spt_selector_match_score(NSString *selName, NSArray<NSString *> *kw) {
    NSString *lower = [selName lowercaseString];
    NSInteger sc = 0;
    for (NSString *k in kw) {
        if ([lower containsString:k]) sc++;
    }
    return sc;
}

void spt_probe_classes_run(void) {
    if (!spt_probe_is_enabled()) { return; }
    dispatch_async(spt_probe_get_queue(), ^{
        unsigned int totalClasses = 0;
        Class *classList = objc_copyClassList(&totalClasses);
        if (!classList || totalClasses == 0) {
            spt_probe_log("A", "No classes found");
            if (classList) free(classList);
            return;
        }
        
        unsigned int cappedCount = totalClasses < 250000 ? totalClasses : 250000;
        spt_probe_log("A", "Class inventory: found %u classes (capped at %u)", totalClasses, cappedCount);
        
        NSMutableDictionary<NSString *, NSNumber *> *imageCounts = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, NSNumber *> *prefixCounts = [NSMutableDictionary new];
        NSMutableArray<SptClassScore *> *keywordClasses = [NSMutableArray new];
        
        NSArray<NSString *> *classKeywords = @[
            @"player", @"playback", @"playcommand", @"playoptions", @"playcontext",
            @"queue", @"rootlist", @"playlist", @"collection", @"library",
            @"track", @"dataloader", @"remote", @"connect"
        ];
        
        NSArray<NSString *> *selKeywords = @[
            @"play", @"uri", @"context", @"track", @"load", @"fetch"
        ];
        
        for (unsigned int i = 0; i < cappedCount; i++) {
            Class cls = classList[i];
            if (!cls) continue;
            
            const char *rawImg = class_getImageName(cls);
            const char *slash = rawImg ? strrchr(rawImg, '/') : NULL;
            NSString *imgBase = slash ? [NSString stringWithUTF8String:slash + 1] : (rawImg ? [NSString stringWithUTF8String:rawImg] : @"(none)");
            imageCounts[imgBase] = @(imageCounts[imgBase].integerValue + 1);
            
            BOOL isNonSystem = (rawImg == NULL) || (strncmp(rawImg, "/System/", 8) != 0 && strncmp(rawImg, "/usr/lib/", 9) != 0);
            if (!isNonSystem) {
                continue;
            }
            
            const char *rawName = class_getName(cls);
            if (!rawName) continue;
            
            char *demangled = spt_probe_demangle(rawName);
            const char *cNameUse = demangled ? demangled : rawName;
            NSString *className = [NSString stringWithUTF8String:cNameUse];
            
            char pfx[5] = {0};
            int pfxLen = 0;
            for (int p = 0; cNameUse[p] && pfxLen < 4; p++) {
                char c = cNameUse[p];
                if (c >= 'A' && c <= 'Z') {
                    pfx[pfxLen++] = c;
                } else {
                    break;
                }
            }
            if (pfxLen > 0) {
                NSString *pStr = [NSString stringWithUTF8String:pfx];
                prefixCounts[pStr] = @(prefixCounts[pStr].integerValue + 1);
            }
            
            if (spt_contains_keyword(className, classKeywords)) {
                SptClassScore *cs = [SptClassScore new];
                cs.className = className;
                cs.imageName = imgBase;
                cs.matchingSelectors = [NSMutableArray new];
                
                unsigned int mCount = 0;
                Method *methods = class_copyMethodList(cls, &mCount);
                if (methods) {
                    for (unsigned int m = 0; m < mCount; m++) {
                        SEL sel = method_getName(methods[m]);
                        const char *sName = sel_getName(sel);
                        if (sName) {
                            NSString *sn = [NSString stringWithUTF8String:sName];
                            NSInteger sc = spt_selector_match_score(sn, selKeywords);
                            if (sc > 0) {
                                cs.score += sc;
                                [cs.matchingSelectors addObject:sn];
                            }
                        }
                    }
                    free(methods);
                }
                
                Class meta = object_getClass((id)cls);
                if (meta && meta != cls) {
                    unsigned int cmCount = 0;
                    Method *cmethods = class_copyMethodList(meta, &cmCount);
                    if (cmethods) {
                        for (unsigned int m = 0; m < cmCount; m++) {
                            SEL sel = method_getName(cmethods[m]);
                            const char *sName = sel_getName(sel);
                            if (sName) {
                                NSString *sn = [NSString stringWithUTF8String:sName];
                                NSInteger sc = spt_selector_match_score(sn, selKeywords);
                                if (sc > 0) {
                                    cs.score += sc;
                                    [cs.matchingSelectors addObject:[@"+" stringByAppendingString:sn]];
                                }
                            }
                        }
                        free(cmethods);
                    }
                }
                
                [keywordClasses addObject:cs];
            }
            
            if (demangled) {
                free(demangled);
            }
        }
        free(classList);
        
        NSArray<NSString *> *sortedImages = [imageCounts.allKeys sortedArrayUsingComparator:
            ^NSComparisonResult(NSString *a, NSString *b) {
                NSInteger ca = [imageCounts[a] integerValue];
                NSInteger cb = [imageCounts[b] integerValue];
                if (ca > cb) return NSOrderedAscending;
                if (ca < cb) return NSOrderedDescending;
                return [a compare:b];
            }];
        spt_probe_log("A", "--- images: top 30 by class count ---");
        NSInteger topImgCount = MIN((NSInteger)sortedImages.count, 30);
        for (NSInteger i = 0; i < topImgCount; i++) {
            NSString *img = sortedImages[i];
            spt_probe_log("A", "%ld %s", (long)[imageCounts[img] integerValue], img.UTF8String);
        }
        
        NSArray<NSString *> *sortedPrefixes = [prefixCounts.allKeys sortedArrayUsingComparator:
            ^NSComparisonResult(NSString *a, NSString *b) {
                NSInteger ca = [prefixCounts[a] integerValue];
                NSInteger cb = [prefixCounts[b] integerValue];
                if (ca > cb) return NSOrderedAscending;
                if (ca < cb) return NSOrderedDescending;
                return [a compare:b];
            }];
        spt_probe_log("A", "--- name prefixes in non-system images (top 30) ---");
        NSInteger topPfxCount = MIN((NSInteger)sortedPrefixes.count, 30);
        for (NSInteger i = 0; i < topPfxCount; i++) {
            NSString *p = sortedPrefixes[i];
            spt_probe_log("A", "%ld %s", (long)[prefixCounts[p] integerValue], p.UTF8String);
        }
        
        spt_probe_log("A", "--- keyword classes (cap 500) ---");
        NSInteger kwCount = MIN((NSInteger)keywordClasses.count, 500);
        for (NSInteger i = 0; i < kwCount; i++) {
            SptClassScore *cs = keywordClasses[i];
            spt_probe_log("A", "%s (%s)", cs.className.UTF8String, cs.imageName.UTF8String);
        }
        
        [keywordClasses sortUsingComparator:^NSComparisonResult(SptClassScore *a, SptClassScore *b) {
            if (a.score > b.score) return NSOrderedAscending;
            if (a.score < b.score) return NSOrderedDescending;
            return [a.className compare:b.className];
        }];
        
        spt_probe_log("A", "--- selector dump (top 40 classes, up to 25 selectors each) ---");
        NSInteger topDumpCount = MIN((NSInteger)keywordClasses.count, 40);
        for (NSInteger i = 0; i < topDumpCount; i++) {
            SptClassScore *cs = keywordClasses[i];
            
            [cs.matchingSelectors sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                NSInteger sa = spt_selector_match_score(a, selKeywords);
                NSInteger sb = spt_selector_match_score(b, selKeywords);
                if (sa > sb) return NSOrderedAscending;
                if (sa < sb) return NSOrderedDescending;
                return [a compare:b];
            }];
            
            NSInteger selLimit = MIN((NSInteger)cs.matchingSelectors.count, 25);
            NSArray<NSString *> *sub = [cs.matchingSelectors subarrayWithRange:NSMakeRange(0, selLimit)];
            NSString *joined = [sub componentsJoinedByString:@" "];
            spt_probe_log("A", "%s: %s", cs.className.UTF8String, joined.UTF8String);
        }
    });
}

#endif
