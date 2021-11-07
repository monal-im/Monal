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

-(void) addUIHandler:(monal_id_block_t) handler forMuc:(NSString*) room;
-(void) removeUIHandlerForMuc:(NSString*) room;

-(void) processPresence:(XMPPPresence*) presenceNode forAccount:(xmpp*) account;
-(BOOL) processMessage:(XMPPMessage*) messageNode forAccount:(xmpp*) account;

-(void) join:(NSString*) room onAccount:(xmpp*) account;
-(void) leave:(NSString*) room onAccount:(xmpp*) account withBookmarksUpdate:(BOOL) updateBookmarks;
-(void) pingAllMucsOnAccount:(xmpp*) account;
-(void) ping:(NSString*) roomJid onAccount:(xmpp*) account;

@end

NS_ASSUME_NONNULL_END
