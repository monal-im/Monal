//
//  MLContact.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString* const kSubBoth;
FOUNDATION_EXPORT NSString* const kSubNone;
FOUNDATION_EXPORT NSString* const kSubTo;
FOUNDATION_EXPORT NSString* const kSubFrom;
FOUNDATION_EXPORT NSString* const kSubRemove;

FOUNDATION_EXPORT NSString* const kAskSubscribe;

@class xmpp;
@class MLMessage;
@class UIImage;

@interface MLContact : NSObject <NSSecureCoding>

+(MLContact*) makeDummyContact:(int) type;

+(BOOL) supportsSecureCoding;

+(NSString*) ownDisplayNameForAccount:(xmpp*) account;

-(BOOL) isSubscribed;
-(BOOL) isInRoster;

-(BOOL) isEqualToContact:(MLContact*) contact;
-(BOOL) isEqualToMessage:(MLMessage*) message;
-(BOOL) isEqual:(id _Nullable) object;

+(MLContact*) createContactFromJid:(NSString*) jid andAccountNo:(NSString*) accountNo;

/**
 account number in the database should be an integer
 */
@property (nonatomic, copy) NSString* accountId;
@property (nonatomic, copy) NSString* contactJid;
@property (nonatomic, copy) UIImage* avatar;
@property (nonatomic, copy) NSString* fullName;
/**
 usually user assigned nick name
 */
@property (nonatomic, copy) NSString* nickName;
@property (nonatomic, strong) NSString* nickNameView;

/**
 xmpp state text
 */
@property (nonatomic, copy) NSString* state;

/**
 xmpp status message
 */
@property (nonatomic, copy) NSString* statusMessage;
@property (nonatomic, copy) NSDate* lastInteractionTime;

/**
 used to display the badge on a row
 */
@property (nonatomic, readonly) NSInteger unreadCount;

@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isMuted;
@property (nonatomic, assign) BOOL isActiveChat;
@property (nonatomic, assign) BOOL isEncrypted;

@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy) NSString* groupSubject;
@property (nonatomic, copy) NSString* mucType;
@property (nonatomic, copy) NSString* accountNickInGroup;
@property (nonatomic, assign) BOOL isMentionOnly;

@property (nonatomic, copy) NSString* subscription; //roster subbscription state
@property (nonatomic, copy) NSString* ask; //whether we have tried to subscribe

@property (nonatomic, readonly) NSString* contactDisplayName;

-(void) updateWithContact:(MLContact*) contact;
-(void) refresh;
-(void) updateUnreadCount;

@property (strong, readonly) NSString* description;


// *** mutating methods (for swiftui etc.) below ***

-(void) toggleMute:(BOOL) mute;
-(void) toggleMentionOnly:(BOOL) mentionOnly;
-(BOOL) toggleEncryption:(BOOL) encrypt;
-(void) togglePinnedChat:(BOOL) pinned;
-(BOOL) toggleBlocked:(BOOL) block;
-(void) removeFromRoster;
-(void) addToRoster;
-(void) clearHistory;

@end

NS_ASSUME_NONNULL_END
