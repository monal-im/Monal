//
//  AESGcm.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <monalxmpp/MLConstants.h>
#import "AESGcm.h"
#import <monalxmpp/monalxmpp-Swift.h>

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
    MLCrypto* crypto = [MLCrypto new];
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

+(NSData*) genIV
{
    MLCrypto* crypto = [MLCrypto new];
    return [crypto genIV];
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
    MLCrypto* crypto = [MLCrypto new];
    
    NSMutableData* combined = [NSMutableData new];
    [combined appendData:iv];
    [combined appendData:body];
    [combined appendData:auth]; //if auth is nil assume it already was apended to body
    
    NSData* toReturn = [crypto decryptGCMWithKey:key encryptedContent:combined];
    return toReturn;
}

@end
