//
//  XMPPStanza.h
//  monalxmpp
//
//  Created by tmolitor on 24.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLXMLNode.h"

NS_ASSUME_NONNULL_BEGIN

@interface XMPPStanza : MLXMLNode

-(void) addDelayTagFrom:(NSString*) from;

@property (atomic, strong) NSString* from;
@property (atomic, strong) NSString* fromUser;
@property (atomic, strong) NSString* fromNode;
@property (atomic, strong) NSString* fromHost;
@property (atomic, strong) NSString* fromResource;

@property (atomic, strong) NSString* to;
@property (atomic, strong) NSString* toUser;
@property (atomic, strong) NSString* toNode;
@property (atomic, strong) NSString* toHost;
@property (atomic, strong) NSString* toResource;

@end

NS_ASSUME_NONNULL_END
