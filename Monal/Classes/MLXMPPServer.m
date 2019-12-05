//
//  MLXMPPServer.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPServer.h"


@interface MLXMPPServer ()

/**
 These are the values that are set by config
 */
@property (nonatomic, strong) NSString *host;
@property (nonatomic, strong) NSNumber *port;

/**
 These may be values that are set by DNS discovery. It may not match
 */
@property (nonatomic, strong) NSString *serverInUse;
@property (nonatomic, strong) NSNumber *portInUse;

@end

@implementation MLXMPPServer

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port{
    self = [super init];
    self.host=host;
    self.port=port;
    
    self.serverInUse=host;
    self.portInUse=port;
    
    return self;
}

- (void) updateConnectServer:(NSString *) server
{
    self.serverInUse = server;
}

- (NSString *) connectServer {
    return self.serverInUse;
}

- (void) updateConnectPort:(NSNumber *) port
{
    self.portInUse = port;
}

- (NSNumber *) connectPort {
    return self.portInUse;
}

@end
