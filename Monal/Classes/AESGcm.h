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
+ (MLEncryptedPayload *) encrypt:(NSData *)body;
+ (NSData *) decrypt:(NSData *)body withKey:(NSData *) key andIv:(NSData *)iv withAuth:(NSData * _Nullable )  auth;
+ (NSData *) attachmentDataFromEncryptedLink:(NSString *) link;
@end

NS_ASSUME_NONNULL_END
