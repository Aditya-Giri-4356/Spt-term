#import "SptProbe.h"

#if SPT_PROBE

#import <sys/stat.h>
#import <dirent.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

typedef struct {
    uint64_t offset;
    uint64_t size;
} SptGBlockHandle;

typedef struct {
    char relPath[PATH_MAX];
    off_t size;
} SptGFileEntry;

static off_t s_gTotalBytesRead = 0;

static NSString *spt_g_redact_path(NSString *path) {
    if (!path || path.length == 0) return @"";
    NSMutableString *s = [path mutableCopy];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(Users/)[^/]+"
                                                                        options:0
                                                                          error:NULL];
    [re replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1<uid>"];
    return s;
}

static ssize_t spt_g_pread(int fd, void *buf, size_t nbyte, off_t offset) {
    if (s_gTotalBytesRead + (off_t)nbyte > 200 * 1024 * 1024) {
        return -1;
    }
    ssize_t r = pread(fd, buf, nbyte, offset);
    if (r > 0) {
        s_gTotalBytesRead += r;
    }
    return r;
}

static int spt_g_decode_varint32(const uint8_t *src, size_t maxLen, uint32_t *val) {
    uint32_t res = 0;
    int shift = 0;
    for (size_t i = 0; i < maxLen && i < 5; i++) {
        uint8_t b = src[i];
        res |= ((uint32_t)(b & 0x7F)) << shift;
        if ((b & 0x80) == 0) {
            *val = res;
            return (int)(i + 1);
        }
        shift += 7;
    }
    return -1;
}

static int spt_g_decode_varint64(const uint8_t *src, size_t maxLen, uint64_t *val) {
    uint64_t res = 0;
    int shift = 0;
    for (size_t i = 0; i < maxLen && i < 10; i++) {
        uint8_t b = src[i];
        res |= ((uint64_t)(b & 0x7F)) << shift;
        if ((b & 0x80) == 0) {
            *val = res;
            return (int)(i + 1);
        }
        shift += 7;
    }
    return -1;
}

static int spt_g_parse_handle(const uint8_t *src, size_t maxLen, SptGBlockHandle *handle) {
    int l1 = spt_g_decode_varint64(src, maxLen, &handle->offset);
    if (l1 <= 0) return -1;
    int l2 = spt_g_decode_varint64(src + l1, maxLen - (size_t)l1, &handle->size);
    if (l2 <= 0) return -1;
    return l1 + l2;
}

static NSData *spt_g_snappy_decompress(const uint8_t *in_buf, size_t in_len) {
    if (!in_buf || in_len < 1) return nil;
    uint32_t uncomp_len = 0;
    int v_len = spt_g_decode_varint32(in_buf, in_len, &uncomp_len);
    if (v_len <= 0) return nil;
    if (uncomp_len > 4 * 1024 * 1024) return nil;
    if (uncomp_len == 0) return [NSData data];
    
    uint8_t *out_buf = (uint8_t *)malloc(uncomp_len);
    if (!out_buf) return nil;
    
    size_t ip = (size_t)v_len;
    size_t op = 0;
    
    while (ip < in_len && op < uncomp_len) {
        uint8_t tag = in_buf[ip++];
        uint8_t tag_type = tag & 0x03;
        if (tag_type == 0) {
            uint32_t len = (tag >> 2) + 1;
            if (len > 60) {
                uint32_t extra = len - 60;
                if (ip + extra > in_len) { free(out_buf); return nil; }
                len = 0;
                for (uint32_t b = 0; b < extra; b++) {
                    len |= ((uint32_t)in_buf[ip++]) << (b * 8);
                }
                len += 1;
            }
            if (ip + len > in_len || op + len > uncomp_len) {
                free(out_buf);
                return nil;
            }
            memcpy(out_buf + op, in_buf + ip, len);
            ip += len;
            op += len;
        } else if (tag_type == 1) {
            uint32_t len = ((tag >> 2) & 0x07) + 4;
            if (ip >= in_len) { free(out_buf); return nil; }
            uint32_t offset = (((uint32_t)(tag >> 5)) << 8) | in_buf[ip++];
            if (offset == 0 || offset > op || op + len > uncomp_len) {
                free(out_buf);
                return nil;
            }
            for (uint32_t i = 0; i < len; i++) {
                out_buf[op + i] = out_buf[op - offset + i];
            }
            op += len;
        } else if (tag_type == 2) {
            uint32_t len = (tag >> 2) + 1;
            if (ip + 2 > in_len) { free(out_buf); return nil; }
            uint32_t offset = (uint32_t)in_buf[ip] | (((uint32_t)in_buf[ip + 1]) << 8);
            ip += 2;
            if (offset == 0 || offset > op || op + len > uncomp_len) {
                free(out_buf);
                return nil;
            }
            for (uint32_t i = 0; i < len; i++) {
                out_buf[op + i] = out_buf[op - offset + i];
            }
            op += len;
        } else {
            uint32_t len = (tag >> 2) + 1;
            if (ip + 4 > in_len) { free(out_buf); return nil; }
            uint32_t offset = (uint32_t)in_buf[ip] | (((uint32_t)in_buf[ip + 1]) << 8) |
                              (((uint32_t)in_buf[ip + 2]) << 16) | (((uint32_t)in_buf[ip + 3]) << 24);
            ip += 4;
            if (offset == 0 || offset > op || op + len > uncomp_len) {
                free(out_buf);
                return nil;
            }
            for (uint32_t i = 0; i < len; i++) {
                out_buf[op + i] = out_buf[op - offset + i];
            }
            op += len;
        }
    }
    if (op != uncomp_len) {
        free(out_buf);
        return nil;
    }
    return [NSData dataWithBytesNoCopy:out_buf length:uncomp_len freeWhenDone:YES];
}

static NSData *spt_g_read_block(int fd, uint64_t offset, uint64_t size, uint8_t *outTrailer) {
    if (size > 8 * 1024 * 1024) return nil;
    uint8_t *raw = (uint8_t *)malloc((size_t)size + 5);
    if (!raw) return nil;
    ssize_t n = spt_g_pread(fd, raw, (size_t)size + 5, (off_t)offset);
    if (n < (ssize_t)(size + 5)) {
        free(raw);
        return nil;
    }
    uint8_t trailer = raw[size];
    if (outTrailer) *outTrailer = trailer;
    NSData *result = nil;
    if (trailer == 0) {
        result = [NSData dataWithBytes:raw length:(size_t)size];
    } else if (trailer == 1) {
        result = spt_g_snappy_decompress(raw, (size_t)size);
    }
    free(raw);
    return result;
}

static NSString *spt_g_escape_key(const uint8_t *keyBytes, size_t keyLen) {
    size_t userLen = (keyLen >= 8) ? (keyLen - 8) : keyLen;
    NSMutableString *res = [NSMutableString new];
    for (size_t i = 0; i < userLen; i++) {
        if (res.length >= 80) break;
        uint8_t c = keyBytes[i];
        if (c >= 32 && c <= 126 && c != '\\') {
            [res appendFormat:@"%c", c];
        } else {
            [res appendFormat:@"\\x%02x", c];
        }
    }
    return res;
}

static NSString *spt_g_hex_str(const uint8_t *bytes, size_t len, size_t maxBytes) {
    size_t n = MIN(len, maxBytes);
    NSMutableString *res = [NSMutableString new];
    for (size_t i = 0; i < n; i++) {
        [res appendFormat:@"%02x", bytes[i]];
    }
    return res;
}

static void spt_g_walk(const char *dirPath,
                       const char *rootPath,
                       int depth,
                       int *entryCount,
                       NSMutableArray<NSString *> *ldbFiles,
                       NSMutableArray<NSString *> *scanFiles,
                       NSMutableArray<NSString *> *storageBlobFiles,
                       int *storageCount,
                       off_t *storageBytes,
                       SptGFileEntry topStorage[5]) {
    if (depth > 6 || *entryCount >= 3000) return;
    DIR *d = opendir(dirPath);
    if (!d) return;
    size_t rootLen = strlen(rootPath);
    struct dirent *ent;
    while ((*entryCount < 3000) && (ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) {
            continue;
        }
        (*entryCount)++;
        char sub[PATH_MAX];
        snprintf(sub, sizeof(sub), "%s/%s", dirPath, ent->d_name);
        struct stat st;
        if (lstat(sub, &st) != 0 || S_ISLNK(st.st_mode)) {
            continue;
        }
        const char *rel = (strlen(sub) > rootLen) ? (sub + rootLen + 1) : sub;
        NSString *relStr = [NSString stringWithUTF8String:rel];
        
        if (S_ISDIR(st.st_mode)) {
            spt_g_walk(sub, rootPath, depth + 1, entryCount, ldbFiles, scanFiles, storageBlobFiles, storageCount, storageBytes, topStorage);
        } else if (S_ISREG(st.st_mode)) {
            if ([relStr hasPrefix:@"Storage/"]) {
                (*storageCount)++;
                (*storageBytes) += st.st_size;
                int ins = -1;
                for (int i = 0; i < 5; i++) {
                    if (st.st_size > topStorage[i].size) {
                        ins = i;
                        break;
                    }
                }
                if (ins >= 0) {
                    for (int i = 4; i > ins; i--) {
                        topStorage[i] = topStorage[i - 1];
                    }
                    strncpy(topStorage[ins].relPath, rel, PATH_MAX - 1);
                    topStorage[ins].relPath[PATH_MAX - 1] = '\0';
                    topStorage[ins].size = st.st_size;
                }
                if ([relStr hasSuffix:@".file"]) {
                    [storageBlobFiles addObject:relStr];
                }
            } else {
                BOOL isTopLevel = (strchr(rel, '/') == NULL);
                BOOL isUnderUsers = [relStr hasPrefix:@"Users/"];
                if (isTopLevel || isUnderUsers) {
                    NSString *redacted = spt_g_redact_path(relStr);
                    spt_probe_log("G", "file: %s size=%lld mtime=%ld",
                                  redacted.UTF8String, (long long)st.st_size, (long)st.st_mtime);
                }
            }
            
            if ([relStr hasSuffix:@".ldb"]) {
                [ldbFiles addObject:relStr];
                [scanFiles addObject:relStr];
            } else if ([relStr hasSuffix:@".log"] ||
                       [relStr.lastPathComponent hasPrefix:@"MANIFEST"] ||
                       [relStr.lastPathComponent isEqualToString:@"CURRENT"] ||
                       [relStr.lastPathComponent isEqualToString:@"context_player_state_restore"] ||
                       [relStr isEqualToString:@"Storage/index.dat"]) {
                [scanFiles addObject:relStr];
            }
        }
    }
    closedir(d);
}

void spt_probe_cache_run(void) {
    if (!spt_probe_is_enabled()) { return; }
    dispatch_async(spt_probe_get_queue(), ^{
        s_gTotalBytesRead = 0;
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/PersistentCache"];
        const char *rootC = root.fileSystemRepresentation;
        if (!rootC) return;
        
        spt_probe_log("G", "Starting PersistentCache inspection: %s", spt_g_redact_path(root).UTF8String);
        
        int entryCount = 0;
        int storageCount = 0;
        off_t storageBytes = 0;
        SptGFileEntry topStorage[5];
        memset(topStorage, 0, sizeof(topStorage));
        NSMutableArray<NSString *> *ldbFiles = [NSMutableArray new];
        NSMutableArray<NSString *> *scanFiles = [NSMutableArray new];
        NSMutableArray<NSString *> *storageBlobFiles = [NSMutableArray new];
        
        spt_g_walk(rootC, rootC, 1, &entryCount, ldbFiles, scanFiles, storageBlobFiles, &storageCount, &storageBytes, topStorage);
        
        spt_probe_log("G", "Storage: count=%d total_bytes=%lld", storageCount, (long long)storageBytes);
        spt_probe_log("G", "Storage top 5 largest:");
        for (int i = 0; i < 5; i++) {
            if (topStorage[i].size > 0) {
                NSString *r = spt_g_redact_path([NSString stringWithUTF8String:topStorage[i].relPath]);
                spt_probe_log("G", "  %s (%lld bytes)", r.UTF8String, (long long)topStorage[i].size);
            }
        }
        
        int ldbMagicOK = 0;
        int ldbMagicBAD = 0;
        
        // 2. LevelDB Table Check on each *.ldb (cap 20)
        NSInteger ldbLimit = MIN((NSInteger)ldbFiles.count, 20);
        for (NSInteger li = 0; li < ldbLimit; li++) {
            NSString *rel = ldbFiles[li];
            NSString *full = [root stringByAppendingPathComponent:rel];
            NSString *redactedRel = spt_g_redact_path(rel);
            
            struct stat st;
            if (lstat(full.fileSystemRepresentation, &st) != 0 || st.st_size > 64 * 1024 * 1024 || st.st_size < 48) {
                continue;
            }
            int fd = open(full.fileSystemRepresentation, O_RDONLY);
            if (fd < 0) continue;
            
            uint8_t footer[48];
            ssize_t nr = spt_g_pread(fd, footer, 48, st.st_size - 48);
            if (nr < 48) {
                close(fd);
                continue;
            }
            uint64_t magic = *(const uint64_t *)(footer + 40);
            if (magic != 0xdb4775248b80fb57ULL) {
                ldbMagicBAD++;
                uint8_t first16[16];
                memset(first16, 0, sizeof(first16));
                ssize_t n16 = spt_g_pread(fd, first16, 16, 0);
                NSString *h16 = (n16 > 0) ? spt_g_hex_str(first16, (size_t)n16, 16) : @"(read-err)";
                spt_probe_log("G", "ldb: %s magic=BAD size=%lld first16=%s",
                              redactedRel.UTF8String, (long long)st.st_size, h16.UTF8String);
                close(fd);
                continue;
            }
            ldbMagicOK++;
            spt_probe_log("G", "ldb: %s magic=OK size=%lld", redactedRel.UTF8String, (long long)st.st_size);
            
            SptGBlockHandle metaHandle = {0, 0};
            SptGBlockHandle indexHandle = {0, 0};
            int p1 = spt_g_parse_handle(footer, 40, &metaHandle);
            int p2 = (p1 > 0) ? spt_g_parse_handle(footer + p1, 40 - (size_t)p1, &indexHandle) : -1;
            if (p1 <= 0 || p2 <= 0) {
                spt_probe_log("G", "ldb: %s footer handle parse failed", redactedRel.UTF8String);
                close(fd);
                continue;
            }
            
            uint8_t indexTrailer = 0;
            NSData *indexData = spt_g_read_block(fd, indexHandle.offset, indexHandle.size, &indexTrailer);
            const char *compStr = (indexTrailer == 1) ? "snappy" : ((indexTrailer == 0) ? "uncompressed" : "unknown");
            spt_probe_log("G", "ldb: %s index offset=%llu size=%llu trailer=%d (%s)",
                          redactedRel.UTF8String, indexHandle.offset, indexHandle.size, (int)indexTrailer, compStr);
            
            if (!indexData || indexData.length < 4) {
                spt_probe_log("G", "ldb: %s index block decode failed", redactedRel.UTF8String);
                close(fd);
                continue;
            }
            
            const uint8_t *idxBytes = (const uint8_t *)indexData.bytes;
            size_t idxLen = indexData.length;
            uint32_t numRestarts = *(const uint32_t *)(idxBytes + idxLen - 4);
            size_t entriesEnd = idxLen - (1 + numRestarts) * 4;
            if (entriesEnd > idxLen) {
                close(fd);
                continue;
            }
            
            NSMutableArray<NSData *> *indexKeyList = [NSMutableArray new];
            NSMutableArray<NSValue *> *dataBlockHandles = [NSMutableArray new];
            NSMutableData *currKey = [NSMutableData new];
            size_t ipos = 0;
            while (ipos < entriesEnd) {
                uint32_t shared = 0, unshared = 0, vlen = 0;
                int d1 = spt_g_decode_varint32(idxBytes + ipos, entriesEnd - ipos, &shared);
                if (d1 <= 0) break;
                ipos += (size_t)d1;
                int d2 = spt_g_decode_varint32(idxBytes + ipos, entriesEnd - ipos, &unshared);
                if (d2 <= 0) break;
                ipos += (size_t)d2;
                int d3 = spt_g_decode_varint32(idxBytes + ipos, entriesEnd - ipos, &vlen);
                if (d3 <= 0) break;
                ipos += (size_t)d3;
                if (ipos + unshared + vlen > entriesEnd) break;
                
                if (shared <= currKey.length) {
                    [currKey setLength:shared];
                    [currKey appendBytes:idxBytes + ipos length:unshared];
                }
                ipos += unshared;
                
                SptGBlockHandle dh = {0, 0};
                if (spt_g_parse_handle(idxBytes + ipos, vlen, &dh) > 0) {
                    [dataBlockHandles addObject:[NSValue valueWithBytes:&dh objCType:@encode(SptGBlockHandle)]];
                    [indexKeyList addObject:[currKey copy]];
                }
                ipos += vlen;
            }
            
            NSInteger dataBlockCount = dataBlockHandles.count;
            spt_probe_log("G", "ldb: %s data blocks=%ld", redactedRel.UTF8String, (long)dataBlockCount);
            
            if (dataBlockCount > 0) {
                // Sample up to 24 blocks (first 8, middle 8, last 8)
                NSMutableIndexSet *sampleIdxs = [NSMutableIndexSet indexSet];
                for (NSInteger k = 0; k < 8 && k < dataBlockCount; k++) {
                    [sampleIdxs addIndex:(NSUInteger)k];
                }
                NSInteger midStart = MAX((NSInteger)0, (dataBlockCount / 2) - 4);
                for (NSInteger k = midStart; k < midStart + 8 && k < dataBlockCount; k++) {
                    [sampleIdxs addIndex:(NSUInteger)k];
                }
                NSInteger endStart = MAX((NSInteger)0, dataBlockCount - 8);
                for (NSInteger k = endStart; k < dataBlockCount; k++) {
                    [sampleIdxs addIndex:(NSUInteger)k];
                }
                
                int uncompCount = 0, snappyCount = 0, otherCount = 0;
                for (NSUInteger bidx = [sampleIdxs firstIndex]; bidx != NSNotFound; bidx = [sampleIdxs indexGreaterThanIndex:bidx]) {
                    SptGBlockHandle bh;
                    [dataBlockHandles[bidx] getValue:&bh];
                    uint8_t tbyte = 0;
                    if (spt_g_pread(fd, &tbyte, 1, (off_t)(bh.offset + bh.size)) == 1) {
                        if (tbyte == 0) uncompCount++;
                        else if (tbyte == 1) snappyCount++;
                        else otherCount++;
                    }
                }
                spt_probe_log("G", "ldb: %s sampled 24 blocks trailer: uncompressed=%d snappy=%d other=%d",
                              redactedRel.UTF8String, uncompCount, snappyCount, otherCount);
                
                // Decode 3 sampled data blocks: first (0), middle (N/2), last (N-1)
                NSInteger decodeTargets[3] = {0, dataBlockCount / 2, dataBlockCount - 1};
                for (int di = 0; di < 3; di++) {
                    NSInteger bidx = decodeTargets[di];
                    if (di > 0 && bidx == decodeTargets[di - 1]) continue;
                    SptGBlockHandle bh;
                    [dataBlockHandles[bidx] getValue:&bh];
                    uint8_t dtrailer = 0;
                    NSData *ddata = spt_g_read_block(fd, bh.offset, bh.size, &dtrailer);
                    if (!ddata || ddata.length < 4) {
                        continue;
                    }
                    const uint8_t *db = (const uint8_t *)ddata.bytes;
                    size_t dlen = ddata.length;
                    uint32_t dnumRestarts = *(const uint32_t *)(db + dlen - 4);
                    size_t dentriesEnd = dlen - (1 + dnumRestarts) * 4;
                    if (dentriesEnd > dlen) continue;
                    
                    int dEntryCount = 0;
                    NSMutableData *dkey = [NSMutableData new];
                    size_t dpos = 0;
                    while (dpos < dentriesEnd) {
                        uint32_t dshared = 0, dunshared = 0, dvlen = 0;
                        int r1 = spt_g_decode_varint32(db + dpos, dentriesEnd - dpos, &dshared);
                        if (r1 <= 0) break;
                        dpos += (size_t)r1;
                        int r2 = spt_g_decode_varint32(db + dpos, dentriesEnd - dpos, &dunshared);
                        if (r2 <= 0) break;
                        dpos += (size_t)r2;
                        int r3 = spt_g_decode_varint32(db + dpos, dentriesEnd - dpos, &dvlen);
                        if (r3 <= 0) break;
                        dpos += (size_t)r3;
                        if (dpos + dunshared + dvlen > dentriesEnd) break;
                        
                        if (dshared <= dkey.length) {
                            [dkey setLength:dshared];
                            [dkey appendBytes:db + dpos length:dunshared];
                        }
                        dpos += dunshared;
                        
                        dEntryCount++;
                        if (dEntryCount <= 5) {
                            NSString *escKey = spt_g_escape_key((const uint8_t *)dkey.bytes, dkey.length);
                            NSString *v0 = spt_g_hex_str(db + dpos, dvlen, 24);
                            spt_probe_log("G", "ldbkey: %s blk=%ld key=%s vlen=%u v0=%s",
                                          redactedRel.UTF8String, (long)bidx, escKey.UTF8String, dvlen, v0.UTF8String);
                        }
                        dpos += dvlen;
                    }
                    spt_probe_log("G", "ldb: %s blk=%ld entries=%d", redactedRel.UTF8String, (long)bidx, dEntryCount);
                }
                
                // Log up to 10 index separator keys spread evenly
                NSInteger sepCount = MIN((NSInteger)indexKeyList.count, 10);
                for (NSInteger si = 0; si < sepCount; si++) {
                    NSInteger targetIdx = (indexKeyList.count > 1) ? (si * (indexKeyList.count - 1) / (sepCount - 1)) : 0;
                    NSData *kd = indexKeyList[targetIdx];
                    NSString *escKey = spt_g_escape_key((const uint8_t *)kd.bytes, kd.length);
                    spt_probe_log("G", "ldbsep: %s idx=%ld key=%s", redactedRel.UTF8String, (long)targetIdx, escKey.UTF8String);
                }
            }
            close(fd);
        }
        
        // 3. String Scan
        NSMutableSet<NSString *> *allTracks = [NSMutableSet new];
        NSMutableSet<NSString *> *allPlaylists = [NSMutableSet new];
        int totalLdbTrack = 0, totalLdbPlaylist = 0, totalLdbEpisode = 0, totalLdbAlbum = 0;
        int totalLdbArtist = 0, totalLdbUser = 0, totalLdbCollection = 0, totalLdbShow = 0;
        
        static NSCharacterSet *s_invB62 = nil;
        static dispatch_once_t s_b62Once;
        dispatch_once(&s_b62Once, ^{
            s_invB62 = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet];
        });
        
        for (NSString *rel in scanFiles) {
            NSString *full = [root stringByAppendingPathComponent:rel];
            NSString *redactedRel = spt_g_redact_path(rel);
            struct stat st;
            if (lstat(full.fileSystemRepresentation, &st) != 0 || st.st_size > 64 * 1024 * 1024 || st.st_size <= 0) {
                continue;
            }
            int fd = open(full.fileSystemRepresentation, O_RDONLY);
            if (fd < 0) continue;
            
            int cTrack = 0, cPlaylist = 0, cEpisode = 0, cAlbum = 0;
            int cArtist = 0, cUser = 0, cCollection = 0, cShow = 0;
            NSMutableSet<NSString *> *fileTracks = [NSMutableSet new];
            NSMutableSet<NSString *> *filePlaylists = [NSMutableSet new];
            NSMutableArray<NSString *> *manifestRuns = [NSMutableArray new];
            NSMutableArray<NSString *> *stateRuns = [NSMutableArray new];
            NSString *stateFirst48 = @"";
            
            BOOL isManifest = [rel.lastPathComponent hasPrefix:@"MANIFEST"];
            BOOL isContextState = [rel.lastPathComponent isEqualToString:@"context_player_state_restore"];
            
            const size_t chunkSize = 1024 * 1024;
            uint8_t *buf = (uint8_t *)malloc(chunkSize);
            off_t fileOff = 0;
            BOOL firstChunk = YES;
            
            while (fileOff < st.st_size && buf) {
                size_t toRead = (size_t)MIN((off_t)chunkSize, st.st_size - fileOff);
                ssize_t n = spt_g_pread(fd, buf, toRead, fileOff);
                if (n <= 0) break;
                
                if (firstChunk && isContextState) {
                    stateFirst48 = spt_g_hex_str(buf, (size_t)n, 48);
                }
                
                // Scan printable runs
                if (isManifest && manifestRuns.count < 6) {
                    size_t rstart = 0;
                    BOOL inRun = NO;
                    for (ssize_t i = 0; i < n; i++) {
                        uint8_t c = buf[i];
                        if (c >= 32 && c <= 126) {
                            if (!inRun) { rstart = (size_t)i; inRun = YES; }
                        } else {
                            if (inRun) {
                                size_t rlen = (size_t)i - rstart;
                                if (rlen >= 8 && manifestRuns.count < 6) {
                                    NSString *rs = [[NSString alloc] initWithBytes:buf + rstart length:rlen encoding:NSUTF8StringEncoding];
                                    if (rs && ![manifestRuns containsObject:rs]) {
                                        [manifestRuns addObject:rs];
                                    }
                                }
                                inRun = NO;
                            }
                        }
                    }
                }
                
                if (isContextState && stateRuns.count < 12) {
                    size_t rstart = 0;
                    BOOL inRun = NO;
                    for (ssize_t i = 0; i < n; i++) {
                        uint8_t c = buf[i];
                        if (c >= 32 && c <= 126) {
                            if (!inRun) { rstart = (size_t)i; inRun = YES; }
                        } else {
                            if (inRun) {
                                size_t rlen = (size_t)i - rstart;
                                if (rlen >= 12 && stateRuns.count < 12) {
                                    size_t cutLen = MIN(rlen, (size_t)64);
                                    NSString *rs = [[NSString alloc] initWithBytes:buf + rstart length:cutLen encoding:NSUTF8StringEncoding];
                                    if (rs && ![stateRuns containsObject:rs]) {
                                        [stateRuns addObject:rs];
                                    }
                                }
                                inRun = NO;
                            }
                        }
                    }
                }
                
                // Scan spotify: patterns
                for (ssize_t i = 0; i < n - 14; i++) {
                    if (buf[i] != 's' || buf[i + 1] != 'p') continue;
                    if (memcmp(buf + i, "spotify:track:", 14) == 0) {
                        cTrack++;
                        if (i + 14 + 22 <= n) {
                            NSString *b62 = [[NSString alloc] initWithBytes:buf + i + 14 length:22 encoding:NSASCIIStringEncoding];
                            if (b62 && [b62 rangeOfCharacterFromSet:s_invB62].location == NSNotFound) {
                                [fileTracks addObject:b62];
                                if (allTracks.count < 100000) [allTracks addObject:b62];
                            }
                        }
                    } else if (memcmp(buf + i, "spotify:playlist:", 17) == 0) {
                        cPlaylist++;
                        if (i + 17 + 22 <= n) {
                            NSString *b62 = [[NSString alloc] initWithBytes:buf + i + 17 length:22 encoding:NSASCIIStringEncoding];
                            if (b62 && [b62 rangeOfCharacterFromSet:s_invB62].location == NSNotFound) {
                                [filePlaylists addObject:b62];
                                if (allPlaylists.count < 100000) [allPlaylists addObject:b62];
                            }
                        }
                    } else if (memcmp(buf + i, "spotify:episode:", 16) == 0) {
                        cEpisode++;
                    } else if (memcmp(buf + i, "spotify:album:", 14) == 0) {
                        cAlbum++;
                    } else if (memcmp(buf + i, "spotify:artist:", 15) == 0) {
                        cArtist++;
                    } else if (memcmp(buf + i, "spotify:user:", 13) == 0) {
                        cUser++;
                    } else if (memcmp(buf + i, "spotify:collection", 18) == 0) {
                        cCollection++;
                    } else if (memcmp(buf + i, "spotify:show:", 13) == 0) {
                        cShow++;
                    }
                }
                
                firstChunk = NO;
                if ((size_t)n < chunkSize) break;
                fileOff += (off_t)(n - 32);
            }
            if (buf) free(buf);
            close(fd);
            
            spt_probe_log("G", "scan: %s track=%d(distinct %ld) playlist=%d(distinct %ld) episode=%d album=%d artist=%d user=%d collection=%d show=%d",
                          redactedRel.UTF8String, cTrack, (long)fileTracks.count, cPlaylist, (long)filePlaylists.count,
                          cEpisode, cAlbum, cArtist, cUser, cCollection, cShow);
            
            if (isManifest) {
                for (NSString *run in manifestRuns) {
                    spt_probe_log("G", "manifest: %s run: %s", redactedRel.UTF8String, run.UTF8String);
                }
            }
            if (isContextState) {
                spt_probe_log("G", "context_state: %s first48=%s", redactedRel.UTF8String, stateFirst48.UTF8String);
                for (NSString *run in stateRuns) {
                    spt_probe_log("G", "context_state: %s run: %s", redactedRel.UTF8String, run.UTF8String);
                }
            }
            
            if ([rel hasSuffix:@".ldb"]) {
                totalLdbTrack += cTrack;
                totalLdbPlaylist += cPlaylist;
                totalLdbEpisode += cEpisode;
                totalLdbAlbum += cAlbum;
                totalLdbArtist += cArtist;
                totalLdbUser += cUser;
                totalLdbCollection += cCollection;
                totalLdbShow += cShow;
            }
        }
        
        spt_probe_log("G", "ldb_totals: track=%d(distinct %ld) playlist=%d(distinct %ld) episode=%d album=%d artist=%d user=%d collection=%d show=%d",
                      totalLdbTrack, (long)allTracks.count, totalLdbPlaylist, (long)allPlaylists.count,
                      totalLdbEpisode, totalLdbAlbum, totalLdbArtist, totalLdbUser, totalLdbCollection, totalLdbShow);
        
        // 4. Storage Blob Sample (10 evenly spaced)
        NSInteger blobCount = storageBlobFiles.count;
        if (blobCount > 0) {
            NSInteger sampleCount = MIN(blobCount, (NSInteger)10);
            for (NSInteger bi = 0; bi < sampleCount; bi++) {
                NSInteger targetIdx = (blobCount > 1) ? (bi * (blobCount - 1) / (sampleCount - 1)) : 0;
                NSString *rel = storageBlobFiles[targetIdx];
                NSString *full = [root stringByAppendingPathComponent:rel];
                NSString *redactedRel = spt_g_redact_path(rel);
                
                int fd = open(full.fileSystemRepresentation, O_RDONLY);
                if (fd < 0) continue;
                
                uint8_t blobHdr[32];
                memset(blobHdr, 0, sizeof(blobHdr));
                ssize_t nb = spt_g_pread(fd, blobHdr, 32, 0);
                NSString *hex32 = (nb > 0) ? spt_g_hex_str(blobHdr, (size_t)nb, 32) : @"(read-err)";
                
                // String scan on up to 512 KB of the blob
                uint8_t *sbuf = (uint8_t *)malloc(512 * 1024);
                int bTrack = 0, bPlaylist = 0, bEpisode = 0, bAlbum = 0;
                int bArtist = 0, bUser = 0, bCollection = 0, bShow = 0;
                if (sbuf) {
                    ssize_t sn = spt_g_pread(fd, sbuf, 512 * 1024, 0);
                    for (ssize_t i = 0; i < sn - 14; i++) {
                        if (sbuf[i] != 's' || sbuf[i + 1] != 'p') continue;
                        if (memcmp(sbuf + i, "spotify:track:", 14) == 0) bTrack++;
                        else if (memcmp(sbuf + i, "spotify:playlist:", 17) == 0) bPlaylist++;
                        else if (memcmp(sbuf + i, "spotify:episode:", 16) == 0) bEpisode++;
                        else if (memcmp(sbuf + i, "spotify:album:", 14) == 0) bAlbum++;
                        else if (memcmp(sbuf + i, "spotify:artist:", 15) == 0) bArtist++;
                        else if (memcmp(sbuf + i, "spotify:user:", 13) == 0) bUser++;
                        else if (memcmp(sbuf + i, "spotify:collection", 18) == 0) bCollection++;
                        else if (memcmp(sbuf + i, "spotify:show:", 13) == 0) bShow++;
                    }
                    free(sbuf);
                }
                close(fd);
                
                spt_probe_log("G", "storage_blob: %s first32=%s track=%d playlist=%d episode=%d album=%d artist=%d user=%d collection=%d show=%d",
                              redactedRel.UTF8String, hex32.UTF8String, bTrack, bPlaylist, bEpisode, bAlbum, bArtist, bUser, bCollection, bShow);
            }
        }
        
        // 5. "--- G summary ---" LAST
        spt_probe_log("G", "--- G summary ---");
        spt_probe_log("G", "PersistentCache entries=%d storage_files=%d storage_bytes=%lld bytes_read=%lld",
                      entryCount, storageCount, (long long)storageBytes, (long long)s_gTotalBytesRead);
        spt_probe_log("G", "LevelDB tables: magic_ok=%d magic_bad=%d", ldbMagicOK, ldbMagicBAD);
        spt_probe_log("G", "Unique entities: tracks=%ld playlists=%ld", (long)allTracks.count, (long)allPlaylists.count);
    });
}

#endif
