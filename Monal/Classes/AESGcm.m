//
//  AESGcm.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "AESGcm.h"
#import "EncodingTools.h"
#import <MLCrypto/MLCrypto-Swift.h>


@implementation AESGcm

+ (MLEncryptedPayload *) encrypt:(NSData *)body {

  //  MLEncryptedPayload *toreturn = [[MLEncryptedPayload alloc] initWithBody:encryptedMessage key:combinedKey iv:gcmiv];

    return  nil;
}

+ (NSData *) decrypt:(NSData *)body withKey:(NSData *) key andIv:(NSData *)iv withAuth:( NSData * _Nullable )  auth {
    
    MLCrypto *crypto = [[MLCrypto alloc] init];

    NSMutableData *combined = [[NSMutableData alloc] init];
    [combined appendData:iv];
    [combined appendData:body];
    [combined appendData:auth];

    NSData *toReturn =[crypto decryptGCMWithKey:key encryptedContent:combined];
    return toReturn;
    
  
    
}



@end
