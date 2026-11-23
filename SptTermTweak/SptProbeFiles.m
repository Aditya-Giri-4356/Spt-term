#import "SptProbe.h"

#if SPT_PROBE

#import <sys/stat.h>
#import <dirent.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

static int s_loggedFiles = 0;

typedef struct {
    char path[PATH_MAX];
    off_t size;
} SptFileRecord;

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

static void spt_probe_walk_directory(const char *dirPath,
                                     int currentDepth,
                                     int *visitedFiles,
                                     int *skippedDirs,
                                     SptFileRecord topFiles[20],
                                     int *topCount,
                                     size_t homeLen) {
    if (*visitedFiles >= 20000) {
        return;
    }
    if (currentDepth > 5) {
        (*skippedDirs)++;
        return;
    }
    DIR *dir = opendir(dirPath);
    if (!dir) {
        return;
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
            spt_probe_walk_directory(subPath, currentDepth + 1, visitedFiles, skippedDirs, topFiles, topCount, homeLen);
        } else if (S_ISREG(st.st_mode)) {
            (*visitedFiles)++;
            const char *relPath = (strlen(subPath) > homeLen) ? (subPath + homeLen + 1) : subPath;
            
            spt_probe_track_top_file(topFiles, topCount, relPath, st.st_size);
            
            if (st.st_size >= 64 * 1024 && s_loggedFiles < 3000) {
                s_loggedFiles++;
                spt_probe_log("D", "file %s size=%lld mtime=%ld",
                              relPath, (long long)st.st_size, (long)st.st_mtime);
            }
            
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
                }
            }
        }
    }
    closedir(dir);
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
        s_loggedFiles = 0;
        spt_probe_log("D", "Starting sandbox walk from: %s", home);
        
        int visitedFiles = 0;
        int skippedDirs = 0;
        SptFileRecord topFiles[20];
        memset(topFiles, 0, sizeof(topFiles));
        int topCount = 0;
        size_t homeLen = strlen(home);
        
        spt_probe_walk_directory(home, 1, &visitedFiles, &skippedDirs, topFiles, &topCount, homeLen);
        
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
    });
}

#endif
