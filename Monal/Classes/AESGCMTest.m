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

-(void) testEncrypt16 {
    NSString *decrypted = @"Hi";
    NSData *data = [decrypted dataUsingEncoding:NSUTF8StringEncoding];
    MLEncryptedPayload *payload = [AESGcm encrypt:data keySize:16];
    
    NSData *key=[payload.key subdataWithRange:NSMakeRange(0,16)];
    NSData *auth=[payload.key subdataWithRange:NSMakeRange(16,16)];
    
    NSData *decryptedResult = [AESGcm decrypt:payload.body withKey:key andIv:payload.iv withAuth:auth];
    NSString *decryptedResultString = [[NSString alloc] initWithData:decryptedResult encoding:NSUTF8StringEncoding];
    XCTAssert([decryptedResultString isEqualToString:decrypted]);
    
}

-(void) testEncrypt32 {
    NSString *decrypted = @"Hi";
    NSData *data = [decrypted dataUsingEncoding:NSUTF8StringEncoding];
    MLEncryptedPayload *payload = [AESGcm encrypt:data keySize:32];
    
    NSData *key=[payload.key subdataWithRange:NSMakeRange(0,32)];
    NSData *auth=[payload.key subdataWithRange:NSMakeRange(32,16)];
    
    NSMutableData *mData = [[NSMutableData alloc] init];
    [mData appendData:payload.body];
    [mData appendData:auth];
    
    NSData *decryptedResult = [AESGcm decrypt:mData  withKey:key andIv:payload.iv withAuth:nil];
    NSString *decryptedResultString = [[NSString alloc] initWithData:decryptedResult encoding:NSUTF8StringEncoding];
    XCTAssert([decryptedResultString isEqualToString:decrypted]);
    
}

-(void) testDecrypt {
    
}

@end
