//
//  AESGcm.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLConstants.h"
#import "AESGcm.h"
#import <monalxmpp/monalxmpp-Swift.h>

#if !TARGET_OS_MACCATALYST
#include <openssl/evp.h>
#include <openssl/rand.h>
#define AES_BLOCK_SIZE 16
#define AUTH_TAG_LENGTH 16
#endif

@class MLCrypto;

@implementation AESGcm

+(MLEncryptedPayload*) encrypt:(NSData*) body keySize:(int) keySize
{
    NSData* gcmKey = [self genKey:keySize];
    if(!gcmKey)
    {
        return nil;
    }
    return [self encrypt:body withKey:gcmKey];
}

+(MLEncryptedPayload*) encrypt:(NSData*) body withKey:(NSData*) gcmKey
{
    if(@available(iOS 13.0, *))
    {
        MLCrypto* crypto = [[MLCrypto alloc] init];
        EncryptedPayload* payload = [crypto encryptGCMWithKey:gcmKey decryptedContent:body];
        if(payload == nil)
        {
            return nil;
        }
        NSMutableData* combinedKey = [NSMutableData dataWithData:gcmKey];
        [combinedKey appendData:payload.tag];
        if(combinedKey == nil)
        {
            return nil;
        }
        return [[MLEncryptedPayload alloc] initWithBody:payload.body key:combinedKey iv:payload.iv authTag:payload.tag];
    }
    else
    {
#if !TARGET_OS_MACCATALYST
        EVP_CIPHER_CTX* ctx;
        int outlen, tmplen;
        unsigned char* outbuf = malloc(body.length + AES_BLOCK_SIZE);
        unsigned char tag[AUTH_TAG_LENGTH];
        NSMutableData* combinedKey;
        NSData* encryptedMessage;
        
        NSData* gcmiv = [self genIV];
        if(gcmiv == nil)
            goto end1;
        
        ctx = EVP_CIPHER_CTX_new();
        if(ctx == NULL)
            goto end1;
        
        /* Set cipher type and mode */
        if([gcmKey length] == 16) {
            EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
            OPENSSL_assert(EVP_CIPHER_CTX_key_length(ctx) == 16);
        }
        else if([gcmKey length] == 32)
        {
            EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL);
            OPENSSL_assert(EVP_CIPHER_CTX_key_length(ctx) == 32);
        }
        else
            goto end2;
        
        /* Set IV length if default 96 bits is not approp riate */
        if(EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)gcmiv.length, NULL) != 1)
            goto end2;
        OPENSSL_assert(EVP_CIPHER_CTX_iv_length(ctx) == (int)gcmiv.length);
        
        /* Initialise key and IV */
        if(EVP_EncryptInit_ex(ctx, NULL, NULL, gcmKey.bytes, gcmiv.bytes) != 1)
            goto end2;
        
        // enable padding, always returns 1
        assert(EVP_CIPHER_CTX_set_padding(ctx, 1) == 1);
        
        /* Encrypt plaintext */
        if(EVP_EncryptUpdate(ctx, outbuf, &outlen, body.bytes, (int)body.length) == 0)
            goto end2;
        tmplen = outlen;
        
        /* Finalise: note get no output for GCM */
        if(EVP_EncryptFinal_ex(ctx, outbuf + outlen, &tmplen) == 0)
            goto end2;
        outlen += tmplen;
        encryptedMessage = [NSData dataWithBytesNoCopy:outbuf length:outlen];
        
        /* Get tag */
        if(EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, AUTH_TAG_LENGTH, tag) != 1)
        {
            EVP_CIPHER_CTX_free(ctx);
            return nil;
        }
        
        combinedKey = [NSMutableData dataWithData:gcmKey];
        [combinedKey appendBytes:tag length:AUTH_TAG_LENGTH];
        
        EVP_CIPHER_CTX_free(ctx);
        return [[MLEncryptedPayload alloc] initWithBody:encryptedMessage key:combinedKey iv:gcmiv authTag:[NSData dataWithBytes:tag length:AUTH_TAG_LENGTH]];
        
        end2:
            EVP_CIPHER_CTX_free(ctx);
        end1:
            free(outbuf);
            return nil;
#else
        assert(false);
        return nil;
#endif
    }
}

+(NSData*) genIV
{
    if(@available(iOS 13.0, *)) {
        MLCrypto* crypto = [[MLCrypto alloc] init];
        return [crypto genIV];
    } else {
#if !TARGET_OS_MACCATALYST
        //generate iv
        unsigned char iv[12];
        if(RAND_bytes(iv, sizeof(iv)) == 0)
        {
            return nil;
        }
        NSData* gcmiv = [[NSData alloc] initWithBytes:iv length:12];
        return gcmiv;
#else
        assert(false);
        return nil;
#endif
    }
}

+(NSData*) genKey:(int) keySize
{
    uint8_t randomBytes[keySize];
    if(SecRandomCopyBytes(kSecRandomDefault, keySize, randomBytes) != 0)
        return nil;
    return [[NSData alloc] initWithBytes:randomBytes length:keySize];
}

+(NSData*) decrypt:(NSData*) body withKey:(NSData*) key andIv:(NSData*) iv withAuth:(NSData* _Nullable) auth
{
    if (@available(iOS 13.0, *)) {
        MLCrypto* crypto = [[MLCrypto alloc] init];
        
        NSMutableData* combined = [[NSMutableData alloc] init];
        [combined appendData:iv];
        [combined appendData:body];
        [combined appendData:auth]; //if auth is nil assume it already was apended to body
        
        NSData* toReturn = [crypto decryptGCMWithKey:key encryptedContent:combined];
        return toReturn;
    }
    else
    {
#if !TARGET_OS_MACCATALYST
        assert(iv.length == 12);

        NSData* realBody = body;
        if(auth == nil)
        {
            realBody = [NSData dataWithBytesNoCopy:(void* _Nonnull)body.bytes length:body.length - AUTH_TAG_LENGTH freeWhenDone:NO];
            auth = [NSData dataWithBytesNoCopy:(void* _Nonnull)body.bytes + (body.length - AUTH_TAG_LENGTH) length:AUTH_TAG_LENGTH freeWhenDone:NO];
        }
        
        int outlen, tmplen, retval;
        unsigned char* outbuf = malloc(realBody.length + AES_BLOCK_SIZE);
        EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
        
        /* Select cipher */
        if(key.length == 16) {
            EVP_DecryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
            OPENSSL_assert(EVP_CIPHER_CTX_key_length(ctx) == 16);
        }
        else if(key.length == 32)
        {
            EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL);
            OPENSSL_assert(EVP_CIPHER_CTX_key_length(ctx) == 32);
        }
        else
        {
            free(outbuf);
            EVP_CIPHER_CTX_free(ctx);
            return nil;
        }
        
        /* Set IV length, omit for 96 bits */
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)iv.length, NULL);
        OPENSSL_assert(EVP_CIPHER_CTX_iv_length(ctx) == (int)iv.length);
        
        /* Specify key and IV */
        EVP_DecryptInit_ex(ctx, NULL, NULL, key.bytes, iv.bytes);
        
        // enable padding, always returns 1
        assert(EVP_CIPHER_CTX_set_padding(ctx, 1) == 1);
        
        /* Set expected tag value. */
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int)auth.length, (void*)auth.bytes);
        
        /* Decrypt ciphertext */
        if((retval = EVP_DecryptUpdate(ctx, outbuf, &tmplen, realBody.bytes, (int)realBody.length)) == 0)
        {
            DDLogError(@"EVP_DecryptUpdate() --> %ld", (long)retval);
            free(outbuf);
            EVP_CIPHER_CTX_free(ctx);
            return nil;
        }
        outlen = tmplen;
        
        /* Finalise: note get no output for GCM */
        if((retval = EVP_DecryptFinal_ex(ctx, outbuf + tmplen, &tmplen)) <= 0)
        {
            DDLogError(@"EVP_DecryptFinal_ex() --> %ld", (long)retval);
            free(outbuf);
            EVP_CIPHER_CTX_free(ctx);
            return nil;
        }
        EVP_CIPHER_CTX_free(ctx);
        
        return [NSData dataWithBytesNoCopy:outbuf length:outlen];
#else
        assert(false);
        return nil;
#endif
    }
}

@end
