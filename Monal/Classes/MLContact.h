//
//  MLContact.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLContactProtocol.h>

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

@interface MLContact : NSObject <NSSecureCoding, MLContactProtocol>
+(MLContact*) makeDummyContact:(int) type;

+(BOOL) supportsSecureCoding;

+(NSString*) ownDisplayNameForAccount:(xmpp*) account;

@property (nonatomic, readonly) BOOL isInRoster;
@property (nonatomic, readonly) BOOL isSubscribedTo;
@property (nonatomic, readonly) BOOL isSubscribedFrom;
@property (nonatomic, readonly) BOOL isSubscribedBoth;
@property (nonatomic, readonly) BOOL hasIncomingContactRequest;
@property (nonatomic, readonly) BOOL hasOutgoingContactRequest;

+(MLContact*) createContactFromJid:(NSString*) jid andAccountID:(NSNumber*) accountID;

/**
 account number in the database should be an integer
 */
@property (nonatomic, readonly) NSNumber* accountID;
@property (nonatomic, readonly) NSString* contactJid;
@property (nonatomic, readonly) NSString* fullName;
@property (nonatomic, readonly) NSSet<NSString*>* rosterGroups;
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
@property (nonatomic, readonly) BOOL isTyping;

/**
 used to display the badge on a row
 */
@property (nonatomic, readonly) NSInteger unreadCount;

@property (nonatomic, readonly) BOOL isPinned;
@property (nonatomic, readonly) BOOL isBlocked;
@property (nonatomic, readonly) BOOL isMuted;
@property (nonatomic, readonly) BOOL isActiveChat;
@property (nonatomic, assign) BOOL isEncrypted;

@property (nonatomic, readonly) BOOL isMuc;
@property (nonatomic, readonly) NSString* groupSubject;
@property (nonatomic, readonly) NSString* mucType;
@property (nonatomic, readonly) NSString* accountNickInGroup;
@property (nonatomic, readonly) BOOL isMentionOnly;

@property (nonatomic, readonly) NSString* subscription; //roster subbscription state
@property (nonatomic, readonly) NSString* ask; //whether we have tried to subscribe

@property (nonatomic, readonly) NSString* contactDisplayNameWithoutSelfnotesPrefix;

// This property is used to avoid querying MAM if the top of the archive
// was already reached in a previous query
@property (nonatomic, readonly) BOOL hasReachedMamArchiveTop;

-(NSString*) contactDisplayNameWithFallback:(NSString* _Nullable) fallbackName;
-(NSString*) contactDisplayNameWithFallback:(NSString* _Nullable) fallbackName andSelfnotesPrefix:(BOOL) hasSelfnotesPrefix;
-(void) refresh;
-(void) updateUnreadCount;


// *** mutating methods (for swiftui etc.) below ***

-(void) toggleMute:(BOOL) mute;
-(void) toggleMentionOnly:(BOOL) mentionOnly;
-(BOOL) toggleEncryption:(BOOL) encrypt;
-(void) togglePinnedChat:(BOOL) pinned;
-(BOOL) toggleBlocked:(BOOL) block;
-(void) removeFromRoster;
-(void) addToRoster;
-(void) clearHistory;
-(void) markReachedMamArchiveTop;
-(void) removeShareInteractions;

@end

NS_ASSUME_NONNULL_END
