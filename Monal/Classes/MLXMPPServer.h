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
@property (nonatomic,assign) BOOL selfSigned;

//used only for gmail login
@property (nonatomic,assign) BOOL oAuth;


// below are properties of the server that are discovered

//server details
@property (nonatomic, strong) NSSet *serverFeatures;


@property (nonatomic,strong)  NSMutableArray*  discoveredServices;
@property (nonatomic,strong)  NSString*  uploadServer;

@property (nonatomic, assign) BOOL supportsHTTPUpload;
// client state
@property (nonatomic, assign) BOOL supportsClientState;
//message archive
@property (nonatomic, assign) BOOL supportsMam2;
@property (nonatomic, assign) BOOL supportsSM3;
@property (nonatomic, assign) BOOL supportsPush;
@property (nonatomic, assign) BOOL pushEnabled;
@property (nonatomic, assign) BOOL usingCarbons2;
@property (nonatomic, assign) BOOL supportsRosterVersion;

@property (nonatomic, assign) BOOL supportsPing;
@property (nonatomic, assign) BOOL supportsPubSub;


@property (nonatomic) NSString *dnsDiscoveredHost;

-(id) initWithHost:(NSString *) host andPort:(NSNumber *) port;

/**
 returns the currently connected server may be host or dns one.
 */
- (NSString *) connectedServer;

@end

NS_ASSUME_NONNULL_END
