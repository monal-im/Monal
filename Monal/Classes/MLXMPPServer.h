//
//  MLXMPPServer.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Class to contain specifics of an XMPP server
 */
@interface MLXMPPServer : NSObject

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) NSNumber *port;

/**
 the only property that is not read only. set after DNS query.
 */
@property (nonatomic) NSString *dnsDiscoveredHost;

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port;

/**
 returns the currently connected server may be host or dns one.
 */
- (NSString *) connectedServer;

@end

NS_ASSUME_NONNULL_END
