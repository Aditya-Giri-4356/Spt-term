#ifndef SPT_PROBE_H
#define SPT_PROBE_H

#import <Foundation/Foundation.h>
#import <os/lock.h>

#ifndef SPT_PROBE
#define SPT_PROBE 0
#endif

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

#if SPT_PROBE

BOOL spt_probe_is_enabled(void);
void spt_probe_set_enabled(BOOL enabled);
const char *_Nullable spt_probe_get_log_path(void);
const char *_Nullable spt_probe_get_redacted_log_path(void);
dispatch_queue_t spt_probe_get_queue(void);
char *_Nullable spt_probe_demangle(const char *_Nullable mangled);

void spt_probe_log(const char *section, const char *fmt, ...)
    __attribute__((format(printf, 2, 3)))
    NS_SWIFT_UNAVAILABLE("variadic: use spt_probe_log_str from Swift");
void spt_probe_log_str(const char *section, const char *message);

void spt_probe_wipe_log(void);
void spt_probe_export_redacted_log(void);

int spt_probe_run(const char *experimentId);
void spt_probe_files_run(void);
void spt_probe_net_run(void);
void spt_probe_cache_run(void);
void spt_probe_classes_run(void);
void spt_probe_net_install(void);
void spt_probe_net_early_install(void);
NSString *spt_probe_norm_path(NSString * _Nullable path);

#else

static inline BOOL spt_probe_is_enabled(void) { return NO; }
static inline void spt_probe_set_enabled(BOOL enabled) { (void)enabled; }
static inline const char *_Nullable spt_probe_get_log_path(void) { return NULL; }
static inline const char *_Nullable spt_probe_get_redacted_log_path(void) { return NULL; }
static inline dispatch_queue_t spt_probe_get_queue(void) { return dispatch_get_main_queue(); }
static inline char *_Nullable spt_probe_demangle(const char *_Nullable m) { (void)m; return NULL; }
static inline void spt_probe_log_str(const char *section, const char *message) {
    (void)section; (void)message;
}
static inline void spt_probe_wipe_log(void) {}
static inline void spt_probe_export_redacted_log(void) {}
static inline int spt_probe_run(const char *experimentId) { (void)experimentId; return -1; }
static inline void spt_probe_cache_run(void) {}
static inline void spt_probe_classes_run(void) {}
static inline void spt_probe_net_early_install(void) {}
static inline NSString *spt_probe_norm_path(NSString * _Nullable path) { return path ?: @"/"; }

#endif

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#endif
