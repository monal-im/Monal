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

@class MLContactSoftwareVersionInfo;
@class MLXMLNode;

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
@property (nonatomic, strong) MLXMLNode* serverFeatures;
@property (nonatomic, strong) NSSet* accountDiscoFeatures;
@property (nonatomic, strong) NSSet* serverDiscoFeatures;

@property (nonatomic, strong) NSMutableArray* discoveredServices;
@property (nonatomic, strong) NSMutableArray* discoveredStunTurnServers;
@property (nonatomic, strong) NSMutableDictionary* discoveredAdhocCommands;
@property (nonatomic, strong) MLContactSoftwareVersionInfo* _Nullable serverVersion;

@property (nonatomic, strong) NSMutableDictionary* conferenceServers;

@property (nonatomic, assign) BOOL supportsHTTPUpload;
@property (nonatomic, strong) NSString* _Nullable uploadServer;
@property (nonatomic, assign) NSInteger uploadSize;

@property (nonatomic, assign) BOOL supportsSM3;
@property (nonatomic, assign) BOOL pushEnabled;
@property (nonatomic, assign) BOOL supportsBookmarksCompat;
@property (nonatomic, assign) BOOL usingCarbons2;
@property (nonatomic, strong) NSString* serverIdentity;

@property (nonatomic, assign) BOOL supportsPubSub;
@property (nonatomic, assign) BOOL supportsPubSubMax;
@property (nonatomic, assign) BOOL supportsModernPubSub;

@property (nonatomic, assign) BOOL accountDiscoDone;

@property (nonatomic, strong) NSDictionary* saslMethods;
@property (nonatomic, strong) NSDictionary* channelBindingTypes;
@property (nonatomic, assign) BOOL supportsSSDP;
@property (nonatomic, strong) NSString* tlsVersion;

-(id) initWithServer:(MLXMPPServer*) server andIdentity:(MLXMPPIdentity*) identity;

@end

NS_ASSUME_NONNULL_END
