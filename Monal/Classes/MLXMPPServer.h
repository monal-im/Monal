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

@property (nonatomic,assign) BOOL directTLS;

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port andDirectTLS:(BOOL) directTLS;


- (void) updateConnectServer:(NSString *) server;

- (void) updateConnectPort:(NSNumber *) port;

- (void) updateConnectTLS:(BOOL) isSecure;

/**
 returns the currently connected server may be host or dns one.
 */
- (NSString *) connectServer;

/**
returns the currently connected port may be configured  or dns one.
*/
- (NSNumber *) connectPort;

/**
 Will indicate whether direct TLS us used. This is either the old style or updated via DNS discovery
*/
- (BOOL) isDirectTLS;

@end

NS_ASSUME_NONNULL_END
