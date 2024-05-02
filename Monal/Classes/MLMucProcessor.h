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
-(void) leave:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks keepBuddylistEntry:(BOOL) keepBuddylistEntry;

//muc management methods
-(NSString* _Nullable) generateMucJid;
-(NSString* _Nullable) createGroup:(NSString*) room;
-(void) destroyRoom:(NSString*) room;
-(void) changeNameOfMuc:(NSString*) room to:(NSString*) name;
-(void) changeSubjectOfMuc:(NSString*) room to:(NSString*) subject;
-(void) publishAvatar:(UIImage* _Nullable) image forMuc:(NSString*) room;
-(void) setAffiliation:(NSString*) affiliation ofUser:(NSString*) jid inMuc:(NSString*) roomJid;
-(void) inviteUser:(NSString*) jid inMuc:(NSString*) roomJid;

-(void) pingAllMucs;
-(void) ping:(NSString*) roomJid;
-(BOOL) checkIfStillBookmarked:(NSString*) room;
-(NSSet*) getRoomFeaturesForMuc:(NSString*) room;

@end

NS_ASSUME_NONNULL_END
