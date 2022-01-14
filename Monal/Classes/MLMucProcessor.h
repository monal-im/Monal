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

-(void) processPresence:(XMPPPresence*) presenceNode;
-(BOOL) processMessage:(XMPPMessage*) messageNode;

-(void) join:(NSString*) room;
-(void) leave:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks;
-(void) pingAllMucs;
-(void) ping:(NSString*) roomJid;
-(BOOL) checkIfStillBookmarked:(NSString*) room;

@end

NS_ASSUME_NONNULL_END
