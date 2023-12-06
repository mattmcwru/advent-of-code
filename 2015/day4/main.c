#import <stdio.h>
#import <string.h>

#define COMMON_DIGEST_FOR_OPENSSL
#include <CommonCrypto/CommonDigest.h>
#define SHA1 CC_SHA1
//#include <openssl/md5.h>

char* key = "bgvyzdsv";

int main() {
    MD5_CTX mdContext;
    unsigned char mdDigest[MD5_DIGEST_LENGTH];
    char mdSum[MD5_DIGEST_LENGTH*2+1];

    char testkey[20];

    int keynum = 0;

    do {
        snprintf(testkey, sizeof(testkey), "%s%d", key, keynum);

        MD5_Init (&mdContext);
        MD5_Update (&mdContext, testkey, strlen(testkey));
        MD5_Final (mdDigest, &mdContext);

        for (int n = 0; n < MD5_DIGEST_LENGTH; n++) {
            snprintf(&(mdSum[n*2]), 3, "%02x", mdDigest[n]);
        }

        keynum++;
    } while (strncmp(mdSum, "000000", 6) != 0);

    printf("Key: %s, Sum: %s\n", testkey, mdSum);

    return 0;
}
