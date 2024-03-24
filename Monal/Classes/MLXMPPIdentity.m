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
    NSDictionary* parts = [HelperTools splitJid:jid];
    
    //we don't allow this because several parts in monal rely on stable bare jids not changing after login/bind
    MLAssert([self.jid isEqualToString:parts[@"user"]], @"trying to bind to different bare jid!", (@{
        @"bind_to_jid": jid,
        @"current_bare_jid": self.jid
    }));
    
    //don't set new full jid if we don't have a resource
    if(parts[@"resource"] != nil)
    {
        //these won't change because of the MLAssert above, but we keep this
        //to make sure user and domain match the jid once the assertion gets removed
        self.jid = parts[@"user"];
        self.user = parts[@"node"];
        self.domain = parts[@"host"];
        
        self.resource = parts[@"resource"];
        _fullJid = [NSString stringWithFormat:@"%@/%@", self.jid, self.resource];
    }
}

@end
