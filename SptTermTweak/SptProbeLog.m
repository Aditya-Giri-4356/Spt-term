#import "SptProbe.h"

#if SPT_PROBE

#import <UIKit/UIKit.h>
#import <os/lock.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <sys/stat.h>
#import <dlfcn.h>
#import <pthread.h>

extern void spt_probe_swift_install(void);

static NSString * const kSptProbeEnabledKey = @"probe.enabled";
static os_unfair_lock s_logLock = OS_UNFAIR_LOCK_INIT;
static FILE *s_logFile = NULL;
static dispatch_queue_t s_probeQueue = NULL;
static char s_logPath[PATH_MAX] = {0};
static char s_redactedLogPath[PATH_MAX] = {0};

void spt_probe_log_str(const char *section, const char *message) {
    spt_probe_log(section, "%s", message ? message : "");
}

static void spt_probe_ensure_paths(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *home = NSHomeDirectory();
        NSString *dir = [home stringByAppendingPathComponent:@"Documents/SptTerm"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        
        NSString *logFile = [dir stringByAppendingPathComponent:@"probe.log"];
        NSString *redactedFile = [dir stringByAppendingPathComponent:@"probe-redacted.log"];
        
        [logFile getFileSystemRepresentation:s_logPath maxLength:sizeof(s_logPath)];
        [redactedFile getFileSystemRepresentation:s_redactedLogPath maxLength:sizeof(s_redactedLogPath)];
        
        dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        s_probeQueue = dispatch_queue_create("com.sptterm.probe.serial", qos);
    });
}

BOOL spt_probe_is_enabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSptProbeEnabledKey];
}

void spt_probe_set_enabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kSptProbeEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

const char *spt_probe_get_log_path(void) {
    spt_probe_ensure_paths();
    return s_logPath;
}

const char *spt_probe_get_redacted_log_path(void) {
    spt_probe_ensure_paths();
    return s_redactedLogPath;
}

dispatch_queue_t spt_probe_get_queue(void) {
    spt_probe_ensure_paths();
    return s_probeQueue;
}

char *spt_probe_demangle(const char *mangled) {
    if (!mangled || mangled[0] == '\0') {
        return NULL;
    }
    typedef char *(*DemangleFn)(const char *, size_t, char *, size_t *, uint32_t);
    static DemangleFn s_demangle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_demangle = (DemangleFn)dlsym(RTLD_DEFAULT, "swift_demangle");
    });
    if (s_demangle) {
        size_t outLen = 0;
        char *res = s_demangle(mangled, strlen(mangled), NULL, &outLen, 0);
        if (res) {
            return res;
        }
    }
    return strdup(mangled);
}

static void spt_probe_rotate_if_needed(size_t incomingBytes) {
    if (s_logPath[0] == '\0') {
        return;
    }
    struct stat st;
    if (stat(s_logPath, &st) == 0) {
        if ((size_t)st.st_size + incomingBytes >= (8 * 1024 * 1024)) {
            if (s_logFile) {
                fclose(s_logFile);
                s_logFile = NULL;
            }
            char rotatePath[PATH_MAX];
            snprintf(rotatePath, sizeof(rotatePath), "%s.1", s_logPath);
            unlink(rotatePath);
            rename(s_logPath, rotatePath);
        }
    }
}

void spt_probe_log(const char *section, const char *fmt, ...) {
    if (!spt_probe_is_enabled()) {
        return;
    }
    spt_probe_ensure_paths();
    
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm tm_info;
    gmtime_r(&tv.tv_sec, &tm_info);
    
    char timeBuf[32];
    strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%dT%H:%M:%S", &tm_info);
    int millis = (int)(tv.tv_usec / 1000);
    
    char msgBuf[3584];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msgBuf, sizeof(msgBuf), fmt, args);
    va_end(args);
    
    char lineBuf[4096];
    int len = snprintf(lineBuf, sizeof(lineBuf), "%s.%03dZ [%s] %s\n",
                       timeBuf, millis, section ? section : "SYS", msgBuf);
    if (len < 0) {
        return;
    }
    if ((size_t)len >= sizeof(lineBuf)) {
        lineBuf[sizeof(lineBuf) - 2] = '\n';
        lineBuf[sizeof(lineBuf) - 1] = '\0';
        len = (int)sizeof(lineBuf) - 1;
    }
    
    os_unfair_lock_lock(&s_logLock);
    spt_probe_rotate_if_needed((size_t)len);
    if (!s_logFile) {
        s_logFile = fopen(s_logPath, "a");
    }
    if (s_logFile) {
        fputs(lineBuf, s_logFile);
        fflush(s_logFile);
    }
    os_unfair_lock_unlock(&s_logLock);
}

void spt_probe_wipe_log(void) {
    spt_probe_ensure_paths();
    os_unfair_lock_lock(&s_logLock);
    if (s_logFile) {
        fclose(s_logFile);
        s_logFile = NULL;
    }
    unlink(s_logPath);
    char rotatePath[PATH_MAX];
    snprintf(rotatePath, sizeof(rotatePath), "%s.1", s_logPath);
    unlink(rotatePath);
    os_unfair_lock_unlock(&s_logLock);
}

void spt_probe_export_redacted_log(void) {
    if (!spt_probe_is_enabled()) {
        return;
    }
    spt_probe_ensure_paths();
    dispatch_async(spt_probe_get_queue(), ^{
        os_unfair_lock_lock(&s_logLock);
        if (s_logFile) {
            fflush(s_logFile);
        }
        NSString *inPath = [NSString stringWithUTF8String:s_logPath];
        NSString *olderPath = [inPath stringByAppendingString:@".1"];
        NSData *older = [NSData dataWithContentsOfFile:olderPath];
        NSData *current = [NSData dataWithContentsOfFile:inPath];
        os_unfair_lock_unlock(&s_logLock);
        NSMutableData *raw = [NSMutableData data];
        if (older) { [raw appendData:older]; }
        if (current) { [raw appendData:current]; }
        if (raw.length == 0) {
            return;
        }
        NSString *content = [[NSString alloc] initWithData:raw
                                                  encoding:NSUTF8StringEncoding];
        if (!content) {
            content = [[NSString alloc] initWithData:raw
                                            encoding:NSISOLatin1StringEncoding];
        }
        if (!content) {
            return;
        }
        NSMutableString *sanitized = [content mutableCopy];
        NSRegularExpressionOptions opts = NSRegularExpressionCaseInsensitive;
        NSRegularExpression *bearerRegex = [NSRegularExpression
            regularExpressionWithPattern:@"Bearer\\s+[^\\s]+" options:opts error:NULL];
        [bearerRegex replaceMatchesInString:sanitized options:0
                                      range:NSMakeRange(0, sanitized.length)
                               withTemplate:@"Bearer <redacted>"];
        NSRegularExpression *userRegex = [NSRegularExpression
            regularExpressionWithPattern:@"spotify:user:[^\\s\\\"',]+"
                                 options:opts error:NULL];
        [userRegex replaceMatchesInString:sanitized options:0
                                    range:NSMakeRange(0, sanitized.length)
                             withTemplate:@"spotify:user:<redacted>"];
        NSRegularExpression *tokenRegex = [NSRegularExpression
            regularExpressionWithPattern:@"[A-Za-z0-9+/=_-]{24,}"
                                 options:opts error:NULL];
        [tokenRegex replaceMatchesInString:sanitized options:0
                                     range:NSMakeRange(0, sanitized.length)
                              withTemplate:@"<redacted>"];
        NSString *outPath = [NSString stringWithUTF8String:s_redactedLogPath];
        [sanitized writeToFile:outPath atomically:YES
                      encoding:NSUTF8StringEncoding error:NULL];
        spt_probe_log("SYS", "Exported redacted log to %s", s_redactedLogPath);
    });
}

static void spt_probe_log_sys_header(void) {
    static dispatch_once_t s_headerOnce;
    dispatch_once(&s_headerOnce, ^{
        size_t size = 0;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        char *machine = malloc(size);
        if (machine) {
            sysctlbyname("hw.machine", machine, &size, NULL, 0);
        }
        
        NSString *sysVer = [[UIDevice currentDevice] systemVersion];
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *shortVer = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
        NSString *bundleVer = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
        NSString *provPath = [bundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        BOOL hasProv = (provPath != nil);
        
        spt_probe_log("SYS",
                      "iOS=%s model=%s Spotify=%s(%s) dylib_build=%s %s provision=%s",
                      sysVer.UTF8String,
                      machine ? machine : "unknown",
                      shortVer.UTF8String,
                      bundleVer.UTF8String,
                      __DATE__,
                      __TIME__,
                      hasProv ? "YES" : "NO");
        if (machine) {
            free(machine);
        }
    });
}

static void spt_probe_install_all(void) {
    spt_probe_ensure_paths();
    spt_probe_net_install();
    spt_probe_swift_install();
    if (spt_probe_is_enabled()) {
        spt_probe_log_sys_header();
    }
}

int spt_probe_run(const char *experimentId) {
    if (!experimentId) {
        return -1;
    }
    if (!spt_probe_is_enabled()) {
        spt_probe_log("SYS", "Experiment %s ignored: probe is disabled", experimentId);
        return -1;
    }
    spt_probe_log_sys_header();
    
    if (strcmp(experimentId, "A") == 0) {
        spt_probe_classes_run();
        return 0;
    } else if (strcmp(experimentId, "D") == 0) {
        spt_probe_files_run();
        return 0;
    } else if (strcmp(experimentId, "E") == 0) {
        spt_probe_net_run();
        return 0;
    } else if (strcmp(experimentId, "G") == 0) {
        spt_probe_cache_run();
        return 0;
    } else if (strcmp(experimentId, "B") == 0 ||
               strcmp(experimentId, "C") == 0 ||
               strcmp(experimentId, "F") == 0) {
        spt_probe_log(experimentId, "experiment %s not built yet", experimentId);
        return -1;
    }
    return -1;
}

@interface SptProbeBootstrap : NSObject
@end

@implementation SptProbeBootstrap

+ (void)load {
    spt_probe_net_early_install();
    static dispatch_once_t s_initOnce;
    void (^installBlock)(void) = ^{
        dispatch_once(&s_initOnce, ^{
            spt_probe_install_all();
        });
    };
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull __unused note) {
        installBlock();
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        installBlock();
    });
}

@end

#endif
