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

-(void) encryptWithSize:(int) size
{
    NSString* plaintext = @"ABCDEFGHIKLMOPQRSTUVWXYZ1234567890!\"§$%&/()=?*+#-.,;:_";
    NSData* plaintextUTF8 = [plaintext dataUsingEncoding:NSUTF8StringEncoding];
    MLEncryptedPayload* payload = [AESGcm encrypt:plaintextUTF8 keySize:size];

    NSData* key = [payload.key subdataWithRange:NSMakeRange(0, size)];
    NSData* auth = [payload.key subdataWithRange:NSMakeRange(size, 16)];

    NSData* decryptedResult = [AESGcm decrypt:payload.body withKey:key andIv:payload.iv withAuth:auth];
    NSString* decryptedResultString = [[NSString alloc] initWithData:decryptedResult encoding:NSUTF8StringEncoding];
    XCTAssert([decryptedResultString isEqualToString:plaintext]);
}

-(void) testEncrypt16
{
    [self encryptWithSize:16];
}

-(void) testEncrypt32
{
    [self encryptWithSize:32];
}

/*
 * This test doesn't check for real IV uniqueness!
 */
-(void) testGenIV
{
    const UInt32 ivCnt = 40000;
    NSMutableArray<NSData*>* ivArray = [[NSMutableArray<NSData*> alloc] init];

    for(UInt32 i = 0; i < ivCnt; i++)
    {
        NSData* iv = [AESGcm genIV];
        XCTAssertFalse([ivArray containsObject:iv], "IV should be unique");
        [ivArray addObject:iv];
    }
}


/*
 * This test doesn't check for real key uniqueness!
 */
-(void) genKeyWithSize:(uint) size
{
    const UInt32 ivCnt = 40000;
    NSMutableArray<NSData*>* ivArray = [[NSMutableArray<NSData*> alloc] init];

    for(UInt32 i = 0; i < ivCnt; i++)
    {
        NSData* iv = [AESGcm genKey:size];
        XCTAssertFalse([ivArray containsObject:iv], "key should be unique");
        [ivArray addObject:iv];
    }
}

/*
 * This test doesn't check for real key uniqueness!
 */
-(void) testGenKey16
{
    [self genKeyWithSize:16];
}

/*
 * This test doesn't check for real key uniqueness!
 */
-(void) testGenKey32
{
    [self genKeyWithSize:32];
}

@end
