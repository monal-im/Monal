//
//  AESGcm.h
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLEncryptedPayload.h"

NS_ASSUME_NONNULL_BEGIN

@interface AESGcm : NSObject
/**
 key size should be 16 or 32
 */
+(MLEncryptedPayload* _Nullable) encrypt:(NSData*) body keySize:(int) keySize;
+(MLEncryptedPayload* _Nullable) encrypt:(NSData*) body withKey:(NSData*) gcmKey;
+(NSData* _Nullable) decrypt:(NSData *)body withKey:(NSData *) key andIv:(NSData *)iv withAuth:(NSData * _Nullable) auth;
+(NSData* _Nullable) genIV;
+(NSData* _Nullable) genKey:(int) keySize;

@end

NS_ASSUME_NONNULL_END
