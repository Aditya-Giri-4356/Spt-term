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
} SptHBlockHandle;

typedef struct {
    int lineCount;
    size_t byteCount;
    BOOL exceededLogged;
} SptHBudget;

static off_t s_hTotalBytesRead = 0;

static void spt_h_budget_log(SptHBudget *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

static void spt_h_budget_log(SptHBudget *b, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[2048];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    size_t len = strlen(buf);
    if (b->lineCount >= 450 || b->byteCount + len >= 58 * 1024) {
        if (!b->exceededLogged) {
            b->exceededLogged = YES;
            spt_probe_log("H", "budget exceeded");
        }
        return;
    }
    b->lineCount++;
    b->byteCount += len + 30;
    spt_probe_log("H", "%s", buf);
}

static NSString *spt_h_redact_user(NSString *str) {
    if (!str || str.length == 0) return @"";
    static NSRegularExpression *reUser = nil;
    static NSRegularExpression *rePath = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reUser = [NSRegularExpression regularExpressionWithPattern:@"spotify:user:[^\\s\\\"',]+"
                                                           options:NSRegularExpressionCaseInsensitive
                                                             error:NULL];
        rePath = [NSRegularExpression regularExpressionWithPattern:@"(Users/)[^/]+"
                                                           options:0
                                                             error:NULL];
    });
    NSMutableString *s = [str mutableCopy];
    [reUser replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"spotify:user:<u>"];
    [rePath replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1<uid>"];
    return s;
}

static ssize_t h_pread(int fd, void *buf, size_t nbyte, off_t offset) {
    if (s_hTotalBytesRead + (off_t)nbyte > 200 * 1024 * 1024) {
        return -1;
    }
    ssize_t r = pread(fd, buf, nbyte, offset);
    if (r > 0) {
        s_hTotalBytesRead += r;
    }
    return r;
}

static int h_decode_varint32(const uint8_t *src, size_t maxLen, uint32_t *val) {
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

static int h_decode_varint64(const uint8_t *src, size_t maxLen, uint64_t *val) {
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

static int h_parse_handle(const uint8_t *src, size_t maxLen, SptHBlockHandle *handle) {
    int l1 = h_decode_varint64(src, maxLen, &handle->offset);
    if (l1 <= 0) return -1;
    int l2 = h_decode_varint64(src + l1, maxLen - (size_t)l1, &handle->size);
    if (l2 <= 0) return -1;
    return l1 + l2;
}

static NSData *h_snappy_decompress(const uint8_t *in_buf, size_t in_len) {
    if (!in_buf || in_len < 1) return nil;
    uint32_t uncomp_len = 0;
    int v_len = h_decode_varint32(in_buf, in_len, &uncomp_len);
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

static NSData *h_read_block(int fd, uint64_t offset, uint64_t size, uint8_t *outTrailer) {
    if (size > 8 * 1024 * 1024) return nil;
    uint8_t *raw = (uint8_t *)malloc((size_t)size + 5);
    if (!raw) return nil;
    ssize_t n = h_pread(fd, raw, (size_t)size + 5, (off_t)offset);
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
        result = h_snappy_decompress(raw, (size_t)size);
    }
    free(raw);
    return result;
}

static NSString *spt_h_escape(const uint8_t *bytes, size_t len, size_t maxLen) {
    size_t n = MIN(len, maxLen);
    NSMutableString *res = [NSMutableString new];
    for (size_t i = 0; i < n; i++) {
        uint8_t c = bytes[i];
        if (c >= 32 && c <= 126 && c != '\\') {
            [res appendFormat:@"%c", c];
        } else {
            [res appendFormat:@"\\x%02x", c];
        }
    }
    return res;
}

static NSString *spt_h_hex(const uint8_t *bytes, size_t len, size_t maxBytes) {
    size_t n = MIN(len, maxBytes);
    NSMutableString *res = [NSMutableString new];
    for (size_t i = 0; i < n; i++) {
        [res appendFormat:@"%02x", bytes[i]];
    }
    return res;
}

@interface SptHEntry : NSObject
@property (nonatomic, assign) uint64_t seq;
@property (nonatomic, assign) uint8_t type;
@property (nonatomic, assign) uint32_t vlen;
@property (nonatomic, strong) NSData *vPrefix;
@property (nonatomic, assign) uint32_t countTrack;
@property (nonatomic, assign) uint32_t countPlaylist;
@property (nonatomic, assign) uint32_t countEpisode;
@property (nonatomic, strong) NSData *fullValue;
@end

@implementation SptHEntry
@end

@interface SptHFamStat : NSObject
@property (nonatomic, copy) NSString *family;
@property (nonatomic, assign) int live;
@property (nonatomic, assign) int dead;
@property (nonatomic, assign) uint64_t keyBytes;
@property (nonatomic, assign) uint64_t valBytes;
@property (nonatomic, assign) uint32_t vlenMin;
@property (nonatomic, assign) uint64_t vlenSum;
@property (nonatomic, assign) uint32_t vlenMax;
@property (nonatomic, strong) NSMutableArray<SptHEntry *> *sampleEntries;
@property (nonatomic, strong) NSMutableArray<NSData *> *sampleKeys;
@property (nonatomic, strong) NSMutableSet<NSString *> *typeUrls;
@end

@implementation SptHFamStat
@end

static NSString *spt_h_extract_family(const uint8_t *k, size_t kLen) {
    size_t hashCount = 0;
    size_t cutHash = kLen;
    for (size_t i = 0; i < kLen; i++) {
        if (k[i] == 0x23) {
            hashCount++;
            if (hashCount == 4) {
                cutHash = i + 1;
                break;
            }
        }
    }
    size_t cutSpot = kLen;
    for (size_t i = 0; i + 8 <= kLen; i++) {
        if (memcmp(k + i, "spotify:", 8) == 0) {
            cutSpot = (i > 0) ? (i - 1) : 0;
            break;
        }
    }
    size_t famLen = MIN(cutHash, cutSpot);
    if (famLen == 0 && kLen > 0) famLen = 1;
    return spt_h_escape(k, famLen, 120);
}

void spt_probe_ldb_run(void) {
    if (!spt_probe_is_enabled()) return;
    dispatch_async(spt_probe_get_queue(), ^{
        s_hTotalBytesRead = 0;
        SptHBudget budget = {0, 0, NO};
        
        // 1. Find directory Users/*/primary.ldb
        NSString *baseUsers = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/PersistentCache/Users"];
        DIR *uDir = opendir(baseUsers.fileSystemRepresentation);
        NSString *targetDir = nil;
        if (uDir) {
            struct dirent *de;
            while ((de = readdir(uDir)) != NULL) {
                if (de->d_name[0] == '.') continue;
                NSString *sub = [baseUsers stringByAppendingPathComponent:[NSString stringWithUTF8String:de->d_name]];
                NSString *prim = [sub stringByAppendingPathComponent:@"primary.ldb"];
                if (access(prim.fileSystemRepresentation, F_OK) == 0) {
                    targetDir = sub;
                    break;
                }
            }
            closedir(uDir);
        }
        
        if (!targetDir) {
            spt_h_budget_log(&budget, "H: dir=missing");
            spt_probe_log("H", "--- H summary --- live=0 families=0 rootlist=NO pldistinct=0 bytes_read=%lld", (long long)s_hTotalBytesRead);
            return;
        }
        
        spt_h_budget_log(&budget, "H: dir=Users/<uid>/primary.ldb");
        
        // 2. CURRENT and MANIFEST
        NSString *curPath = [targetDir stringByAppendingPathComponent:@"CURRENT"];
        NSError *curErr = nil;
        NSString *curContent = [NSString stringWithContentsOfFile:curPath encoding:NSUTF8StringEncoding error:&curErr];
        if (curContent && curContent.length > 0) {
            NSString *manifestName = [curContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            spt_h_budget_log(&budget, "H: CURRENT=%s", manifestName.UTF8String);
            
            NSString *manifestPath = [targetDir stringByAppendingPathComponent:manifestName];
            int mfd = open(manifestPath.fileSystemRepresentation, O_RDONLY);
            if (mfd >= 0) {
                struct stat mst;
                if (fstat(mfd, &mst) == 0 && mst.st_size > 0 && mst.st_size <= 64 * 1024 * 1024) {
                    NSString *comparator = @"(none)";
                    uint64_t logNum = 0, lastSeq = 0;
                    NSMutableSet<NSNumber *> *liveFiles[7];
                    for (int l = 0; l < 7; l++) liveFiles[l] = [NSMutableSet new];
                    
                    uint8_t *mbuf = (uint8_t *)malloc((size_t)mst.st_size);
                    if (mbuf) {
                        ssize_t mr = h_pread(mfd, mbuf, (size_t)mst.st_size, 0);
                        if (mr > 0) {
                            size_t off = 0;
                            while (off + 7 <= (size_t)mr) {
                                uint16_t rlen = (uint16_t)mbuf[off + 4] | (((uint16_t)mbuf[off + 5]) << 8);
                                uint8_t rtype = mbuf[off + 6];
                                off += 7;
                                if (off + rlen > (size_t)mr) break;
                                if (rtype == 1 && rlen > 0) {
                                    size_t roff = off;
                                    size_t rend = off + rlen;
                                    while (roff < rend) {
                                        uint32_t tag = 0;
                                        int dl = h_decode_varint32(mbuf + roff, rend - roff, &tag);
                                        if (dl <= 0) break;
                                        roff += (size_t)dl;
                                        if (tag == 1) {
                                            uint32_t clen = 0;
                                            int l = h_decode_varint32(mbuf + roff, rend - roff, &clen);
                                            if (l <= 0) break;
                                            roff += (size_t)l;
                                            if (roff + clen <= rend) {
                                                comparator = [[NSString alloc] initWithBytes:mbuf + roff length:clen encoding:NSUTF8StringEncoding] ?: @"(unknown)";
                                                roff += clen;
                                            }
                                        } else if (tag == 2) {
                                            uint64_t v = 0; int l = h_decode_varint64(mbuf + roff, rend - roff, &v);
                                            if (l <= 0) break; roff += (size_t)l; logNum = v;
                                        } else if (tag == 3) {
                                            uint64_t v = 0; int l = h_decode_varint64(mbuf + roff, rend - roff, &v);
                                            if (l <= 0) break; roff += (size_t)l;
                                        } else if (tag == 4) {
                                            uint64_t v = 0; int l = h_decode_varint64(mbuf + roff, rend - roff, &v);
                                            if (l <= 0) break; roff += (size_t)l; lastSeq = v;
                                        } else if (tag == 5) {
                                            uint32_t lvl = 0, klen = 0;
                                            int l = h_decode_varint32(mbuf + roff, rend - roff, &lvl);
                                            if (l <= 0) break; roff += (size_t)l;
                                            l = h_decode_varint32(mbuf + roff, rend - roff, &klen);
                                            if (l <= 0) break; roff += (size_t)l + klen;
                                        } else if (tag == 6) {
                                            uint32_t lvl = 0; uint64_t fnum = 0;
                                            int l = h_decode_varint32(mbuf + roff, rend - roff, &lvl);
                                            if (l <= 0) break; roff += (size_t)l;
                                            l = h_decode_varint64(mbuf + roff, rend - roff, &fnum);
                                            if (l <= 0) break; roff += (size_t)l;
                                            if (lvl < 7) [liveFiles[lvl] removeObject:@(fnum)];
                                        } else if (tag == 7) {
                                            uint32_t lvl = 0; uint64_t fnum = 0, fsize = 0; uint32_t klen1 = 0, klen2 = 0;
                                            int l = h_decode_varint32(mbuf + roff, rend - roff, &lvl);
                                            if (l <= 0) break; roff += (size_t)l;
                                            l = h_decode_varint64(mbuf + roff, rend - roff, &fnum);
                                            if (l <= 0) break; roff += (size_t)l;
                                            l = h_decode_varint64(mbuf + roff, rend - roff, &fsize);
                                            if (l <= 0) break; roff += (size_t)l;
                                            l = h_decode_varint32(mbuf + roff, rend - roff, &klen1);
                                            if (l <= 0) break; roff += (size_t)l + klen1;
                                            l = h_decode_varint32(mbuf + roff, rend - roff, &klen2);
                                            if (l <= 0) break; roff += (size_t)l + klen2;
                                            if (lvl < 7) [liveFiles[lvl] addObject:@(fnum)];
                                        } else if (tag == 9) {
                                            uint64_t v = 0; int l = h_decode_varint64(mbuf + roff, rend - roff, &v);
                                            if (l <= 0) break; roff += (size_t)l;
                                        } else {
                                            break;
                                        }
                                    }
                                }
                                off += rlen;
                            }
                            spt_h_budget_log(&budget, "H: manifest comparator=%s log_number=%llu last_seq=%llu",
                                             comparator.UTF8String, (unsigned long long)logNum, (unsigned long long)lastSeq);
                            for (int l = 0; l < 7; l++) {
                                if (liveFiles[l].count > 0) {
                                    NSArray *arr = [liveFiles[l].allObjects sortedArrayUsingSelector:@selector(compare:)];
                                    NSMutableArray<NSString *> *sarr = [NSMutableArray new];
                                    for (NSNumber *n in arr) [sarr addObject:n.stringValue];
                                    spt_h_budget_log(&budget, "H: live L%d: %s", l, [sarr componentsJoinedByString:@", "].UTF8String);
                                }
                            }
                        }
                        free(mbuf);
                    }
                }
                close(mfd);
            }
        }
        
        // 3. Ingest *.ldb and *.log
        NSMutableDictionary<NSData *, SptHEntry *> *mergedMap = [NSMutableDictionary dictionaryWithCapacity:50000];
        int tableCount = 0, logCount = 0;
        uint64_t totalEntries = 0;
        uint64_t overriddenCount = 0;
        uint64_t seqMin = UINT64_MAX, seqMax = 0;
        int errorCount = 0;
        
        DIR *tDir = opendir(targetDir.fileSystemRepresentation);
        NSMutableArray<NSString *> *allFiles = [NSMutableArray new];
        if (tDir) {
            struct dirent *de;
            while ((de = readdir(tDir)) != NULL) {
                if (de->d_name[0] == '.') continue;
                NSString *fn = [NSString stringWithUTF8String:de->d_name];
                if ([fn hasSuffix:@".ldb"] || [fn hasSuffix:@".log"]) {
                    [allFiles addObject:fn];
                }
            }
            closedir(tDir);
        }
        [allFiles sortUsingSelector:@selector(compare:)];
        
        for (NSString *fname in allFiles) {
            NSString *fpath = [targetDir stringByAppendingPathComponent:fname];
            struct stat fst;
            if (lstat(fpath.fileSystemRepresentation, &fst) != 0 || fst.st_size > 64 * 1024 * 1024 || fst.st_size <= 0) {
                continue;
            }
            int fd = open(fpath.fileSystemRepresentation, O_RDONLY);
            if (fd < 0) continue;
            
            BOOL isLdb = [fname hasSuffix:@".ldb"];
            if (isLdb) tableCount++; else logCount++;
            
            uint64_t fEntries = 0, fPuts = 0, fDels = 0;
            const char *fErr = "none";
            
            if (isLdb) {
                if (fst.st_size < 48) {
                    fErr = "too_small";
                    errorCount++;
                } else {
                    uint8_t footer[48];
                    if (h_pread(fd, footer, 48, fst.st_size - 48) == 48 &&
                        *(const uint64_t *)(footer + 40) == 0xdb4775248b80fb57ULL) {
                        SptHBlockHandle metaH = {0, 0}, indexH = {0, 0};
                        int p1 = h_parse_handle(footer, 40, &metaH);
                        int p2 = (p1 > 0) ? h_parse_handle(footer + p1, 40 - (size_t)p1, &indexH) : -1;
                        if (p2 > 0) {
                            uint8_t itrailer = 0;
                            NSData *idxData = h_read_block(fd, indexH.offset, indexH.size, &itrailer);
                            if (idxData && idxData.length >= 4) {
                                const uint8_t *ib = (const uint8_t *)idxData.bytes;
                                size_t ilen = idxData.length;
                                uint32_t numRestarts = *(const uint32_t *)(ib + ilen - 4);
                                size_t entriesEnd = ilen - (1 + numRestarts) * 4;
                                size_t ipos = 0;
                                NSMutableData *ik = [NSMutableData new];
                                NSMutableArray<NSValue *> *dataHandles = [NSMutableArray new];
                                while (ipos < entriesEnd) {
                                    uint32_t sh = 0, un = 0, vl = 0;
                                    int d1 = h_decode_varint32(ib + ipos, entriesEnd - ipos, &sh); if (d1 <= 0) break; ipos += (size_t)d1;
                                    int d2 = h_decode_varint32(ib + ipos, entriesEnd - ipos, &un); if (d2 <= 0) break; ipos += (size_t)d2;
                                    int d3 = h_decode_varint32(ib + ipos, entriesEnd - ipos, &vl); if (d3 <= 0) break; ipos += (size_t)d3;
                                    if (ipos + un + vl > entriesEnd) break;
                                    if (sh <= ik.length) { [ik setLength:sh]; [ik appendBytes:ib + ipos length:un]; }
                                    ipos += un;
                                    SptHBlockHandle dh;
                                    if (h_parse_handle(ib + ipos, vl, &dh) > 0) {
                                        [dataHandles addObject:[NSValue valueWithBytes:&dh objCType:@encode(SptHBlockHandle)]];
                                    }
                                    ipos += vl;
                                }
                                
                                for (NSValue *vh in dataHandles) {
                                    SptHBlockHandle dh;
                                    [vh getValue:&dh];
                                    uint8_t dtrailer = 0;
                                    NSData *ddata = h_read_block(fd, dh.offset, dh.size, &dtrailer);
                                    if (!ddata || ddata.length < 4) continue;
                                    const uint8_t *db = (const uint8_t *)ddata.bytes;
                                    size_t dlen = ddata.length;
                                    uint32_t dnumRestarts = *(const uint32_t *)(db + dlen - 4);
                                    size_t dentriesEnd = dlen - (1 + dnumRestarts) * 4;
                                    if (dentriesEnd > dlen) continue;
                                    size_t dpos = 0;
                                    NSMutableData *dk = [NSMutableData new];
                                    while (dpos < dentriesEnd) {
                                        uint32_t dsh = 0, dun = 0, dvl = 0;
                                        int r1 = h_decode_varint32(db + dpos, dentriesEnd - dpos, &dsh); if (r1 <= 0) break; dpos += (size_t)r1;
                                        int r2 = h_decode_varint32(db + dpos, dentriesEnd - dpos, &dun); if (r2 <= 0) break; dpos += (size_t)r2;
                                        int r3 = h_decode_varint32(db + dpos, dentriesEnd - dpos, &dvl); if (r3 <= 0) break; dpos += (size_t)r3;
                                        if (dpos + dun + dvl > dentriesEnd) break;
                                        if (dsh <= dk.length) { [dk setLength:dsh]; [dk appendBytes:db + dpos length:dun]; }
                                        dpos += dun;
                                        
                                        fEntries++; totalEntries++;
                                        if (dk.length >= 8) {
                                            const uint8_t *kptr = (const uint8_t *)dk.bytes;
                                            size_t ulen = dk.length - 8;
                                            uint64_t pack = *(const uint64_t *)(kptr + ulen);
                                            uint64_t seq = pack >> 8;
                                            uint8_t type = (uint8_t)(pack & 0xFF);
                                            if (type == 1) { fPuts++; } else { fDels++; }
                                            if (seq < seqMin) seqMin = seq;
                                            if (seq > seqMax) seqMax = seq;
                                            
                                            NSData *ukData = [NSData dataWithBytes:kptr length:ulen];
                                            SptHEntry *prev = mergedMap[ukData];
                                            if (!prev || seq > prev.seq) {
                                                if (prev) overriddenCount++;
                                                if (!prev && mergedMap.count >= 500000) {
                                                    // capped
                                                } else {
                                                    SptHEntry *e = [SptHEntry new];
                                                    e.seq = seq;
                                                    e.type = type;
                                                    e.vlen = dvl;
                                                    e.vPrefix = [NSData dataWithBytes:db + dpos length:MIN((size_t)dvl, (size_t)256)];
                                                    
                                                    // Count URIs in value (up to 1 MB)
                                                    size_t vscanLen = MIN((size_t)dvl, (size_t)(1024 * 1024));
                                                    const uint8_t *vp = db + dpos;
                                                    for (size_t vi = 0; vi + 14 <= vscanLen; vi++) {
                                                        if (vp[vi] == 's' && vp[vi+1] == 'p') {
                                                            if (memcmp(vp + vi, "spotify:track:", 14) == 0) e.countTrack++;
                                                            else if (memcmp(vp + vi, "spotify:playlist:", 17) == 0) e.countPlaylist++;
                                                            else if (memcmp(vp + vi, "spotify:episode:", 16) == 0) e.countEpisode++;
                                                        }
                                                    }
                                                    if (e.countTrack > 0 || e.countPlaylist > 0) {
                                                        e.fullValue = [NSData dataWithBytes:vp length:vscanLen];
                                                    }
                                                    mergedMap[ukData] = e;
                                                }
                                            }
                                        }
                                        dpos += dvl;
                                    }
                                }
                            } else {
                                fErr = "bad_index";
                                errorCount++;
                            }
                        } else {
                            fErr = "bad_handle";
                            errorCount++;
                        }
                    } else {
                        fErr = "bad_magic";
                        errorCount++;
                    }
                }
            } else {
                // Parse WAL (.log)
                const size_t kBlockSize = 32768;
                uint8_t *lbuf = (uint8_t *)malloc(kBlockSize);
                off_t lpos = 0;
                NSMutableData *record = [NSMutableData new];
                while (lpos + 7 <= fst.st_size && lbuf) {
                    size_t blockLeft = (size_t)(kBlockSize - (lpos % kBlockSize));
                    if (blockLeft < 7) {
                        lpos += (off_t)blockLeft;
                        continue;
                    }
                    uint8_t hdr[7];
                    if (h_pread(fd, hdr, 7, lpos) < 7) break;
                    uint16_t rlen = (uint16_t)hdr[4] | (((uint16_t)hdr[5]) << 8);
                    uint8_t rtype = hdr[6];
                    lpos += 7;
                    if (rtype == 0 || rlen == 0 || (size_t)rlen > blockLeft - 7) {
                        lpos += (off_t)(blockLeft - 7);
                        continue;
                    }
                    uint8_t *payload = (uint8_t *)malloc(rlen);
                    if (!payload) break;
                    if (h_pread(fd, payload, rlen, lpos) < (ssize_t)rlen) {
                        free(payload);
                        break;
                    }
                    lpos += rlen;
                    
                    if (rtype == 1) { // FULL
                        [record setLength:0];
                        [record appendBytes:payload length:rlen];
                    } else if (rtype == 2) { // FIRST
                        [record setLength:0];
                        [record appendBytes:payload length:rlen];
                    } else if (rtype == 3) { // MIDDLE
                        [record appendBytes:payload length:rlen];
                    } else if (rtype == 4) { // LAST
                        [record appendBytes:payload length:rlen];
                    }
                    free(payload);
                    
                    if ((rtype == 1 || rtype == 4) && record.length >= 12) {
                        const uint8_t *rb = (const uint8_t *)record.bytes;
                        size_t rtotal = record.length;
                        uint64_t bseq = *(const uint64_t *)rb;
                        uint32_t bcount = *(const uint32_t *)(rb + 8);
                        size_t bpos = 12;
                        for (uint32_t bi = 0; bi < bcount && bpos < rtotal; bi++) {
                            uint8_t tag = rb[bpos++];
                            uint64_t eseq = bseq + bi;
                            if (eseq < seqMin) seqMin = eseq;
                            if (eseq > seqMax) seqMax = eseq;
                            fEntries++; totalEntries++;
                            
                            if (tag == 1) { // Put
                                uint32_t klen = 0, vlen = 0;
                                int l1 = h_decode_varint32(rb + bpos, rtotal - bpos, &klen); if (l1 <= 0) break; bpos += (size_t)l1;
                                if (bpos + klen > rtotal) break;
                                const uint8_t *kp = rb + bpos; bpos += klen;
                                int l2 = h_decode_varint32(rb + bpos, rtotal - bpos, &vlen); if (l2 <= 0) break; bpos += (size_t)l2;
                                if (bpos + vlen > rtotal) break;
                                const uint8_t *vp = rb + bpos; bpos += vlen;
                                fPuts++;
                                
                                NSData *ukData = [NSData dataWithBytes:kp length:klen];
                                SptHEntry *prev = mergedMap[ukData];
                                if (!prev || eseq > prev.seq) {
                                    if (prev) overriddenCount++;
                                    if (!prev && mergedMap.count >= 500000) {
                                        // cap hit
                                    } else {
                                        SptHEntry *e = [SptHEntry new];
                                        e.seq = eseq;
                                        e.type = 1;
                                        e.vlen = vlen;
                                        e.vPrefix = [NSData dataWithBytes:vp length:MIN((size_t)vlen, (size_t)256)];
                                        size_t vscanLen = MIN((size_t)vlen, (size_t)(1024 * 1024));
                                        for (size_t vi = 0; vi + 14 <= vscanLen; vi++) {
                                            if (vp[vi] == 's' && vp[vi+1] == 'p') {
                                                if (memcmp(vp + vi, "spotify:track:", 14) == 0) e.countTrack++;
                                                else if (memcmp(vp + vi, "spotify:playlist:", 17) == 0) e.countPlaylist++;
                                                else if (memcmp(vp + vi, "spotify:episode:", 16) == 0) e.countEpisode++;
                                            }
                                        }
                                        if (e.countTrack > 0 || e.countPlaylist > 0) {
                                            e.fullValue = [NSData dataWithBytes:vp length:vscanLen];
                                        }
                                        mergedMap[ukData] = e;
                                    }
                                }
                            } else if (tag == 0) { // Delete
                                uint32_t klen = 0;
                                int l1 = h_decode_varint32(rb + bpos, rtotal - bpos, &klen); if (l1 <= 0) break; bpos += (size_t)l1;
                                if (bpos + klen > rtotal) break;
                                const uint8_t *kp = rb + bpos; bpos += klen;
                                fDels++;
                                
                                NSData *ukData = [NSData dataWithBytes:kp length:klen];
                                SptHEntry *prev = mergedMap[ukData];
                                if (!prev || eseq > prev.seq) {
                                    if (prev) overriddenCount++;
                                    if (!prev && mergedMap.count >= 500000) {
                                        // cap hit
                                    } else {
                                        SptHEntry *e = [SptHEntry new];
                                        e.seq = eseq;
                                        e.type = 0;
                                        e.vlen = 0;
                                        mergedMap[ukData] = e;
                                    }
                                }
                            } else {
                                break;
                            }
                        }
                    }
                }
                if (lbuf) free(lbuf);
            }
            close(fd);
            spt_h_budget_log(&budget, "H: file %s kind=%s entries=%llu puts=%llu dels=%llu bytes=%lld err=%s",
                             fname.UTF8String, isLdb ? "ldb" : "log", (unsigned long long)fEntries,
                             (unsigned long long)fPuts, (unsigned long long)fDels, (long long)fst.st_size, fErr);
        }
        
        uint64_t liveCount = 0, tombstoneCount = 0;
        NSMutableDictionary<NSString *, SptHFamStat *> *famMap = [NSMutableDictionary new];
        
        // Greps setup
        NSArray<NSString *> *grepTerms = @[@"rootlist", @"folder", @"liked", @"collection", @"sort", @"position", @"revision", @"diff", @"name"];
        NSMutableDictionary<NSString *, NSMutableArray<NSData *> *> *grepHits = [NSMutableDictionary new];
        for (NSString *t in grepTerms) grepHits[t] = [NSMutableArray new];
        
        NSMutableDictionary<NSString *, NSNumber *> *plFamilyCounts = [NSMutableDictionary new];
        NSMutableSet<NSString *> *plDistinctSet = [NSMutableSet new];
        
        NSMutableArray<SptHEntry *> *liveWithTrack = [NSMutableArray new];
        NSMutableArray<NSData *> *liveWithTrackKeys = [NSMutableArray new];
        NSMutableArray<SptHEntry *> *liveWithPl = [NSMutableArray new];
        NSMutableArray<NSData *> *liveWithPlKeys = [NSMutableArray new];
        
        BOOL mentionsRootlist = NO;
        
        for (NSData *kData in mergedMap) {
            SptHEntry *e = mergedMap[kData];
            if (e.type == 1) liveCount++; else tombstoneCount++;
            
            const uint8_t *kp = (const uint8_t *)kData.bytes;
            size_t klen = kData.length;
            NSString *fam = spt_h_extract_family(kp, klen);
            if ([fam containsString:@"rootlist"]) mentionsRootlist = YES;
            
            SptHFamStat *fs = famMap[fam];
            if (!fs) {
                fs = [SptHFamStat new];
                fs.family = fam;
                fs.vlenMin = UINT32_MAX;
                fs.sampleEntries = [NSMutableArray new];
                fs.sampleKeys = [NSMutableArray new];
                fs.typeUrls = [NSMutableSet new];
                famMap[fam] = fs;
            }
            fs.keyBytes += klen;
            fs.valBytes += e.vlen;
            if (e.type == 1) {
                fs.live++;
                if (e.vlen < fs.vlenMin) fs.vlenMin = e.vlen;
                if (e.vlen > fs.vlenMax) fs.vlenMax = e.vlen;
                fs.vlenSum += e.vlen;
                if (fs.sampleEntries.count < 2) {
                    [fs.sampleEntries addObject:e];
                    [fs.sampleKeys addObject:kData];
                }
                if ([fam containsString:@"!xmeta#cache#"] && e.vPrefix) {
                    const char *vstr = (const char *)e.vPrefix.bytes;
                    size_t vlen = e.vPrefix.length;
                    for (size_t vi = 0; vi + 20 <= vlen; vi++) {
                        if (memcmp(vstr + vi, "type.googleapis.com/", 20) == 0) {
                            size_t uend = vi + 20;
                            while (uend < vlen && vstr[uend] > 32 && vstr[uend] <= 126 && vstr[uend] != 34) uend++;
                            NSString *u = [[NSString alloc] initWithBytes:vstr + vi length:uend - vi encoding:NSUTF8StringEncoding];
                            if (u && fs.typeUrls.count < 3) [fs.typeUrls addObject:u];
                            break;
                        }
                    }
                }
                
                // Greps
                NSString *kAscii = [[NSString alloc] initWithBytes:kp length:klen encoding:NSISOLatin1StringEncoding];
                if (kAscii) {
                    for (NSString *term in grepTerms) {
                        if ([kAscii containsString:term]) {
                            [grepHits[term] addObject:kData];
                            if ([term isEqualToString:@"rootlist"]) mentionsRootlist = YES;
                        }
                    }
                }
                
                // Playlist completeness
                for (size_t i = 0; i + 38 <= klen; i++) {
                    if (memcmp(kp + i, "spotify:playlist:", 17) == 0) {
                        NSString *plid = [[NSString alloc] initWithBytes:kp + i + 17 length:22 encoding:NSASCIIStringEncoding];
                        if (plid && plid.length == 22) {
                            [plDistinctSet addObject:plid];
                            NSString *fKey = [NSString stringWithFormat:@"%@ %@", fam, plid];
                            plFamilyCounts[fKey] = @(plFamilyCounts[fKey].integerValue + 1);
                        }
                    }
                }
                
                // Big refs
                if (e.countTrack > 0) {
                    [liveWithTrack addObject:e];
                    [liveWithTrackKeys addObject:kData];
                }
                if (e.countPlaylist > 0) {
                    [liveWithPl addObject:e];
                    [liveWithPlKeys addObject:kData];
                }
            } else {
                fs.dead++;
            }
        }
        
        // 5a. Stat line
        spt_h_budget_log(&budget, "H: stat tables=%d logs=%d entries=%llu distinct=%ld live=%llu tombstones=%llu overridden=%llu seq_min=%llu seq_max=%llu errors=%d",
                         tableCount, logCount, (unsigned long long)totalEntries, (long)mergedMap.count,
                         (unsigned long long)liveCount, (unsigned long long)tombstoneCount, (unsigned long long)overriddenCount,
                         (unsigned long long)(seqMin == UINT64_MAX ? 0 : seqMin), (unsigned long long)seqMax, errorCount);
        
        // 5b. Families (top 70)
        NSArray<SptHFamStat *> *sortedFams = [famMap.allValues sortedArrayUsingComparator:^NSComparisonResult(SptHFamStat *a, SptHFamStat *b) {
            if (a.live > b.live) return NSOrderedAscending;
            if (a.live < b.live) return NSOrderedDescending;
            return [a.family compare:b.family];
        }];
        spt_h_budget_log(&budget, "--- families (top 70 by live count) ---");
        NSInteger topFamCount = MIN((NSInteger)sortedFams.count, (NSInteger)70);
        for (NSInteger i = 0; i < topFamCount; i++) {
            SptHFamStat *fs = sortedFams[i];
            uint32_t vmin = (fs.vlenMin == UINT32_MAX) ? 0 : fs.vlenMin;
            uint64_t vavg = (fs.live > 0) ? (fs.vlenSum / (uint64_t)fs.live) : 0;
            spt_h_budget_log(&budget, "fam: %s live=%d dead=%d keybytes=%llu valbytes=%llu vlen_min=%u vlen_avg=%llu vlen_max=%u",
                             spt_h_redact_user(fs.family).UTF8String, fs.live, fs.dead,
                             (unsigned long long)fs.keyBytes, (unsigned long long)fs.valBytes,
                             vmin, (unsigned long long)vavg, fs.vlenMax);
        }
        
        // 5c. Greps
        spt_h_budget_log(&budget, "--- greps ---");
        for (NSString *term in grepTerms) {
            NSArray<NSData *> *hits = grepHits[term];
            spt_h_budget_log(&budget, "grep: %s n=%ld", term.UTF8String, (long)hits.count);
            NSInteger kcap = MIN((NSInteger)hits.count, (NSInteger)3);
            for (NSInteger j = 0; j < kcap; j++) {
                NSData *kd = hits[j];
                SptHEntry *e = mergedMap[kd];
                NSString *ek = spt_h_escape((const uint8_t *)kd.bytes, kd.length, 200);
                spt_h_budget_log(&budget, "grepkey: %s vlen=%u", spt_h_redact_user(ek).UTF8String, e ? e.vlen : 0);
            }
        }
        
        // 5d. Playlist completeness
        spt_h_budget_log(&budget, "--- playlist completeness ---");
        NSArray<NSString *> *sortedPlCounts = [plFamilyCounts.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSInteger ca = [plFamilyCounts[a] integerValue];
            NSInteger cb = [plFamilyCounts[b] integerValue];
            if (ca > cb) return NSOrderedAscending;
            if (ca < cb) return NSOrderedDescending;
            return [a compare:b];
        }];
        NSInteger topPlCount = MIN((NSInteger)sortedPlCounts.count, (NSInteger)60);
        int b1 = 0, b2_9 = 0, b10_49 = 0, b50_199 = 0, b200plus = 0;
        for (NSString *k in plFamilyCounts) {
            NSInteger cnt = [plFamilyCounts[k] integerValue];
            if (cnt == 1) b1++;
            else if (cnt <= 9) b2_9++;
            else if (cnt <= 49) b10_49++;
            else if (cnt <= 199) b50_199++;
            else b200plus++;
        }
        for (NSInteger i = 0; i < topPlCount; i++) {
            NSString *k = sortedPlCounts[i];
            spt_h_budget_log(&budget, "plcount: %s n=%ld", spt_h_redact_user(k).UTF8String, (long)[plFamilyCounts[k] integerValue]);
        }
        spt_h_budget_log(&budget, "plbuckets: 1=%d 2-9=%d 10-49=%d 50-199=%d 200+=%d", b1, b2_9, b10_49, b50_199, b200plus);
        spt_h_budget_log(&budget, "pldistinct: %ld", (long)plDistinctSet.count);
        
        // 5e. Big refs
        spt_h_budget_log(&budget, "--- big refs ---");
        // Sort liveWithTrack
        NSMutableArray<NSNumber *> *tIdxs = [NSMutableArray new];
        for (NSUInteger i = 0; i < liveWithTrack.count; i++) [tIdxs addObject:@(i)];
        [tIdxs sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            uint32_t ca = liveWithTrack[a.unsignedIntegerValue].countTrack;
            uint32_t cb = liveWithTrack[b.unsignedIntegerValue].countTrack;
            if (ca > cb) return NSOrderedAscending;
            if (ca < cb) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        NSInteger topT = MIN((NSInteger)tIdxs.count, (NSInteger)10);
        for (NSInteger i = 0; i < topT; i++) {
            NSUInteger idx = [tIdxs[i] unsignedIntegerValue];
            SptHEntry *e = liveWithTrack[idx];
            NSData *kd = liveWithTrackKeys[idx];
            NSString *fam = spt_h_extract_family((const uint8_t *)kd.bytes, kd.length);
            NSString *ek = spt_h_escape((const uint8_t *)kd.bytes, kd.length, 160);
            spt_h_budget_log(&budget, "ref: %s key=%s vlen=%u tracks=%u playlists=%u episodes=%u",
                             spt_h_redact_user(fam).UTF8String, spt_h_redact_user(ek).UTF8String,
                             e.vlen, e.countTrack, e.countPlaylist, e.countEpisode);
        }
        if (tIdxs.count > 0) {
            NSUInteger topIdx = [tIdxs[0] unsignedIntegerValue];
            SptHEntry *topE = liveWithTrack[topIdx];
            if (topE.fullValue) {
                const uint8_t *vb = (const uint8_t *)topE.fullValue.bytes;
                size_t vlen = topE.fullValue.length;
                size_t prevEnd = 0;
                int uriCount = 0;
                for (size_t i = 0; i + 8 <= vlen && uriCount < 20; i++) {
                    if (memcmp(vb + i, "spotify:", 8) == 0) {
                        size_t uend = i + 8;
                        while (uend < vlen && vb[uend] > 32 && vb[uend] <= 126 && vb[uend] != 34 && vb[uend] != '\'') uend++;
                        NSString *uri = [[NSString alloc] initWithBytes:vb + i length:uend - i encoding:NSUTF8StringEncoding];
                        if (uri) {
                            size_t gap = (i >= prevEnd) ? (i - prevEnd) : 0;
                            spt_h_budget_log(&budget, "refuri: off=%zu gap=%zu %s", i, gap, spt_h_redact_user(uri).UTF8String);
                            prevEnd = uend;
                            uriCount++;
                            i = uend;
                        }
                    }
                }
            }
        }
        
        // Sort liveWithPl
        NSMutableArray<NSNumber *> *pIdxs = [NSMutableArray new];
        for (NSUInteger i = 0; i < liveWithPl.count; i++) [pIdxs addObject:@(i)];
        [pIdxs sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            uint32_t ca = liveWithPl[a.unsignedIntegerValue].countPlaylist;
            uint32_t cb = liveWithPl[b.unsignedIntegerValue].countPlaylist;
            if (ca > cb) return NSOrderedAscending;
            if (ca < cb) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        NSInteger topP = MIN((NSInteger)pIdxs.count, (NSInteger)10);
        for (NSInteger i = 0; i < topP; i++) {
            NSUInteger idx = [pIdxs[i] unsignedIntegerValue];
            SptHEntry *e = liveWithPl[idx];
            NSData *kd = liveWithPlKeys[idx];
            NSString *fam = spt_h_extract_family((const uint8_t *)kd.bytes, kd.length);
            NSString *ek = spt_h_escape((const uint8_t *)kd.bytes, kd.length, 160);
            spt_h_budget_log(&budget, "ref: %s key=%s vlen=%u tracks=%u playlists=%u episodes=%u",
                             spt_h_redact_user(fam).UTF8String, spt_h_redact_user(ek).UTF8String,
                             e.vlen, e.countTrack, e.countPlaylist, e.countEpisode);
        }
        if (pIdxs.count > 0) {
            NSUInteger topIdx = [pIdxs[0] unsignedIntegerValue];
            SptHEntry *topE = liveWithPl[topIdx];
            if (topE.fullValue) {
                const uint8_t *vb = (const uint8_t *)topE.fullValue.bytes;
                size_t vlen = topE.fullValue.length;
                size_t prevEnd = 0;
                int uriCount = 0;
                for (size_t i = 0; i + 8 <= vlen && uriCount < 20; i++) {
                    if (memcmp(vb + i, "spotify:", 8) == 0) {
                        size_t uend = i + 8;
                        while (uend < vlen && vb[uend] > 32 && vb[uend] <= 126 && vb[uend] != 34 && vb[uend] != '\'') uend++;
                        NSString *uri = [[NSString alloc] initWithBytes:vb + i length:uend - i encoding:NSUTF8StringEncoding];
                        if (uri) {
                            size_t gap = (i >= prevEnd) ? (i - prevEnd) : 0;
                            spt_h_budget_log(&budget, "refuri: off=%zu gap=%zu %s", i, gap, spt_h_redact_user(uri).UTF8String);
                            prevEnd = uend;
                            uriCount++;
                            i = uend;
                        }
                    }
                }
            }
        }
        
        // 5f. Samples (top 30 families, 2 live samples each)
        spt_h_budget_log(&budget, "--- samples (top 30 families, 2 live samples each) ---");
        NSInteger sampleFamCount = MIN((NSInteger)sortedFams.count, (NSInteger)30);
        for (NSInteger i = 0; i < sampleFamCount; i++) {
            SptHFamStat *fs = sortedFams[i];
            for (NSUInteger si = 0; si < fs.sampleEntries.count; si++) {
                SptHEntry *e = fs.sampleEntries[si];
                NSData *kd = fs.sampleKeys[si];
                NSString *ek = spt_h_escape((const uint8_t *)kd.bytes, kd.length, 160);
                NSString *v0 = (e.vPrefix) ? spt_h_hex((const uint8_t *)e.vPrefix.bytes, e.vPrefix.length, 32) : @"";
                
                // Runs of 5 or more printable ASCII from vPrefix
                NSMutableArray<NSString *> *runs = [NSMutableArray new];
                if (e.vPrefix) {
                    const uint8_t *vp = (const uint8_t *)e.vPrefix.bytes;
                    size_t vlen = e.vPrefix.length;
                    size_t rstart = 0;
                    BOOL inRun = NO;
                    for (size_t j = 0; j < vlen && runs.count < 4; j++) {
                        if (vp[j] >= 32 && vp[j] <= 126) {
                            if (!inRun) { rstart = j; inRun = YES; }
                        } else {
                            if (inRun) {
                                size_t rlen = j - rstart;
                                if (rlen >= 5 && runs.count < 4) {
                                    size_t cut = MIN(rlen, (size_t)40);
                                    NSString *rs = [[NSString alloc] initWithBytes:vp + rstart length:cut encoding:NSUTF8StringEncoding];
                                    if (rs) [runs addObject:rs];
                                }
                                inRun = NO;
                            }
                        }
                    }
                }
                NSString *runsStr = [runs componentsJoinedByString:@" | "];
                spt_h_budget_log(&budget, "sample: %s key=%s vlen=%u v0=%s runs=%s",
                                 spt_h_redact_user(fs.family).UTF8String, spt_h_redact_user(ek).UTF8String,
                                 e.vlen, v0.UTF8String, runsStr.UTF8String);
            }
            if (fs.typeUrls.count > 0) {
                for (NSString *u in fs.typeUrls) {
                    spt_h_budget_log(&budget, "typeurl: %s %s", spt_h_redact_user(fs.family).UTF8String, u.UTF8String);
                }
            }
        }
        
        // 5g. Summary LAST
        spt_probe_log("H", "--- H summary --- live=%llu families=%ld rootlist=%s pldistinct=%ld bytes_read=%lld",
                      (unsigned long long)liveCount, (long)famMap.count, mentionsRootlist ? "YES" : "NO",
                      (long)plDistinctSet.count, (long long)s_hTotalBytesRead);
    });
}

#endif
