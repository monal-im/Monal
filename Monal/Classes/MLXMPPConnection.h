//
//  MLXMPPConnection.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLXMPPServer.h"
#import "MLXMPPIdentity.h"

NS_ASSUME_NONNULL_BEGIN

/**
 A class to hold the the  identity, host, state and discovered properties of an xmpp connection
 */
@interface MLXMPPConnection : NSObject

@property (nonatomic, readonly) MLXMPPServer* server;
@property (nonatomic, readonly) MLXMPPIdentity* identity;

//State

/**
 The properties below are discovered after connecting and therefore are not read only
 */

//server details
@property (nonatomic, strong) NSSet* _Nullable serverFeatures;

@property (nonatomic, strong)  NSMutableArray* _Nullable discoveredServices;
@property (nonatomic, strong)  NSString* _Nullable uploadServer;

@property (nonatomic, strong)  NSString* _Nullable conferenceServer;

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
@property (nonatomic, assign) BOOL supportsRosterPreApproval;

@property (nonatomic, assign) BOOL supportsBlocking;
@property (nonatomic, assign) BOOL supportsPing;
@property (nonatomic, assign) BOOL supportsPubSub;


-(id) initWithServer:(MLXMPPServer*) server andIdentity:(MLXMPPIdentity*) identity;

@end

NS_ASSUME_NONNULL_END
