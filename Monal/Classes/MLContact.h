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

@property (readonly) NSString* id;     //for Identifiable protocol

@property (nonatomic, readonly) BOOL isSelfChat;
@property (nonatomic, readonly) BOOL isInRoster;
@property (nonatomic, readonly) BOOL isSubscribedTo;
@property (nonatomic, readonly) BOOL isSubscribedFrom;
@property (nonatomic, readonly) BOOL isSubscribedBoth;
@property (nonatomic, readonly) BOOL hasIncomingContactRequest;
@property (nonatomic, readonly) BOOL hasOutgoingContactRequest;

-(BOOL) isEqualToContact:(MLContact*) contact;
-(BOOL) isEqualToMessage:(MLMessage*) message;
-(BOOL) isEqual:(id _Nullable) object;

+(MLContact*) createContactFromJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo;

/**
 account number in the database should be an integer
 */
@property (nonatomic, readonly) NSNumber* accountId;
@property (nonatomic, readonly) NSString* contactJid;
@property (nonatomic, readonly, copy) UIImage* avatar;
@property (nonatomic, readonly) BOOL hasAvatar;
@property (nonatomic, readonly) NSString* fullName;
@property (nonatomic, readonly) xmpp* _Nullable account;
/**
 usually user assigned nick name
 */
@property (nonatomic, readonly) NSString* nickName;
@property (nonatomic, strong) NSString* nickNameView;
@property (nonatomic, strong) NSString* fullNameView;

/**
 xmpp state text
 */
@property (nonatomic, copy) NSString* state;

/**
 xmpp status message
 */
@property (nonatomic, copy) NSString* statusMessage;
@property (nonatomic, readonly) NSDate* _Nullable lastInteractionTime;

/**
 used to display the badge on a row
 */
@property (nonatomic, readonly) NSInteger unreadCount;

@property (nonatomic, readonly) BOOL isPinned;
@property (nonatomic, readonly) BOOL isBlocked;
@property (nonatomic, readonly) BOOL isMuted;
@property (nonatomic, readonly) BOOL isActiveChat;
@property (nonatomic, assign) BOOL isEncrypted;

@property (nonatomic, readonly) BOOL isGroup;
@property (nonatomic, readonly) NSString* groupSubject;
@property (nonatomic, readonly) NSString* mucType;
@property (nonatomic, readonly) NSString* accountNickInGroup;
@property (nonatomic, readonly) BOOL isMentionOnly;

@property (nonatomic, readonly) NSString* subscription; //roster subbscription state
@property (nonatomic, readonly) NSString* ask; //whether we have tried to subscribe

@property (nonatomic, readonly) NSString* contactDisplayName;
@property (nonatomic, readonly) NSString* contactDisplayNameWithoutSelfnotesPrefix;

-(NSString*) contactDisplayNameWithFallback:(NSString* _Nullable) fallbackName;
-(NSString*) contactDisplayNameWithFallback:(NSString* _Nullable) fallbackName andSelfnotesPrefix:(BOOL) hasSelfnotesPrefix;
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
-(void) removeShareInteractions;

-(NSUInteger) hash;

@end

NS_ASSUME_NONNULL_END
