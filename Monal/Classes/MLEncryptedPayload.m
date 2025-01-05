//
//  MLEncryptedPayload.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLEncryptedPayload.h"
#import <monalxmpp/HelperTools.h>

@interface MLEncryptedPayload ()
@property (nonatomic, strong) NSData* body;
@property (nonatomic, strong) NSData* key;
@property (nonatomic, strong) NSData* iv;
@property (nonatomic, strong) NSData* authTag;
@end

@implementation MLEncryptedPayload

-(MLEncryptedPayload *) initWithBody:(NSData *) body key:(NSData *) key iv:(NSData *) iv authTag:(NSData *) authTag
{
    MLAssert(body != nil, @"body must not be nil");
    MLAssert(key != nil, @"key must not be nil");
    MLAssert(iv != nil, @"iv must not be nil");
    MLAssert(authTag != nil, @"authTag must not be nil");

    self = [super init];
    self.body = body;
    self.key = key;
    self.iv = iv;
    self.authTag = authTag;
    return self;
}

-(MLEncryptedPayload *) initWithKey:(NSData *) key iv:(NSData *) iv
{
    MLAssert(key != nil, @"key must not be nil");
    MLAssert(iv != nil, @"iv must not be nil");

    self = [super init];
    self.body = nil;
    self.key = key;
    self.iv = iv;
    self.authTag = nil;
    return self;
}

@end
