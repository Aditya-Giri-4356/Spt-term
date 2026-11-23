#import "SptProbe.h"

#if SPT_PROBE

#import <objc/runtime.h>
#import <dlfcn.h>

typedef struct {
    int lineCount;
    size_t byteCount;
    BOOL exceededLogged;
} SptIBudget;

static void spt_i_budget_log(SptIBudget *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

static void spt_i_budget_log(SptIBudget *b, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[2048];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    size_t len = strlen(buf);
    if (b->lineCount >= 450 || b->byteCount + len >= 58 * 1024) {
        if (!b->exceededLogged) {
            b->exceededLogged = YES;
            spt_probe_log("I", "budget exceeded");
        }
        return;
    }
    b->lineCount++;
    b->byteCount += len + 30;
    spt_probe_log("I", "%s", buf);
}

static BOOL spt_i_is_sensitive(const char *name) {
    if (!name) return NO;
    NSString *s = [[NSString stringWithUTF8String:name] lowercaseString];
    return [s containsString:@"token"] || [s containsString:@"auth"] ||
           [s containsString:@"password"] || [s containsString:@"secret"] ||
           [s containsString:@"bearer"] || [s containsString:@"credential"] ||
           [s containsString:@"cookie"];
}

static BOOL spt_i_meth_matches(const char *name) {
    if (!name) return NO;
    NSString *s = [[NSString stringWithUTF8String:name] lowercaseString];
    return [s containsString:@"play"] || [s containsString:@"uri"] ||
           [s containsString:@"url"] || [s containsString:@"context"] ||
           [s containsString:@"option"] || [s containsString:@"origin"] ||
           [s containsString:@"fetch"] || [s containsString:@"subscribe"] ||
           [s containsString:@"load"] || [s containsString:@"enqueue"] ||
           [s containsString:@"shuffle"] || [s containsString:@"command"];
}

void spt_probe_types_run(void) {
    if (!spt_probe_is_enabled()) return;
    dispatch_async(spt_probe_get_queue(), ^{
        SptIBudget budget = {0, 0, NO};
        
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
        
        unsigned int totalClasses = 0;
        Class *classList = objc_copyClassList(&totalClasses);
        NSMutableDictionary<NSString *, NSValue *> *nameToClass = [NSMutableDictionary new];
        
        for (unsigned int i = 0; i < totalClasses; i++) {
            Class c = classList[i];
            if (!c) continue;
            const char *raw = class_getName(c);
            if (!raw) continue;
            NSString *rawStr = [NSString stringWithUTF8String:raw];
            nameToClass[rawStr] = [NSValue valueWithPointer:(__bridge const void *)c];
            
            char *dem = spt_probe_demangle(raw);
            if (dem) {
                NSString *demStr = [NSString stringWithUTF8String:dem];
                nameToClass[demStr] = [NSValue valueWithPointer:(__bridge const void *)c];
                free(dem);
            }
        }
        
        int foundCount = 0;
        int missingCount = 0;
        NSMutableArray<Protocol *> *adoptedProtocols = [NSMutableArray new];
        NSMutableSet<NSString *> *protoNamesSeen = [NSMutableSet new];
        
        for (NSString *tName in targetNames) {
            NSValue *v = nameToClass[tName];
            Class cls = v ? (__bridge Class)[v pointerValue] : Nil;
            if (!cls) {
                // Try fuzzy demangled match
                for (NSString *k in nameToClass) {
                    if ([k hasSuffix:tName] || [k containsString:tName]) {
                        cls = (__bridge Class)[nameToClass[k] pointerValue];
                        break;
                    }
                }
            }
            if (!cls) {
                spt_i_budget_log(&budget, "I: missing %s", tName.UTF8String);
                missingCount++;
                continue;
            }
            foundCount++;
            
            const char *img = class_getImageName(cls);
            const char *slash = img ? strrchr(img, '/') : NULL;
            const char *imgBase = slash ? slash + 1 : (img ? img : "unknown");
            
            // Super chain up to 6
            NSMutableArray<NSString *> *supers = [NSMutableArray new];
            Class curSuper = class_getSuperclass(cls);
            for (int s = 0; s < 6 && curSuper != Nil; s++) {
                const char *sName = class_getName(curSuper);
                if (sName) {
                    char *dem = spt_probe_demangle(sName);
                    [supers addObject:[NSString stringWithUTF8String:dem ? dem : sName]];
                    if (dem) free(dem);
                }
                curSuper = class_getSuperclass(curSuper);
            }
            spt_i_budget_log(&budget, "cls: %s image=%s super=%s",
                             tName.UTF8String, imgBase, [supers componentsJoinedByString:@" -> "].UTF8String);
            
            // Protocols
            unsigned int pCount = 0;
            __unsafe_unretained Protocol **pList = class_copyProtocolList(cls, &pCount);
            NSMutableArray<NSString *> *pNames = [NSMutableArray new];
            if (pList) {
                for (unsigned int p = 0; p < pCount; p++) {
                    const char *pn = protocol_getName(pList[p]);
                    if (pn) {
                        NSString *pStr = [NSString stringWithUTF8String:pn];
                        [pNames addObject:pStr];
                        NSString *lower = [pStr lowercaseString];
                        if ([lower containsString:@"player"] || [lower containsString:@"playback"] ||
                            [lower containsString:@"play"] || [lower containsString:@"collection"] ||
                            [lower containsString:@"playlist"] || [lower containsString:@"dataloader"]) {
                            if (![protoNamesSeen containsObject:pStr] && adoptedProtocols.count < 40) {
                                [protoNamesSeen addObject:pStr];
                                [adoptedProtocols addObject:pList[p]];
                            }
                        }
                    }
                }
                free(pList);
            }
            spt_i_budget_log(&budget, "proto: %s", [pNames componentsJoinedByString:@", "].UTF8String);
            
            // Ivars (cap 60)
            unsigned int iCount = 0;
            Ivar *ivars = class_copyIvarList(cls, &iCount);
            if (ivars) {
                unsigned int loggedIvars = 0;
                for (unsigned int iv = 0; iv < iCount && loggedIvars < 60; iv++) {
                    const char *inm = ivar_getName(ivars[iv]);
                    if (!inm || spt_i_is_sensitive(inm)) continue;
                    const char *ienc = ivar_getTypeEncoding(ivars[iv]) ?: "";
                    ptrdiff_t ioff = ivar_getOffset(ivars[iv]);
                    spt_i_budget_log(&budget, "ivar: %s %s %s off=%td", tName.UTF8String, inm, ienc, ioff);
                    loggedIvars++;
                }
                free(ivars);
            }
            
            // Properties (cap 60)
            unsigned int propCount = 0;
            objc_property_t *props = class_copyPropertyList(cls, &propCount);
            if (props) {
                unsigned int loggedProps = 0;
                for (unsigned int pr = 0; pr < propCount && loggedProps < 60; pr++) {
                    const char *prName = property_getName(props[pr]);
                    if (!prName || spt_i_is_sensitive(prName)) continue;
                    const char *prAttr = property_getAttributes(props[pr]) ?: "";
                    char cutAttr[128];
                    snprintf(cutAttr, sizeof(cutAttr), "%.120s", prAttr);
                    spt_i_budget_log(&budget, "prop: %s %s %s", tName.UTF8String, prName, cutAttr);
                    loggedProps++;
                }
                free(props);
            }
            
            // Methods (cap 80 total per class, instance and class methods prefixed +)
            unsigned int mLogged = 0;
            unsigned int imCount = 0;
            Method *iMethods = class_copyMethodList(cls, &imCount);
            if (iMethods) {
                for (unsigned int m = 0; m < imCount && mLogged < 80; m++) {
                    SEL sel = method_getName(iMethods[m]);
                    const char *sName = sel_getName(sel);
                    if (sName && spt_i_meth_matches(sName)) {
                        const char *menc = method_getTypeEncoding(iMethods[m]) ?: "";
                        char cutEnc[108];
                        snprintf(cutEnc, sizeof(cutEnc), "%.100s", menc);
                        spt_i_budget_log(&budget, "meth: %s %s enc=%s", tName.UTF8String, sName, cutEnc);
                        mLogged++;
                    }
                }
                free(iMethods);
            }
            
            Class meta = object_getClass((id)cls);
            if (meta && meta != cls && mLogged < 80) {
                unsigned int cmCount = 0;
                Method *cMethods = class_copyMethodList(meta, &cmCount);
                if (cMethods) {
                    for (unsigned int m = 0; m < cmCount && mLogged < 80; m++) {
                        SEL sel = method_getName(cMethods[m]);
                        const char *sName = sel_getName(sel);
                        if (sName && spt_i_meth_matches(sName)) {
                            const char *menc = method_getTypeEncoding(cMethods[m]) ?: "";
                            char cutEnc[108];
                            snprintf(cutEnc, sizeof(cutEnc), "%.100s", menc);
                            spt_i_budget_log(&budget, "meth: %s +%s enc=%s", tName.UTF8String, sName, cutEnc);
                            mLogged++;
                        }
                    }
                    free(cMethods);
                }
            }
        }
        
        // 3. Protocols
        const char *(*extTypeFn)(Protocol *, SEL, BOOL, BOOL) =
            (const char *(*)(Protocol *, SEL, BOOL, BOOL))dlsym(RTLD_DEFAULT, "_protocol_getMethodTypeEncoding");
        
        for (Protocol *proto in adoptedProtocols) {
            const char *pName = protocol_getName(proto);
            
            // Required instance methods
            unsigned int rCount = 0;
            struct objc_method_description *rmList = protocol_copyMethodDescriptionList(proto, YES, YES, &rCount);
            if (rmList) {
                for (unsigned int i = 0; i < rCount && i < 40; i++) {
                    SEL sel = rmList[i].name;
                    const char *sName = sel_getName(sel);
                    const char *ext = extTypeFn ? extTypeFn(proto, sel, YES, YES) : NULL;
                    const char *enc = ext ? ext : (rmList[i].types ? rmList[i].types : "none");
                    spt_i_budget_log(&budget, "pmeth: %s %s ext=%s", pName, sName, enc);
                }
                free(rmList);
            }
            
            // Optional instance methods
            unsigned int oCount = 0;
            struct objc_method_description *omList = protocol_copyMethodDescriptionList(proto, NO, YES, &oCount);
            if (omList) {
                for (unsigned int i = 0; i < oCount && i < 40; i++) {
                    SEL sel = omList[i].name;
                    const char *sName = sel_getName(sel);
                    const char *ext = extTypeFn ? extTypeFn(proto, sel, NO, YES) : NULL;
                    const char *enc = ext ? ext : (omList[i].types ? omList[i].types : "none");
                    spt_i_budget_log(&budget, "pmeth: %s %s ext=%s", pName, sName, enc);
                }
                free(omList);
            }
        }
        
        // 4. Related Classes
        spt_i_budget_log(&budget, "--- related classes ---");
        NSArray<NSString *> *relKw = @[
            @"playoptions", @"playorigin", @"playcontext", @"playercontext",
            @"playcommand", @"playeroptions", @"playrequest", @"loggingparams",
            @"espplay", @"espcontext", @"espplayer"
        ];
        NSArray<NSString *> *libKw = @[
            @"rootlist", @"yourlibrary", @"likedsongs", @"collectionplatform"
        ];
        
        int relLogged = 0;
        int libLogged = 0;
        NSMutableArray<NSString *> *libLines = [NSMutableArray new];
        
        for (unsigned int i = 0; i < totalClasses; i++) {
            Class c = classList[i];
            if (!c) continue;
            const char *img = class_getImageName(c);
            if (img && (strncmp(img, "/System/", 8) == 0 || strncmp(img, "/usr/lib/", 9) == 0)) {
                continue;
            }
            const char *raw = class_getName(c);
            if (!raw) continue;
            char *dem = spt_probe_demangle(raw);
            const char *useName = dem ? dem : raw;
            NSString *nsName = [NSString stringWithUTF8String:useName];
            NSString *lower = [nsName lowercaseString];
            
            if (relLogged < 60) {
                BOOL matchesRel = NO;
                for (NSString *kw in relKw) {
                    if ([lower containsString:kw]) { matchesRel = YES; break; }
                }
                if (matchesRel) {
                    Class sCls = class_getSuperclass(c);
                    const char *sRaw = sCls ? class_getName(sCls) : "nil";
                    char *sDem = sCls ? spt_probe_demangle(sRaw) : NULL;
                    NSString *superName = [NSString stringWithUTF8String:sDem ? sDem : sRaw];
                    if (sDem) free(sDem);
                    
                    NSMutableArray<NSString *> *ivarNames = [NSMutableArray new];
                    unsigned int ic = 0;
                    Ivar *ivs = class_copyIvarList(c, &ic);
                    if (ivs) {
                        for (unsigned int iv = 0; iv < ic; iv++) {
                            const char *inm = ivar_getName(ivs[iv]);
                            if (inm && !spt_i_is_sensitive(inm)) {
                                [ivarNames addObject:[NSString stringWithUTF8String:inm]];
                            }
                        }
                        free(ivs);
                    }
                    NSString *ivarsJoined = [ivarNames componentsJoinedByString:@", "];
                    char cutIvars[168];
                    snprintf(cutIvars, sizeof(cutIvars), "%.160s", ivarsJoined.UTF8String);
                    spt_i_budget_log(&budget, "rel: %s super=%s ivars=%s", nsName.UTF8String, superName.UTF8String, cutIvars);
                    relLogged++;
                }
            }
            
            if (libLogged < 80) {
                BOOL matchesLib = NO;
                for (NSString *kw in libKw) {
                    if ([lower containsString:kw]) { matchesLib = YES; break; }
                }
                if (matchesLib) {
                    const char *slash = img ? strrchr(img, '/') : NULL;
                    const char *imgBase = slash ? slash + 1 : (img ? img : "unknown");
                    [libLines addObject:[NSString stringWithFormat:@"lib: %s (%s)", nsName.UTF8String, imgBase]];
                    libLogged++;
                }
            }
            
            if (dem) free(dem);
            if (relLogged >= 60 && libLogged >= 80) break;
        }
        
        for (NSString *ll in libLines) {
            spt_i_budget_log(&budget, "%s", ll.UTF8String);
        }
        
        free(classList);
        
        // 5. Summary LAST
        spt_probe_log("I", "--- I summary --- targets_found=%d targets_missing=%d", foundCount, missingCount);
    });
}

#endif
