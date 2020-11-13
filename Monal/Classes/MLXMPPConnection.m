//
//  MLXMPPConnection.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPConnection.h"

@interface MLXMPPConnection ()

@property (nonatomic) MLXMPPServer* server;
@property (nonatomic) MLXMPPIdentity* identity;

@end

@implementation MLXMPPConnection

-(id) initWithServer:(MLXMPPServer*) server andIdentity:(MLXMPPIdentity*) identity
{
    self = [super init];
    self.server = server;
    self.identity = identity;
    return self;
}

@end
