//
//  AESGcm.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "AESGcm.h"
#import "EncodingTools.h"
#import "DDLog.h"

#include <openssl/evp.h>
#include <openssl/rand.h>

static const int ddLogLevel = LOG_LEVEL_ERROR;

@implementation AESGcm

+ (MLEncryptedPayload *) encrypt:(NSData *)body {
    EVP_CIPHER_CTX *ctx =EVP_CIPHER_CTX_new();
    int outlen;
    unsigned char outbuf[body.length];
    unsigned char tag[16];
    
    //genreate key and iv
    
    unsigned char key[16];
    RAND_bytes(key, sizeof(key));
    
    unsigned char iv[16];
    RAND_bytes(iv, sizeof(iv));
    
    NSData *gcmKey = [[NSData alloc] initWithBytes:key length:16];
    
    NSData *gcmiv= [[NSData alloc] initWithBytes:iv length:16];
    
    NSMutableData *encryptedMessage;
    
    ctx = EVP_CIPHER_CTX_new();
    /* Set cipher type and mode */
    EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
    /* Set IV length if default 96 bits is not approp riate */
    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int) gcmiv.length, NULL);
    /* Initialise key and IV */
    EVP_EncryptInit_ex(ctx, NULL, NULL, gcmKey.bytes, gcmiv.bytes);
    EVP_CIPHER_CTX_set_padding(ctx,1);
    /* Encrypt plaintext */
    EVP_EncryptUpdate(ctx, outbuf, &outlen,body.bytes,(int)body.length);
    
    encryptedMessage = [NSMutableData dataWithBytes:outbuf length:outlen];
    
    /* Finalise: note get no output for GCM */
    EVP_EncryptFinal_ex(ctx, outbuf, &outlen);
    
    
    /* Get tag */
    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
    //[encryptedMessage appendBytes:tag length:16];
    
    NSMutableData *combinedKey  = [NSMutableData dataWithData:gcmKey];
    [combinedKey appendBytes:tag length:16];
    
    
    EVP_CIPHER_CTX_free(ctx);
    MLEncryptedPayload *toreturn = [[MLEncryptedPayload alloc] initWithBody:encryptedMessage key:gcmKey iv:gcmiv];
    
    return  toreturn;
}

+ (NSData *) decrypt:(NSData *)body withKey:(NSData *) key andIv:(NSData *)iv withAuth:(NSData *) auth {
 
    EVP_CIPHER_CTX *ctx =EVP_CIPHER_CTX_new();
    int outlen, rv;
    unsigned char outbuf[body.length];
    
    /* Select cipher */
    EVP_DecryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
    /* Set IV length, omit for 96 bits */
    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)iv.length, NULL);
    /* Specify key and IV */
    EVP_DecryptInit_ex(ctx, NULL, NULL, key.bytes, iv.bytes);
    EVP_CIPHER_CTX_set_padding(ctx,1);
    /* Decrypt plaintext */
    EVP_DecryptUpdate(ctx, outbuf, &outlen, body.bytes, (int)body.length);
    /* Output decrypted block */
    
    if(auth) {
        /* Set expected tag value. */
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int)auth.length, auth.bytes);
    }
    /* Finalise: note get no output for GCM */
    rv = EVP_DecryptFinal_ex(ctx, outbuf, &outlen);
    
    NSData *decdata = [[NSData alloc] initWithBytes:outbuf length:body.length];
   
    EVP_CIPHER_CTX_free(ctx);
    
    return  decdata;
}



@end
