//
//  MLXMPPServer.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPServer.h"


@interface MLXMPPServer ()

@property (nonatomic, strong) NSString *host;
@property (nonatomic, strong) NSNumber *port;

@property (nonatomic, strong) NSString *serverInUse;

@end

@implementation MLXMPPServer

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port{
    self = [super init];
    self.host=host;
    self.port=port;
    
    return self;
}

- (void) updateConnectedServer:(NSString *) server
{
    self.serverInUse = server;
}

- (NSString *) connectedServer {
    return self.serverInUse;
}

@end
