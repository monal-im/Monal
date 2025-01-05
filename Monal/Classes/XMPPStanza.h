//
//  XMPPStanza.h
//  monalxmpp
//
//  Created by Thilo Molitor on 24.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLXMLNode.h>

NS_ASSUME_NONNULL_BEGIN

@interface XMPPStanza : MLXMLNode

-(void) addDelayTagFrom:(NSString*) from;

@property (atomic, strong) NSString* _Nullable id;

@property (atomic, strong) NSString* _Nullable from;
@property (atomic, strong) NSString* _Nullable fromUser;
@property (atomic, strong) NSString* _Nullable fromNode;
@property (atomic, strong) NSString* _Nullable fromHost;
@property (atomic, strong) NSString* _Nullable fromResource;

@property (atomic, strong) NSString* _Nullable to;
@property (atomic, strong) NSString* _Nullable toUser;
@property (atomic, strong) NSString* _Nullable toNode;
@property (atomic, strong) NSString* _Nullable toHost;
@property (atomic, strong) NSString* _Nullable toResource;

@end

NS_ASSUME_NONNULL_END
