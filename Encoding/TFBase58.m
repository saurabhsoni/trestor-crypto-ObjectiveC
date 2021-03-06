//
//  TFBase58.m
//  Trestor Wallet Crypto
//
//  Created by Ashish Gogna on 1/30/15.
//  Code Taken from - https://github.com/chain-engineering/chain-ios-wallet-demo/blob/master/Pods/CoreBitcoin/CoreBitcoin/BTCBase58.m
//

#import "TFBase58.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonDigest.h>
#import <openssl/bn.h>
#include <openssl/ripemd.h>
#include <openssl/evp.h>

@implementation TFBase58

static const char* BTCBase58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
//static const char* BTCBase58Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz123456789";
static const unsigned char _BTCZeroString256[32] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};

- (id)init
{
    //Test (working)
    //Encode
    /*
    NSString *test = @"1234567";
    NSData *d1 = [test dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableData *d2 = [d1 mutableCopy];
    NSString *enc = BTCBase58CheckStringWithData(d1);
    NSLog(@"%@", d1);
     
    //Decode
    NSData *dec = BTCDataFromBase58Check(enc);
    NSLog(@"%@", dec);
    */
     
    return self;
}

NSMutableData* BTCDataFromBase58(NSString* string)
{
    return BTCDataFromBase58CString([string cStringUsingEncoding:NSASCIIStringEncoding]);
}

NSMutableData* BTCDataFromBase58Check(NSString* string)
{
    return BTCDataFromBase58CheckCString([string cStringUsingEncoding:NSASCIIStringEncoding]);
}

NSMutableData* BTCDataFromBase58CString(const char* cstring)
{
    if (cstring == NULL) return nil;
    
    // empty string -> empty data.
    if (cstring[0] == '\0') return [NSData data];
    
    NSMutableData* result = nil;
    
    BN_CTX* pctx = BN_CTX_new();
    __block BIGNUM bn58;   BN_init(&bn58);   BN_set_word(&bn58, 58);
    __block BIGNUM bn;     BN_init(&bn);     BN_zero(&bn);
    __block BIGNUM bnChar; BN_init(&bnChar);
    
    void(^finish)() = ^{
        if (pctx) BN_CTX_free(pctx);
        BN_clear_free(&bn58);
        BN_clear_free(&bn);
        BN_clear_free(&bnChar);
    };
    
    while (isspace(*cstring)) cstring++;
    
    
    // Convert big endian string to bignum
    for (const char* p = cstring; *p; p++)
    {
        const char* p1 = strchr(BTCBase58Alphabet, *p);
        if (p1 == NULL)
        {
            while (isspace(*p))
                p++;
            if (*p != '\0')
            {
                finish();
                return nil;
            }
            break;
        }
        
        BN_set_word(&bnChar, p1 - BTCBase58Alphabet);
        
        if (!BN_mul(&bn, &bn, &bn58, pctx))
        {
            finish();
            return nil;
        }
        
        if (!BN_add(&bn, &bn, &bnChar))
        {
            finish();
            return nil;
        }
    }
    
    // Get bignum as little endian data
    
    NSMutableData* bndata = nil;
    {
        size_t bnsize = BN_bn2mpi(&bn, NULL);
        if (bnsize <= 4)
        {
            bndata = [NSMutableData data];
        }
        else
        {
            bndata = [NSMutableData dataWithLength:bnsize];
            BN_bn2mpi(&bn, bndata.mutableBytes);
            [bndata replaceBytesInRange:NSMakeRange(0, 4) withBytes:NULL length:0];
            BTCDataReverse(bndata);
        }
    }
    size_t bnsize = bndata.length;
    
    // Trim off sign byte if present
    if (bnsize >= 2
        && ((unsigned char*)bndata.bytes)[bnsize - 1] == 0
        && ((unsigned char*)bndata.bytes)[bnsize - 2] >= 0x80)
    {
        bnsize -= 1;
        [bndata setLength:bnsize];
    }
    
    // Restore leading zeros
    int nLeadingZeros = 0;
    for (const char* p = cstring; *p == BTCBase58Alphabet[0]; p++)
        nLeadingZeros++;
    
    result = [NSMutableData dataWithLength:nLeadingZeros + bnsize];
    
    // Copy the bignum to the beginning of array. We'll reverse it then and zeros will become leading zeros.
    [result replaceBytesInRange:NSMakeRange(0, bnsize) withBytes:bndata.bytes length:bnsize];
    
    // Convert little endian data to big endian
    BTCDataReverse(result);
    
    finish();
    
    return result;
}

NSMutableData* BTCDataFromBase58CheckCString(const char* cstring)
{
    if (cstring == NULL) return nil;
    
    NSMutableData* result = BTCDataFromBase58CString(cstring);
    size_t length = result.length;
    if (length < 4)
    {
        return nil;
    }
    NSData* hash = BTCHash256([result subdataWithRange:NSMakeRange(0, length - 4)]);
    
    // Last 4 bytes should be equal first 4 bytes of the hash.
    if (memcmp(hash.bytes, result.bytes + length - 4, 4) != 0)
    {
        return nil;
    }
    [result setLength:length - 4];
    return result;
}


char* BTCBase58CStringWithData(NSData* data)
{
    if (!data) return NULL;
    
    BN_CTX* pctx = BN_CTX_new();
    __block BIGNUM bn58; BN_init(&bn58); BN_set_word(&bn58, 58);
    __block BIGNUM bn0;  BN_init(&bn0);  BN_zero(&bn0);
    __block BIGNUM bn; BN_init(&bn); BN_zero(&bn);
    __block BIGNUM dv; BN_init(&dv); BN_zero(&dv);
    __block BIGNUM rem; BN_init(&rem); BN_zero(&rem);
    
    void(^finish)() = ^{
        if (pctx) BN_CTX_free(pctx);
        BN_clear_free(&bn58);
        BN_clear_free(&bn0);
        BN_clear_free(&bn);
        BN_clear_free(&dv);
        BN_clear_free(&rem);
    };
    
    // Convert big endian data to little endian.
    // Extra zero at the end make sure bignum will interpret as a positive number.
    NSMutableData* tmp = BTCReversedMutableData(data);
    tmp.length += 1;
    
    // Convert little endian data to bignum
    {
        NSUInteger size = tmp.length;
        NSMutableData* mdata = [tmp mutableCopy];
        
        // Reverse to convert to OpenSSL bignum endianess
        BTCDataReverse(mdata);
        
        // BIGNUM's byte stream format expects 4 bytes of
        // big endian size data info at the front
        [mdata replaceBytesInRange:NSMakeRange(0, 0) withBytes:"\0\0\0\0" length:4];
        unsigned char* bytes = mdata.mutableBytes;
        bytes[0] = (size >> 24) & 0xff;
        bytes[1] = (size >> 16) & 0xff;
        bytes[2] = (size >> 8) & 0xff;
        bytes[3] = (size >> 0) & 0xff;
        
        BN_mpi2bn(bytes, (int)mdata.length, &bn);
    }
    
    // Expected size increase from base58 conversion is approximately 137%
    // use 138% to be safe
    NSMutableData* stringData = [NSMutableData dataWithCapacity:data.length*138/100 + 1];
    
    while (BN_cmp(&bn, &bn0) > 0)
    {
        if (!BN_div(&dv, &rem, &bn, &bn58, pctx))
        {
            finish();
            return nil;
        }
        BN_copy(&bn, &dv);
        unsigned long c = BN_get_word(&rem);
        [stringData appendBytes:BTCBase58Alphabet + c length:1];
    }
    finish();
    
    // Leading zeroes encoded as base58 ones ("1")
    const unsigned char* pbegin = data.bytes;
    const unsigned char* pend = data.bytes + data.length;
    for (const unsigned char* p = pbegin; p < pend && *p == 0; p++)
    {
        [stringData appendBytes:BTCBase58Alphabet + 0 length:1];
    }
    
    // Convert little endian std::string to big endian
    BTCDataReverse(stringData);
    
    [stringData appendBytes:"" length:1];
    
    char* r = malloc(stringData.length);
    memcpy(r, stringData.bytes, stringData.length);
    BTCDataClear(stringData);
    return r;
}

// String in Base58 with checksum
char* BTCBase58CheckCStringWithData(NSData* immutabledata)
{
    if (!immutabledata) return NULL;
    // add 4-byte hash check to the end
    NSMutableData* data = [immutabledata mutableCopy];
    NSData* checksum = BTCHash256(data);
    [data appendBytes:checksum.bytes length:4];
    char* result = BTCBase58CStringWithData(data);
    BTCDataClear(data);
    return result;
}

NSString* BTCBase58StringWithData(NSData* data)
{
    if (!data) return nil;
    char* s = BTCBase58CStringWithData(data);
    id r = [NSString stringWithCString:s encoding:NSASCIIStringEncoding];
    BTCSecureClearCString(s);
    free(s);
    return r;
}


NSString* BTCBase58CheckStringWithData(NSData* data)
{
    if (!data) return nil;
    char* s = BTCBase58CheckCStringWithData(data);
    id r = [NSString stringWithCString:s encoding:NSASCIIStringEncoding];
    BTCSecureClearCString(s);
    free(s);
    return r;
}



//////////////////////////////////////////////////BTCDATA////////////////////////////////////////////////////////
void *BTCSecureMemset(void *v, unsigned char c, size_t n)
{
    if (!v) return v;
    volatile unsigned char *p = v;
    while (n--)
        *p++ = c;
    
    return v;
}

void BTCSecureClearCString(char *s)
{
    if (!s) return;
    BTCSecureMemset(s, 0, strlen(s));
}

void *BTCCreateRandomBytesOfLength(size_t length)
{
    FILE *fp = fopen("/dev/random", "r");
    if (!fp)
    {
        NSLog(@"NSData+BTC: cannot fopen /dev/random");
        exit(-1);
        return NULL;
    }
    char* bytes = (char*)malloc(length);
    for (int i = 0; i < length; i++)
    {
        char c = fgetc(fp);
        bytes[i] = c;
    }
    
    fclose(fp);
    return bytes;
}

// Returns data with securely random bytes of the specified length. Uses /dev/random.
NSData* BTCRandomDataWithLength(NSUInteger length)
{
    void *bytes = BTCCreateRandomBytesOfLength(length);
    if (!bytes) return nil;
    return [[NSData alloc] initWithBytesNoCopy:bytes length:length];
}

// Returns data produced by flipping the coin as proposed by Dan Kaminsky:
// https://gist.github.com/PaulCapestany/6148566

static inline int BTCCoinFlip()
{
    __block int n = 0;
    //int c = 0;
    dispatch_time_t then = dispatch_time(DISPATCH_TIME_NOW, 999000ull);
    
    // We need to increase variance of number of flips, so we force system to schedule some threads
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (dispatch_time(DISPATCH_TIME_NOW, 0) <= then)
        {
            n = !n;
        }
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (dispatch_time(DISPATCH_TIME_NOW, 0) <= then)
        {
            n = !n;
        }
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (dispatch_time(DISPATCH_TIME_NOW, 0) <= then)
        {
            n = !n;
        }
    });
    
    while (dispatch_time(DISPATCH_TIME_NOW, 0) <= then)
    {
        //c++;
        n = !n; // flipping the coin
    }
    //NSLog(@"Flips: %d", c);
    return n;
}

// Simple Von Neumann debiasing - throwing away two flips that return the same value.
static inline int BTCFairCoinFlip()
{
    while(1)
    {
        int a = BTCCoinFlip();
        if (a != BTCCoinFlip())
        {
            return a;
        }
    }
}

NSData* BTCCoinFlipDataWithLength(NSUInteger length)
{
    NSMutableData* data = [NSMutableData dataWithLength:length];
    unsigned char* bytes = data.mutableBytes;
    for (int i = 0; i < length; i++)
    {
        unsigned char byte = 0;
        int bits = 8;
        while(bits--)
        {
            byte <<= 1;
            byte |= BTCFairCoinFlip();
        }
        bytes[i] = byte;
    }
    return data;
}


// Creates data with zero-terminated string in UTF-8 encoding.
NSData* BTCDataWithUTF8String(const char* utf8string)
{
    return [[NSData alloc] initWithBytes:utf8string length:strlen(utf8string)];
}

// Init with hex string (lower- or uppercase, with optional 0x prefix)
NSData* BTCDataWithHexString(NSString* hexString)
{
    return BTCDataWithHexCString([hexString cStringUsingEncoding:NSASCIIStringEncoding]);
}

// Init with zero-terminated hex string (lower- or uppercase, with optional 0x prefix)
NSData* BTCDataWithHexCString(const char* hexCString)
{
    if (hexCString == NULL) return nil;
    
    const unsigned char *psz = (const unsigned char*)hexCString;
    
    while (isspace(*psz)) psz++;
    
    // Skip optional 0x prefix
    if (psz[0] == '0' && tolower(psz[1]) == 'x') psz += 2;
    
    while (isspace(*psz)) psz++;
    
    size_t len = strlen((const char*)psz);
    
    // If the string is not full number of bytes (each byte 2 hex characters), return nil.
    if (len % 2 != 0) return nil;
    
    unsigned char* buf = (unsigned char*)malloc(len/2);
    
    static const signed char digits[256] = {
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, -1, -1, -1, -1, -1, -1,
        -1,0xa,0xb,0xc,0xd,0xe,0xf, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1,0xa,0xb,0xc,0xd,0xe,0xf, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
    };
    
    unsigned char* bufpointer = buf;
    
    while (1)
    {
        unsigned char c1 = (unsigned char)*psz++;
        signed char n1 = digits[c1];
        if (n1 == (signed char)-1) break; // break when null-terminator is hit
        
        unsigned char c2 = (unsigned char)*psz++;
        signed char n2 = digits[c2];
        if (n2 == (signed char)-1) break; // break when null-terminator is hit
        
        *bufpointer = (unsigned char)((n1 << 4) | n2);
        bufpointer++;
    }
    
    return [[NSData alloc] initWithBytesNoCopy:buf length:len/2];
}

NSData* BTCReversedData(NSData* data)
{
    return BTCReversedMutableData(data);
}

NSMutableData* BTCReversedMutableData(NSData* data)
{
    if (!data) return nil;
    NSMutableData* md = [NSMutableData dataWithData:data];
    BTCDataReverse(md);
    return md;
}

void BTCReverseBytesLength(void* bytes, NSUInteger length)
{
    // K&R
    if (length <= 1) return;
    unsigned char* buf = bytes;
    unsigned char byte;
    NSUInteger i, j;
    for (i = 0, j = length - 1; i < j; i++, j--)
    {
        byte = buf[i];
        buf[i] = buf[j];
        buf[j] = byte;
    }
}

// Reverses byte order in the internal buffer of mutable data object.
void BTCDataReverse(NSMutableData* self)
{
    BTCReverseBytesLength(self.mutableBytes, self.length);
}

// Clears contents of the data to prevent leaks through swapping or buffer-overflow attacks.
void BTCDataClear(NSMutableData* self)
{
    [self resetBytesInRange:NSMakeRange(0, self.length)];
}

NSData* BTCSHA1(NSData* data)
{
    if (!data) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], digest);
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

NSData* BTCSHA256(NSData* data)
{
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

NSData* BTCSHA256Concat(NSData* data1, NSData* data2)
{
    if (!data1 || !data2) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, [data1 bytes], (CC_LONG)[data1 length]);
    CC_SHA256_Update(&ctx, [data2 bytes], (CC_LONG)[data2 length]);
    CC_SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

NSData* BTCHash256(NSData* data)
{
    if (!data) return nil;
    unsigned char digest1[CC_SHA256_DIGEST_LENGTH];
    unsigned char digest2[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest1);
    CC_SHA256(digest1, CC_SHA256_DIGEST_LENGTH, digest2);
    return [NSData dataWithBytes:digest2 length:CC_SHA256_DIGEST_LENGTH];
}

NSData* BTCHash256Concat(NSData* data1, NSData* data2)
{
    if (!data1 || !data2) return nil;
    
    unsigned char digest1[CC_SHA256_DIGEST_LENGTH];
    unsigned char digest2[CC_SHA256_DIGEST_LENGTH];
    
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, [data1 bytes], (CC_LONG)[data1 length]);
    CC_SHA256_Update(&ctx, [data2 bytes], (CC_LONG)[data2 length]);
    CC_SHA256_Final(digest1, &ctx);
    
    CC_SHA256(digest1, CC_SHA256_DIGEST_LENGTH, digest2);
    return [NSData dataWithBytes:digest2 length:CC_SHA256_DIGEST_LENGTH];
}

NSData* BTCZero160()
{
    return [NSData dataWithBytes:_BTCZeroString256 length:20];
}

NSData* BTCZero256()
{
    return [NSData dataWithBytes:_BTCZeroString256 length:32];
}

const unsigned char* BTCZeroString256()
{
    return _BTCZeroString256;
}

NSData* BTCHMACSHA512(NSData* key, NSData* data)
{
    if (!key) return nil;
    if (!data) return nil;
    unsigned char digest[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, key.bytes, key.length, data.bytes, data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA512_DIGEST_LENGTH];
}

#if BTCDataRequiresOpenSSL

NSData* BTCRIPEMD160(NSData* data)
{
    if (!data) return nil;
    unsigned char digest[RIPEMD160_DIGEST_LENGTH];
    RIPEMD160([data bytes], (size_t)[data length], digest);
    return [NSData dataWithBytes:digest length:RIPEMD160_DIGEST_LENGTH];
}

NSData* BTCHash160(NSData* data)
{
    if (!data) return nil;
    unsigned char digest1[CC_SHA256_DIGEST_LENGTH];
    unsigned char digest2[RIPEMD160_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest1);
    RIPEMD160(digest1, CC_SHA256_DIGEST_LENGTH, digest2);
    NSData* result = [NSData dataWithBytes:digest2 length:RIPEMD160_DIGEST_LENGTH];
    BTCSecureMemset(digest1, 0, CC_SHA256_DIGEST_LENGTH);
    BTCSecureMemset(digest2, 0, RIPEMD160_DIGEST_LENGTH);
    return result;
}

#endif



NSString* BTCHexStringFromDataWithFormat(NSData* data, const char* format)
{
    if (!data) return nil;
    
    NSUInteger length = data.length;
    if (length == 0) return @"";
    
    NSMutableData* resultdata = [NSMutableData dataWithLength:length * 2];
    char *dest = resultdata.mutableBytes;
    unsigned const char *src = data.bytes;
    for (int i = 0; i < length; ++i)
    {
        sprintf(dest + i*2, format, (unsigned int)(src[i]));
    }
    return [[NSString alloc] initWithData:resultdata encoding:NSASCIIStringEncoding];
}

NSString* BTCHexStringFromData(NSData* data)
{
    return BTCHexStringFromDataWithFormat(data, "%02x");
}

NSString* BTCUppercaseHexStringFromData(NSData* data)
{
    return BTCHexStringFromDataWithFormat(data, "%02X");
}

// Hashes input with salt using specified number of rounds and the minimum amount of memory (rounded up to a whole number of 256-bit blocks).
// Actual number of hash function computations is a number of rounds multiplied by a number of 256-bit blocks.
// So rounds=1 for 256 Mb of memory would mean 8M hash function calculations (8M blocks by 32 byte to form 256 Mb total).
// Uses SHA256 as an internal hash function.
// Password and salt are hashed before being placed in the first block.
// The whole memory region is hashed after all rounds to generate the result.
// Based on proposal by Sergio Demian Lerner http://bitslog.files.wordpress.com/2013/12/memohash-v0-3.pdf
// Returns a mutable data, so you can cleanup the memory when needed.
NSMutableData* BTCMemoryHardKDF256(NSData* password, NSData* salt, unsigned int rounds, unsigned int numberOfBytes)
{
    const unsigned int blockSize = CC_SHA256_DIGEST_LENGTH;
    
    // Will be used for intermediate hash computation
    unsigned char block[blockSize];
    
    // Context for computing hashes.
    CC_SHA256_CTX ctx;
    
    // Round up the required memory to integral number of blocks
    unsigned int numberOfBlocks = numberOfBytes / blockSize;
    if (numberOfBytes % blockSize) numberOfBlocks++;
    numberOfBytes = numberOfBlocks * blockSize;
    
    // Make sure we have at least 1 round
    rounds = rounds ? rounds : 1;
    
    // Allocate the required memory
    NSMutableData* space = [NSMutableData dataWithLength:numberOfBytes];
    unsigned char* spaceBytes = space.mutableBytes;
    
    // Hash the password with the salt to produce the initial seed
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, password.bytes, (CC_LONG)password.length);
    CC_SHA256_Update(&ctx, salt.bytes, (CC_LONG)salt.length);
    CC_SHA256_Final(block, &ctx);
    
    // Set the seed to the first block
    memcpy(spaceBytes, block, blockSize);
    
    // Produce a chain of hashes to fill the memory with initial data
    for (unsigned int  i = 1; i < numberOfBlocks; i++)
    {
        // Put a hash of the previous block into the next block.
        CC_SHA256_Init(&ctx);
        CC_SHA256_Update(&ctx, spaceBytes + (i - 1) * blockSize, blockSize);
        CC_SHA256_Final(block, &ctx);
        memcpy(spaceBytes + i * blockSize, block, blockSize);
    }
    
    // Each round consists of hashing the entire space block by block.
    for (unsigned int r = 0; r < rounds; r++)
    {
        // For each block, update it with the hash of the previous block
        // mixed with the randomly shifted block around the current one.
        for (unsigned int b = 0; b < numberOfBlocks; b++)
        {
            unsigned int prevb = (numberOfBlocks + b - 1) % numberOfBlocks;
            
            // Interpret the previous block as an integer to provide some randomness to memory location.
            // This reduces potential for memory access optimization.
            // We are simplifying a task here by simply taking first 64 bits instead of full 256 bits.
            // In theory it may give some room for optimization, but it would be equivalent to a slightly more efficient prediction of the next block,
            // which does not remove the need to store all blocks in memory anyway.
            // Also, this optimization would be meaningless if the amount of memory is a power of two. E.g. 16, 32, 64 or 128 Mb.
            unsigned long long offset = (*((unsigned long long*)(spaceBytes + prevb * blockSize))) % (numberOfBlocks - 1); // (N-1) is taken to exclude prevb block.
            
            // Calculate actual index relative to the current block.
            offset = (b + offset) % numberOfBlocks;
            
            // Mix previous block with a random one.
            CC_SHA256_Init(&ctx);
            CC_SHA256_Update(&ctx, spaceBytes + prevb * blockSize, blockSize); // mix previous block
            CC_SHA256_Update(&ctx, spaceBytes + offset * blockSize, blockSize); // mix random block around the current one
            CC_SHA256_Final(block, &ctx);
            memcpy(spaceBytes + b * blockSize, block, blockSize);
        }
    }
    
    // Hash the whole space to arrive at a final derived key.
    CC_SHA256_Init(&ctx);
    for (unsigned int b = 0; b < numberOfBlocks; b++)
    {
        CC_SHA256_Update(&ctx, spaceBytes + b * blockSize, blockSize);
    }
    CC_SHA256_Final(block, &ctx);
    
    NSMutableData* derivedKey = [NSMutableData dataWithBytes:block length:blockSize];
    
    // Clean all the buffers to leave no traces of sensitive data
    BTCSecureMemset(&ctx, 0, sizeof(ctx));
    BTCSecureMemset(block, 0, blockSize);
    BTCSecureMemset(spaceBytes, 0, numberOfBytes);
    
    return derivedKey;
}



// Hashes input with salt using specified number of rounds and the minimum amount of memory (rounded up to a whole number of 128-bit blocks)
NSMutableData* BTCMemoryHardAESKDF(NSData* password, NSData* salt, unsigned int rounds, unsigned int numberOfBytes)
{
    // The idea is to use a highly optimized AES implementation in CBC mode to quickly transform a lot of memory.
    // For the first round, a SHA256(password+salt) is used as AES key and SHA256(key+salt) is used as Initialization Vector (IV).
    // After each round, last 256 bits of space are hashed with IV to produce new IV for the next round. Key remains the same.
    // After the final round, last 256 bits are hashed with the AES key to arrive at the resulting key.
    // This is based on proposal by Sergio Demian Lerner http://bitslog.files.wordpress.com/2013/12/memohash-v0-3.pdf
    // More specifically, on his SeqMemoHash where he shows that when number of rounds is equal to number of memory blocks,
    // hash function is strictly memory hard: any less memory than N blocks will make computation impossible.
    // If less than N number of rounds is used, execution time grows exponentially with number of rounds, thus quickly making memory/time tradeoff
    // increasingly towards choosing an optimal amount of memory.
    
    // 1 round can be optimized to using just one small block of memory for block cipher operation (n = 1).
    // 2 rounds can reduce memory to 2 blocks, but the 2nd round would need recomputation of the 1st round in parallel (n = 1 + (1 + 1) = 3).
    // 3 rounds can reduce memory to 3 blocks, but the 3rd round would need recomputation of the 2nd round in parallel (n = 3 + (1 + 3) = 7).
    // k-th round can reduce memory to k blocks, the k-th round would need recomputation of the (k-1)-th round in parallel (n(k) = n(k-1) + (1 + n(k-1)) = 1 + 2*n(k-1))
    // Ultimately, k rounds with N blocks of memory would need at minimum k blocks of memory at expense of (2^k - 1) rounds.
    
    const unsigned int digestSize = CC_SHA256_DIGEST_LENGTH;
    const unsigned int blockSize = 128/8;
    
    // Round up the required memory to integral number of blocks
    {
        if (numberOfBytes < digestSize) numberOfBytes = digestSize;
        unsigned int numberOfBlocks = numberOfBytes / blockSize;
        if (numberOfBytes % blockSize) numberOfBlocks++;
        numberOfBytes = numberOfBlocks * blockSize;
    }
    
    // Make sure we have at least 3 rounds (1 round would be equivalent to using just 32 bytes of memory; 2 rounds would become 3 rounds if memory was reduced to 32 bytes)
    if (rounds < 3) rounds = 3;
    
    // Will be used for intermediate hash computation
    unsigned char key[digestSize];
    unsigned char iv[digestSize];
    
    // Context for computing hashes.
    CC_SHA256_CTX ctx;
    
    // Allocate the required memory
    NSMutableData* space = [NSMutableData dataWithLength:numberOfBytes + blockSize]; // extra block for the cipher.
    unsigned char* spaceBytes = space.mutableBytes;
    
    // key = SHA256(password + salt)
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, password.bytes, (CC_LONG)password.length);
    CC_SHA256_Update(&ctx, salt.bytes, (CC_LONG)salt.length);
    CC_SHA256_Final(key, &ctx);
    
    // iv = SHA256(key + salt)
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, key, (CC_LONG)digestSize);
    CC_SHA256_Update(&ctx, salt.bytes, (CC_LONG)salt.length);
    CC_SHA256_Final(iv, &ctx);
    
    // Set the space to 1010101010...
    memset(spaceBytes, (1 + 4 + 16 + 64), numberOfBytes);
    
    // Each round consists of encrypting the entire space using AES-CBC
    BOOL failed = NO;
    for (unsigned int r = 0; r < rounds; r++)
    {
        if (1) // Apple implementation - slightly faster than OpenSSL one.
        {
            size_t dataOutMoved = 0;
            CCCryptorStatus cryptstatus = CCCrypt(
                                                  kCCEncrypt,                  // CCOperation op,         /* kCCEncrypt, kCCDecrypt */
                                                  kCCAlgorithmAES,             // CCAlgorithm alg,        /* kCCAlgorithmAES128, etc. */
                                                  kCCOptionPKCS7Padding,       // CCOptions options,      /* kCCOptionPKCS7Padding, etc. */
                                                  key,                         // const void *key,
                                                  digestSize,                  // size_t keyLength,
                                                  iv,                          // const void *iv,         /* optional initialization vector */
                                                  spaceBytes,                  // const void *dataIn,     /* optional per op and alg */
                                                  numberOfBytes,               // size_t dataInLength,
                                                  spaceBytes,                  // void *dataOut,          /* data RETURNED here */
                                                  numberOfBytes + blockSize,   // size_t dataOutAvailable,
                                                  &dataOutMoved                // size_t *dataOutMoved
                                                  );
            
            if (cryptstatus != kCCSuccess || dataOutMoved != (numberOfBytes + blockSize))
            {
                failed = YES;
                break;
            }
        }
        else // OpenSSL implementation
        {
            EVP_CIPHER_CTX evpctx;
            int outlen1, outlen2;
            
            EVP_EncryptInit(&evpctx, EVP_aes_256_cbc(), key, iv);
            EVP_EncryptUpdate(&evpctx, spaceBytes, &outlen1, spaceBytes, (int)numberOfBytes);
            EVP_EncryptFinal(&evpctx, spaceBytes + outlen1, &outlen2);
            
            if (outlen1 != numberOfBytes || outlen2 != blockSize)
            {
                failed = YES;
                break;
            }
        }
        
        // iv2 = SHA256(iv1 + tail)
        CC_SHA256_Init(&ctx);
        CC_SHA256_Update(&ctx, iv, digestSize); // mix the current IV.
        CC_SHA256_Update(&ctx, spaceBytes + numberOfBytes - digestSize, digestSize); // mix in last 256 bits.
        CC_SHA256_Final(iv, &ctx);
    }
    
    NSMutableData* derivedKey = nil;
    
    if (!failed)
    {
        // derivedKey = SHA256(key + tail)
        CC_SHA256_Init(&ctx);
        CC_SHA256_Update(&ctx, key, digestSize); // mix the current key.
        CC_SHA256_Update(&ctx, spaceBytes + numberOfBytes - digestSize, digestSize); // mix in last 256 bits.
        CC_SHA256_Final(key, &ctx);
        
        derivedKey = [NSMutableData dataWithBytes:key length:digestSize];
    }
    
    // Clean all the buffers to leave no traces of sensitive data
    BTCSecureMemset(&ctx,       0, sizeof(ctx));
    BTCSecureMemset(key,        0, digestSize);
    BTCSecureMemset(iv,         0, digestSize);
    BTCSecureMemset(spaceBytes, 0, numberOfBytes + blockSize);
    
    return derivedKey;
    
}





// Probabilistic memory-hard KDF with 256-bit output and only one difficulty parameter - amount of memory.
// Actual amount of memory is rounded to a whole number of 256-bit blocks.
// Uses SHA512 as internal hash function.
// Computational time is proportional to amount of memory.
// Brutefore with half the memory raises amount of hash computations quadratically.
NSMutableData* BTCJerk256(NSData* password, NSData* salt, unsigned int numberOfBytes)
{
    @autoreleasepool {
        
        const unsigned int blockSize = CC_SHA512_DIGEST_LENGTH / 2;
        
        // Round up the required memory to integral number of blocks.
        // Minimum size is 512 bits.
        {
            if (numberOfBytes < blockSize*2) numberOfBytes = blockSize*2;
            unsigned int numberOfBlocks = numberOfBytes / blockSize;
            if (numberOfBytes % blockSize) numberOfBlocks++;
            numberOfBytes = numberOfBlocks * blockSize;
        }
        
        // Context for computing hashes.
        CC_SHA512_CTX ctx;
        
        // Allocate the required memory
        NSMutableData* space = [NSMutableData dataWithLength:numberOfBytes + blockSize]; // a bit of extra memory for temporary storage of SHA512
        unsigned char* spaceBytes = space.mutableBytes;
        
        // Initial two blocks = SHA512(password + salt)
        CC_SHA512_Init(&ctx);
        CC_SHA512_Update(&ctx, password.bytes, (CC_LONG)password.length);
        CC_SHA512_Update(&ctx, salt.bytes, (CC_LONG)salt.length);
        CC_SHA512_Final(spaceBytes, &ctx);
        
        // Take first 256 bits as a key to mix in during hashing below.
        NSData* key = [NSData dataWithBytes:spaceBytes length:blockSize];
        const unsigned char* keyBytes = key.bytes;
        
        // At each step we try reinforce memory requirement while spending as little time as possible.
        // Making each step fast allows us to require more memory in the same amount of time.
        // Some applications wouldn't like to waste more than 100 ms on KDF, some are okay to spend 5 sec.
        // Yet, the more memory we can use in that period of time, the better.
        
        // We start with just 2 blocks of data. It's pointless to waste time filling in the whole space.
        // It's also pointless to use any of the remaining space. The only source of entropy we have is in the very beginning.
        // We use the initial state to produce the next block and at the same time we pseudo-randomly mutate that space to force attacker to keep the result around.
        
        // On step two we will have slightly more material, so we'll use that. As we go further in the space,
        // amount of generated data grows, but the amount of computations per step is the same.
        
        // When we arrive at the end, we simply take the last 256 bits as a result.
        
        for (unsigned long i = 2*blockSize; i < numberOfBytes; i += blockSize)
        {
            // A = previous block (filled).
            // B = next block (empty).
            // A is composed of little-endian 64-bit numbers: {A1, A2, A3, A4}.
            // 64-bit chunk C1 will be pointed at by A1 mod (i - 7).
            // 64-bit chunk C2 will be pointed at by (C1 ^ A2) mod (i - 7).
            // 64-bit chunk C3 will be pointed at by (C2 ^ A3) mod (i - 7).
            // Compute hash H = SHA512(C1 ++ C2 ++ C3 ++ A4 ++ key) = {R, H1, H2, H3, H4}, where R - 256-bit block and H1,H2,H3,H4 are 64-bit numbers.
            // Copy H1 to C1, H2 to C2, H3 to C3 and H4 to A1.
            // Copy R into B.
            // Increase i by the block size and repeat.
            // Note that A1 is completely replaced by a hash, so it's hard to quickly find a chain of blocks C1, C2 and C3 that are updated and also affect B.
            // 64-bit hidden pointer is not a big deal, but it increases burden for the attacker significantly without adding much overhead to computing the hash function.
            // Remember that we try to be as fast as possible to cover as much memory as possible in a scarce amount of time.
            
            // Security analysis:
            // Lets say attacker wants to reduce amount of memory by a factor of 2.
            // He will complete 50% of needed computations with the available memory.
            // Then, to continue he will have to overwrite some bytes to continue hashing.
            // Attacker may figure out which bytes will be used in the very next step, so he may avoid overwriting them, but
            // he cannot know yet which ones will be used on the step after the next one.
            // So he will have a chance that one, two or three 64-bit blocks needed are overwritten.
            // That chance grows as more and more bytes are being overwritten.
            // We do not count cost of tracking overwritten blocks; assuming it's zero (although in practice it is not).
            // The cost of a missing 64-bit block is in the need to replay hashing from that position which involves two problems:
            //
            
            uint64_t a1 = *((uint64_t*)(spaceBytes + i - 32));
            uint64_t a2 = *((uint64_t*)(spaceBytes + i - 24));
            uint64_t a3 = *((uint64_t*)(spaceBytes + i - 16));
            uint64_t a4 = *((uint64_t*)(spaceBytes + i - 8));
            
            uint64_t* pc1 = (uint64_t*)(spaceBytes + (a1 % (i - 7)));
            uint64_t* pc2 = (uint64_t*)(spaceBytes + (((*pc1) ^ a2) % (i - 7)));
            uint64_t* pc3 = (uint64_t*)(spaceBytes + (((*pc2) ^ a3) % (i - 7)));
            
            CC_SHA512_Init(&ctx);
            CC_SHA512_Update(&ctx, pc1, 8);
            CC_SHA512_Update(&ctx, pc2, 8);
            CC_SHA512_Update(&ctx, pc3, 8);
            CC_SHA512_Update(&ctx, &a1, 8);
            CC_SHA512_Update(&ctx, &a2, 8);
            CC_SHA512_Update(&ctx, &a3, 8);
            CC_SHA512_Update(&ctx, &a4, 8);
            CC_SHA512_Update(&ctx, keyBytes, blockSize);
            CC_SHA512_Final(spaceBytes + i, &ctx); // put the results in the space so we don't need any extra memory for it. We'll take H1,H2,H3,H4 from spaceBytes[i + 32].
            
            // H1 -> C1
            *pc1 = *((uint64_t*)(spaceBytes + i + 32 + 0 ));
            
            // H2 -> C2
            *pc2 = *((uint64_t*)(spaceBytes + i + 32 + 8 ));
            
            // H3 -> C3
            *pc3 = *((uint64_t*)(spaceBytes + i + 32 + 16));
            
            // H4 -> A1
            *((uint64_t*)(spaceBytes + i - 32)) = *((uint64_t*)(spaceBytes + i + 32 + 24));
        }
        
        // The resulting key is simply the remaining bits of the data space.
        
        NSMutableData* result =  [NSMutableData dataWithBytes:spaceBytes + numberOfBytes - blockSize length:blockSize];
        
        BTCSecureMemset(&ctx,       0, sizeof(ctx));
        BTCSecureMemset(spaceBytes, 0, space.length);
        
        return result;
    }
}

@end
