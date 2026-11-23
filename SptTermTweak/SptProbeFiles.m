#import "SptProbe.h"

#if SPT_PROBE

#import <sys/stat.h>
#import <dirent.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <dlfcn.h>
#import <sqlite3.h>

@interface SptDirStat : NSObject
@property (nonatomic, copy) NSString *relPath;
@property (nonatomic, assign) int files;
@property (nonatomic, assign) off_t bytes;
@end

@implementation SptDirStat
@end

typedef struct {
    char path[PATH_MAX];
    off_t size;
} SptFileRecord;

typedef struct {
    char fullPath[PATH_MAX];
    char relPath[PATH_MAX];
    off_t size;
} SptSqliteFileInfo;

typedef struct {
    int files;
    off_t bytes;
} SptDirAccum;

static void *s_sqliteHandle = NULL;
static __typeof__(&sqlite3_open_v2) s_sqlite3_open_v2 = NULL;
static __typeof__(&sqlite3_close) s_sqlite3_close = NULL;
static __typeof__(&sqlite3_prepare_v2) s_sqlite3_prepare_v2 = NULL;
static __typeof__(&sqlite3_step) s_sqlite3_step = NULL;
static __typeof__(&sqlite3_column_text) s_sqlite3_column_text = NULL;
static __typeof__(&sqlite3_column_int64) s_sqlite3_column_int64 = NULL;
static __typeof__(&sqlite3_column_count) s_sqlite3_column_count = NULL;
static __typeof__(&sqlite3_column_name) s_sqlite3_column_name = NULL;
static __typeof__(&sqlite3_finalize) s_sqlite3_finalize = NULL;

static BOOL spt_probe_init_sqlite(void) {
    static dispatch_once_t once;
    static BOOL s_ok = NO;
    dispatch_once(&once, ^{
        s_sqliteHandle = dlopen("/usr/lib/libsqlite3.dylib", RTLD_NOW);
        if (!s_sqliteHandle) {
            return;
        }
        #define LOAD_SYM(name) s_##name = (__typeof__(&name))dlsym(s_sqliteHandle, #name); if (!s_##name) return;
        LOAD_SYM(sqlite3_open_v2);
        LOAD_SYM(sqlite3_close);
        LOAD_SYM(sqlite3_prepare_v2);
        LOAD_SYM(sqlite3_step);
        LOAD_SYM(sqlite3_column_text);
        LOAD_SYM(sqlite3_column_int64);
        LOAD_SYM(sqlite3_column_count);
        LOAD_SYM(sqlite3_column_name);
        LOAD_SYM(sqlite3_finalize);
        #undef LOAD_SYM
        s_ok = YES;
    });
    return s_ok;
}

static BOOL spt_should_skip_file_print(const char *relPath) {
    if (!relPath) return YES;
    if (strncmp(relPath, "Library/Caches/VolatileCache", 28) == 0) return YES;
    if (strncmp(relPath, "Library/Caches/Canvases", 23) == 0) return YES;
    if (strncmp(relPath, "Library/Caches/com.spotify.feature.video", 40) == 0) return YES;
    if (strncmp(relPath, "Library/Caches/com.spotify.persistent.image.cache", 49) == 0) return YES;
    if (strncmp(relPath, "Library/Caches/com.apple.", 25) == 0) return YES;
    if (strncmp(relPath, "Library/WebKit", 14) == 0) return YES;
    if (strncmp(relPath, "Library/SplashBoard", 19) == 0) return YES;
    return NO;
}

static void spt_probe_track_top_file(SptFileRecord topFiles[20], int *topCount, const char *path, off_t size) {
    int idx = -1;
    if (*topCount < 20) {
        idx = *topCount;
        (*topCount)++;
    } else if (size > topFiles[19].size) {
        idx = 19;
    }
    if (idx >= 0) {
        strncpy(topFiles[idx].path, path, sizeof(topFiles[idx].path) - 1);
        topFiles[idx].path[sizeof(topFiles[idx].path) - 1] = '\0';
        topFiles[idx].size = size;
        for (int i = idx; i > 0; i--) {
            if (topFiles[i].size > topFiles[i - 1].size) {
                SptFileRecord temp = topFiles[i];
                topFiles[i] = topFiles[i - 1];
                topFiles[i - 1] = temp;
            } else {
                break;
            }
        }
    }
}

static SptDirAccum spt_probe_walk_directory(const char *dirPath,
                                            int currentDepth,
                                            int *visitedFiles,
                                            int *skippedDirs,
                                            int *printedFiles,
                                            int *overflowFiles,
                                            SptFileRecord topFiles[20],
                                            int *topCount,
                                            size_t homeLen,
                                            NSMutableArray<SptDirStat *> *dirStats,
                                            int *bLt1K,
                                            int *bLt16K,
                                            int *bLt256K,
                                            int *bGe256K,
                                            NSMutableArray<NSString *> *persistentCacheSamples,
                                            NSMutableDictionary<NSString *, NSNumber *> *extCounts,
                                            SptSqliteFileInfo sqliteFiles[12],
                                            int *sqliteCount) {
    SptDirAccum myAccum = {0, 0};
    if (*visitedFiles >= 20000) {
        return myAccum;
    }
    if (currentDepth > 8) {
        (*skippedDirs)++;
        return myAccum;
    }
    DIR *dir = opendir(dirPath);
    if (!dir) {
        return myAccum;
    }
    struct dirent *entry;
    while ((*visitedFiles < 20000) && (entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char subPath[PATH_MAX];
        snprintf(subPath, sizeof(subPath), "%s/%s", dirPath, entry->d_name);
        
        if (strstr(subPath, "/Documents/SptTerm") != NULL) {
            continue;
        }
        
        struct stat st;
        if (lstat(subPath, &st) != 0) {
            continue;
        }
        if (S_ISLNK(st.st_mode)) {
            continue;
        }
        
        if (S_ISDIR(st.st_mode)) {
            SptDirAccum subAccum = spt_probe_walk_directory(subPath,
                                                           currentDepth + 1,
                                                           visitedFiles,
                                                           skippedDirs,
                                                           printedFiles,
                                                           overflowFiles,
                                                           topFiles,
                                                           topCount,
                                                           homeLen,
                                                           dirStats,
                                                           bLt1K,
                                                           bLt16K,
                                                           bLt256K,
                                                           bGe256K,
                                                           persistentCacheSamples,
                                                           extCounts,
                                                           sqliteFiles,
                                                           sqliteCount);
            myAccum.files += subAccum.files;
            myAccum.bytes += subAccum.bytes;
        } else if (S_ISREG(st.st_mode)) {
            (*visitedFiles)++;
            myAccum.files += 1;
            myAccum.bytes += st.st_size;
            
            const char *relPath = (strlen(subPath) > homeLen) ? (subPath + homeLen + 1) : subPath;
            spt_probe_track_top_file(topFiles, topCount, relPath, st.st_size);
            
            if (st.st_size >= 64 * 1024 && !spt_should_skip_file_print(relPath)) {
                if (*printedFiles < 100) {
                    (*printedFiles)++;
                    spt_probe_log("D", "file %s size=%lld mtime=%ld",
                                  relPath, (long long)st.st_size, (long)st.st_mtime);
                } else {
                    (*overflowFiles)++;
                }
            }
            
            if (strncmp(relPath, "Library/Application Support", 27) == 0) {
                if (st.st_size < 1024) {
                    (*bLt1K)++;
                } else if (st.st_size < 16 * 1024) {
                    (*bLt16K)++;
                } else if (st.st_size < 256 * 1024) {
                    (*bLt256K)++;
                } else {
                    (*bGe256K)++;
                }
                if (strncmp(relPath, "Library/Application Support/PersistentCache", 43) == 0) {
                    if (persistentCacheSamples.count < 15) {
                        [persistentCacheSamples addObject:[NSString stringWithFormat:@"%s (%lld bytes)", relPath, (long long)st.st_size]];
                    }
                }
            }
            
            const char *dot = strrchr(entry->d_name, '.');
            NSString *ext = (dot && dot != entry->d_name) ? [[NSString stringWithUTF8String:dot] lowercaseString] : @"(no extension)";
            extCounts[ext] = @(extCounts[ext].integerValue + 1);
            
            int fd = open(subPath, O_RDONLY);
            if (fd >= 0) {
                char header[16];
                ssize_t bytesRead = read(fd, header, 16);
                close(fd);
                if (bytesRead == 16 && memcmp(header, "SQLite format 3\0", 16) == 0) {
                    char walPath[PATH_MAX];
                    char shmPath[PATH_MAX];
                    snprintf(walPath, sizeof(walPath), "%s-wal", subPath);
                    snprintf(shmPath, sizeof(shmPath), "%s-shm", subPath);
                    
                    struct stat stWal, stShm;
                    BOOL hasWal = (lstat(walPath, &stWal) == 0 && S_ISREG(stWal.st_mode));
                    BOOL hasShm = (lstat(shmPath, &stShm) == 0 && S_ISREG(stShm.st_mode));
                    
                    spt_probe_log("D",
                                  "SQLite: %s (size=%lld, mtime=%ld, wal=%s[%lld], shm=%s[%lld])",
                                  relPath,
                                  (long long)st.st_size,
                                  (long)st.st_mtime,
                                  hasWal ? "YES" : "NO",
                                  (long long)(hasWal ? stWal.st_size : 0),
                                  hasShm ? "YES" : "NO",
                                  (long long)(hasShm ? stShm.st_size : 0));
                    
                    if (*sqliteCount < 12 && st.st_size <= 64 * 1024 * 1024) {
                        strncpy(sqliteFiles[*sqliteCount].fullPath, subPath, sizeof(sqliteFiles[*sqliteCount].fullPath) - 1);
                        sqliteFiles[*sqliteCount].fullPath[sizeof(sqliteFiles[*sqliteCount].fullPath) - 1] = '\0';
                        strncpy(sqliteFiles[*sqliteCount].relPath, relPath, sizeof(sqliteFiles[*sqliteCount].relPath) - 1);
                        sqliteFiles[*sqliteCount].relPath[sizeof(sqliteFiles[*sqliteCount].relPath) - 1] = '\0';
                        sqliteFiles[*sqliteCount].size = st.st_size;
                        (*sqliteCount)++;
                    }
                }
            }
        }
    }
    closedir(dir);
    
    if (strlen(dirPath) > homeLen) {
        const char *dirRel = dirPath + homeLen + 1;
        int slashes = 0;
        for (const char *p = dirRel; *p; p++) {
            if (*p == '/') slashes++;
        }
        if (slashes <= 2) {
            SptDirStat *ds = [SptDirStat new];
            ds.relPath = [NSString stringWithUTF8String:dirRel];
            ds.files = myAccum.files;
            ds.bytes = myAccum.bytes;
            [dirStats addObject:ds];
        }
    }
    
    return myAccum;
}

void spt_probe_files_run(void) {
    if (!spt_probe_is_enabled()) {
        return;
    }
    dispatch_async(spt_probe_get_queue(), ^{
        const char *home = [NSHomeDirectory() fileSystemRepresentation];
        if (!home) {
            return;
        }
        spt_probe_log("D", "Starting sandbox walk from: %s", home);
        
        int visitedFiles = 0;
        int skippedDirs = 0;
        int printedFiles = 0;
        int overflowFiles = 0;
        SptFileRecord topFiles[20];
        memset(topFiles, 0, sizeof(topFiles));
        int topCount = 0;
        size_t homeLen = strlen(home);
        
        NSMutableArray<SptDirStat *> *dirStats = [NSMutableArray new];
        int bLt1K = 0, bLt16K = 0, bLt256K = 0, bGe256K = 0;
        NSMutableArray<NSString *> *persistentCacheSamples = [NSMutableArray new];
        NSMutableDictionary<NSString *, NSNumber *> *extCounts = [NSMutableDictionary new];
        SptSqliteFileInfo sqliteFiles[12];
        memset(sqliteFiles, 0, sizeof(sqliteFiles));
        int sqliteCount = 0;
        
        spt_probe_walk_directory(home, 1, &visitedFiles, &skippedDirs, &printedFiles, &overflowFiles, topFiles, &topCount, homeLen, dirStats, &bLt1K, &bLt16K, &bLt256K, &bGe256K, persistentCacheSamples, extCounts, sqliteFiles, &sqliteCount);
        
        if (overflowFiles > 0) {
            spt_probe_log("D", "file ... %d more", overflowFiles);
        }
        
        spt_probe_log("D",
                      "Sandbox walk complete: visited=%d files (cap 20000 reached=%s), skipped_dirs_depth=%d",
                      visitedFiles,
                      (visitedFiles >= 20000) ? "YES" : "NO",
                      skippedDirs);
        
        spt_probe_log("D", "Top %d largest regular files:", topCount);
        for (int i = 0; i < topCount; i++) {
            spt_probe_log("D", "  #%02d: %s (%lld bytes)",
                          i + 1, topFiles[i].path, (long long)topFiles[i].size);
        }
        
        [dirStats sortUsingComparator:^NSComparisonResult(SptDirStat *a, SptDirStat *b) {
            if (a.bytes > b.bytes) return NSOrderedAscending;
            if (a.bytes < b.bytes) return NSOrderedDescending;
            return [a.relPath compare:b.relPath];
        }];
        
        spt_probe_log("D", "--- dir summary (depth<=3, top 40 by bytes) ---");
        int dirLimit = MIN((int)dirStats.count, 40);
        for (int i = 0; i < dirLimit; i++) {
            SptDirStat *ds = dirStats[i];
            spt_probe_log("D", "%s files=%d bytes=%lld", ds.relPath.UTF8String, ds.files, (long long)ds.bytes);
        }
        
        spt_probe_log("D", "--- Application Support size buckets ---");
        spt_probe_log("D", "<1KB=%d <16KB=%d <256KB=%d >=256KB=%d", bLt1K, bLt16K, bLt256K, bGe256K);
        spt_probe_log("D", "PersistentCache samples (cap 15):");
        for (NSString *sample in persistentCacheSamples) {
            spt_probe_log("D", "  %s", sample.UTF8String);
        }
        
        NSArray<NSString *> *sortedExts = [extCounts.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSInteger ca = [extCounts[a] integerValue];
            NSInteger cb = [extCounts[b] integerValue];
            if (ca > cb) return NSOrderedAscending;
            if (ca < cb) return NSOrderedDescending;
            return [a compare:b];
        }];
        
        spt_probe_log("D", "--- extensions (top 15) ---");
        int extLimit = MIN((int)sortedExts.count, 15);
        for (int i = 0; i < extLimit; i++) {
            NSString *e = sortedExts[i];
            spt_probe_log("D", "%s: %ld", e.UTF8String, (long)[extCounts[e] integerValue]);
        }
        
        spt_probe_log("D", "--- sqlite schema ---");
        if (!spt_probe_init_sqlite()) {
            spt_probe_log("D", "sqlite unavailable");
            return;
        }
        
        for (int idx = 0; idx < sqliteCount; idx++) {
            SptSqliteFileInfo *info = &sqliteFiles[idx];
            NSString *srcPath = [NSString stringWithUTF8String:info->fullPath];
            NSString *relPathStr = [NSString stringWithUTF8String:info->relPath];
            NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"spt-probe-sql/%d", idx]];
            
            [[NSFileManager defaultManager] removeItemAtPath:tmpDir error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:NULL];
            
            NSString *destPath = [tmpDir stringByAppendingPathComponent:[srcPath lastPathComponent]];
            NSError *cpErr = nil;
            if (![[NSFileManager defaultManager] copyItemAtPath:srcPath toPath:destPath error:&cpErr]) {
                spt_probe_log("D", "schema: %s error=%d", info->relPath, (int)(cpErr ? cpErr.code : -1));
                [[NSFileManager defaultManager] removeItemAtPath:tmpDir error:NULL];
                continue;
            }
            
            NSString *srcWal = [srcPath stringByAppendingString:@"-wal"];
            NSString *srcShm = [srcPath stringByAppendingString:@"-shm"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:srcWal]) {
                [[NSFileManager defaultManager] copyItemAtPath:srcWal toPath:[destPath stringByAppendingString:@"-wal"] error:NULL];
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:srcShm]) {
                [[NSFileManager defaultManager] copyItemAtPath:srcShm toPath:[destPath stringByAppendingString:@"-shm"] error:NULL];
            }
            
            sqlite3 *db = NULL;
            int rc = s_sqlite3_open_v2(destPath.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL);
            if (rc != SQLITE_OK) {
                spt_probe_log("D", "schema: %s error=%d", info->relPath, rc);
                if (db) { s_sqlite3_close(db); }
                [[NSFileManager defaultManager] removeItemAtPath:tmpDir error:NULL];
                continue;
            }
            
            const char *masterSql = "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name;";
            sqlite3_stmt *stmt = NULL;
            rc = s_sqlite3_prepare_v2(db, masterSql, -1, &stmt, NULL);
            if (rc != SQLITE_OK) {
                spt_probe_log("D", "schema: %s error=%d", info->relPath, rc);
                s_sqlite3_close(db);
                [[NSFileManager defaultManager] removeItemAtPath:tmpDir error:NULL];
                continue;
            }
            
            NSMutableArray<NSString *> *tableNames = [NSMutableArray new];
            while (s_sqlite3_step(stmt) == SQLITE_ROW) {
                const unsigned char *tName = s_sqlite3_column_text(stmt, 0);
                if (tName) {
                    [tableNames addObject:[NSString stringWithUTF8String:(const char *)tName]];
                }
            }
            s_sqlite3_finalize(stmt);
            
            int tableLimit = MIN((int)tableNames.count, 60);
            for (int t = 0; t < tableLimit; t++) {
                NSString *tName = tableNames[t];
                NSString *quoteChar = [NSString stringWithCharacters:(const unichar[]){34} length:1];
                NSString *escaped = [tName stringByReplacingOccurrencesOfString:quoteChar withString:@"\"\""];
                
                int64_t rowCount = -1;
                NSString *countSql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM \"%@\";", escaped];
                sqlite3_stmt *cStmt = NULL;
                if (s_sqlite3_prepare_v2(db, countSql.UTF8String, -1, &cStmt, NULL) == SQLITE_OK) {
                    if (s_sqlite3_step(cStmt) == SQLITE_ROW) {
                        rowCount = s_sqlite3_column_int64(cStmt, 0);
                    }
                    s_sqlite3_finalize(cStmt);
                }
                
                NSString *colSql = [NSString stringWithFormat:@"SELECT * FROM \"%@\" LIMIT 0;", escaped];
                sqlite3_stmt *colStmt = NULL;
                NSMutableArray<NSString *> *colNames = [NSMutableArray new];
                if (s_sqlite3_prepare_v2(db, colSql.UTF8String, -1, &colStmt, NULL) == SQLITE_OK) {
                    int nCols = s_sqlite3_column_count(colStmt);
                    int capC = MIN(nCols, 20);
                    for (int c = 0; c < capC; c++) {
                        const char *cn = s_sqlite3_column_name(colStmt, c);
                        if (cn) {
                            [colNames addObject:[NSString stringWithUTF8String:cn]];
                        }
                    }
                    s_sqlite3_finalize(colStmt);
                }
                
                NSString *colsStr = [colNames componentsJoinedByString:@", "];
                spt_probe_log("D", "schema: %s table=%s rows=%lld cols=%s",
                              info->relPath, tName.UTF8String, (long long)rowCount, colsStr.UTF8String);
            }
            
            NSString *lowerRel = [relPathStr lowercaseString];
            if ([lowerRel containsString:@"cache.db"]) {
                spt_probe_log("D", "--- Cache.db url histogram ---");
                const char *cacheSql = "SELECT request_key FROM cfurl_cache_response LIMIT 20000;";
                sqlite3_stmt *cacheStmt = NULL;
                int cacheRc = s_sqlite3_prepare_v2(db, cacheSql, -1, &cacheStmt, NULL);
                if (cacheRc != SQLITE_OK) {
                    NSString *allTables = [tableNames componentsJoinedByString:@", "];
                    spt_probe_log("D", "Cache.db cfurl_cache_response missing. Tables: %s", allTables.UTF8String);
                } else {
                    int totalRows = 0;
                    NSMutableDictionary<NSString *, NSNumber *> *cacheUrlCounts = [NSMutableDictionary new];
                    while (s_sqlite3_step(cacheStmt) == SQLITE_ROW) {
                        totalRows++;
                        const unsigned char *txt = s_sqlite3_column_text(cacheStmt, 0);
                        if (txt) {
                            NSString *rawUrl = [NSString stringWithUTF8String:(const char *)txt];
                            NSURL *u = [NSURL URLWithString:rawUrl];
                            if (u) {
                                NSString *host = u.host ?: @"unknown-host";
                                NSString *norm = spt_probe_norm_path(u.path ?: @"/");
                                NSString *key = [NSString stringWithFormat:@"%@ %@", host, norm];
                                cacheUrlCounts[key] = @(cacheUrlCounts[key].integerValue + 1);
                            }
                        }
                    }
                    s_sqlite3_finalize(cacheStmt);
                    spt_probe_log("D", "Cache.db total rows=%d", totalRows);
                    
                    NSArray<NSString *> *sortedKeys = [cacheUrlCounts.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *k1, NSString *k2) {
                        NSInteger c1 = [cacheUrlCounts[k1] integerValue];
                        NSInteger c2 = [cacheUrlCounts[k2] integerValue];
                        if (c1 > c2) return NSOrderedAscending;
                        if (c1 < c2) return NSOrderedDescending;
                        return [k1 compare:k2];
                    }];
                    
                    int topK = MIN((int)sortedKeys.count, 60);
                    for (int k = 0; k < topK; k++) {
                        NSString *key = sortedKeys[k];
                        spt_probe_log("D", "%ld %s", (long)[cacheUrlCounts[key] integerValue], key.UTF8String);
                    }
                }
            }
            
            s_sqlite3_close(db);
            [[NSFileManager defaultManager] removeItemAtPath:tmpDir error:NULL];
        }
    });
}

#endif
