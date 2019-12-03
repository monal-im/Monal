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

@property (nonatomic) NSString *user;
@property (nonatomic) NSString *domain;

@end

@implementation MLXMPPIdentity

-(id) initWithJid:(NSString *)jid andPassword:(NSString *) password
{
    self=[super init];
    self.jid=jid;
    self.password=password;
    
    NSArray* elements=[self.jid componentsSeparatedByString:@"@"];
    
    self.user=elements[0];
    
    if(elements.count>1) {
        self.domain = elements[1];
    }
    
    return self;
}


@end
