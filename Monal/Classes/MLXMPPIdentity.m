//
//  MLXMPPIdentity.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPIdentity.h"
#import "HelperTools.h"

@interface MLXMPPIdentity ()

@property (atomic) NSString* user;
@property (atomic) NSString* password;
@property (atomic) NSString* domain;

@end

@implementation MLXMPPIdentity

-(id) initWithJid:(NSString*) jid password:(NSString*) password andResource:(NSString*) resource
{
    self = [super init];
    NSDictionary* parts = [HelperTools splitJid:jid];
    self.jid = parts[@"user"];
    self.resource = resource;
    _fullJid = resource ? [NSString stringWithFormat:@"%@/%@", self.jid, self.resource] : jid;
    self.password = password;
    self.user = parts[@"node"];
    self.domain = parts[@"host"];
    return self;
}

-(void) updatPassword:(NSString*) newPassword
{
    self.password = newPassword;
}

-(void) bindJid:(NSString*) jid
{
    _fullJid = jid;
    NSDictionary* parts = [HelperTools splitJid:jid];
    self.jid = parts[@"user"];
    self.resource = parts[@"resource"];
    self.user = parts[@"node"];
    self.domain = parts[@"host"];
}

@end
