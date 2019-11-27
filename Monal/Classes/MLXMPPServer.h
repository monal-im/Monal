//
//  MLXMPPServer.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLXMPPServer : NSObject

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) NSNumber *port;
@property (nonatomic) NSString *dnsDiscoveredHost;

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port;
- (NSString *) connectedServer;

@end

NS_ASSUME_NONNULL_END
