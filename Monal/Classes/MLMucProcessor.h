//
//  MLMucProcessor.h
//  monalxmpp
//
//  Created by Thilo Molitor on 29.12.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@class XMPPPresence;
@class XMPPMessage;
@class xmpp;

@interface MLMucProcessor : NSObject

+(void) setState:(NSDictionary*) state;
+(NSDictionary*) state;

+(void) addUIHandler:(monal_id_block_t) handler forMuc:(NSString*) room;
+(void) removeUIHandlerForMuc:(NSString*) room;

+(void) processPresence:(XMPPPresence*) presenceNode forAccount:(xmpp*) account;
+(BOOL) processMessage:(XMPPMessage*) messageNode forAccount:(xmpp*) account;

+(void) sendDiscoQueryFor:(NSString*) roomJid onAccount:(xmpp*) account withJoin:(BOOL) join;

@end

NS_ASSUME_NONNULL_END
