//
//  MLXMPPIdentity.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPIdentity.h"

 
@interface MLXMPPIdentity ()

@property (nonatomic) NSString *jid;
@property (nonatomic) NSString *password;

@end

@implementation MLXMPPIdentity

-(id) initWithJid:(NSString *)jid andPassword:(NSString *) password
{
    self=[super init];
    self.jid=jid;
    self.password=password;
    return self;
}

-(NSString *) user {
    return nil;
}

-(NSString *) domain {
    return nil;
}
@end
