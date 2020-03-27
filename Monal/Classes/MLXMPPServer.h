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

@property (nonatomic,assign) BOOL SSL;
@property (nonatomic,assign) BOOL oldStyleSSL;
@property (nonatomic,assign) BOOL selfSignedCert;

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port andOldStyleSSL:(BOOL) oldStyleSSL;


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
returns the currently directTLS setting may be configured  or dns one.
*/
- (BOOL) connectTLS;

@end

NS_ASSUME_NONNULL_END
