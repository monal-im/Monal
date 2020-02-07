//
//  AESGCMTest.m
//  Monal Tests
//
//  Created by Anurodh Pokharel on 1/7/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "AESGcm.h"

@interface AESGCMTest : XCTestCase

@end

@implementation AESGCMTest

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

-(void) testEncrypt {
    NSString *decrypted = @"Hi";
    NSData *data = [decrypted dataUsingEncoding:NSUTF8StringEncoding];
    MLEncryptedPayload *payload = [AESGcm encrypt:data keySize:16];
    
    NSData *key=[payload.key subdataWithRange:NSMakeRange(0,16)];
    NSData *auth=[payload.key subdataWithRange:NSMakeRange(16,16)];
    
    NSData *decryptedResult = [AESGcm decrypt:payload.body withKey:key andIv:payload.iv withAuth:auth];
    
}

-(void) testDecrypt {
    
}

@end
