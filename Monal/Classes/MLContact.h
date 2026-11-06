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

typedef NSString* MLContactSubscription NS_TYPED_ENUM NS_SWIFT_NAME(ContactSubscription);
FOUNDATION_EXPORT MLContactSubscription const kSubBoth NS_SWIFT_NAME(both);
FOUNDATION_EXPORT MLContactSubscription const kSubNone NS_SWIFT_NAME(none);
FOUNDATION_EXPORT MLContactSubscription const kSubTo NS_SWIFT_NAME(to);
FOUNDATION_EXPORT MLContactSubscription const kSubFrom NS_SWIFT_NAME(from);
FOUNDATION_EXPORT MLContactSubscription const kSubRemove NS_SWIFT_NAME(remove);
FOUNDATION_EXPORT MLContactSubscription const kSubNotListedLocally NS_SWIFT_NAME(notListedLocally);

typedef NSString* MLContactSubscriptionAsk NS_TYPED_ENUM NS_SWIFT_NAME(ContactSubscriptionAsk);
FOUNDATION_EXPORT MLContactSubscriptionAsk const kAskSubscribe NS_SWIFT_NAME(subscribe);

@class xmpp;
@class MLMessage;
@class UIImage;

@interface MLContact : NSObject <NSSecureCoding, MLContactProtocol>
+(MLContact*) makeDummyContact:(int) type;

+(BOOL) supportsSecureCoding;

+(NSString*) ownDisplayNameForAccount:(xmpp*) account;

@property (nonatomic, readonly) BOOL isListedLocally;
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

@property (nonatomic, readonly) NSString* groupSubject;
@property (nonatomic, readonly) NSString* mucType;
@property (nonatomic, readonly) NSString* accountNickInGroup;
@property (nonatomic, readonly) BOOL isMentionOnly;

@property (nonatomic, readonly) MLContactSubscription subscription; //roster subbscription state
@property (nonatomic, readonly) MLContactSubscriptionAsk ask; //whether we have tried to subscribe

@property (nonatomic, readonly) NSString* contactDisplayNameWithoutSelfnotesPrefix;

// This property is used to avoid querying MAM if the top of the archive
// was already reached in a previous query
@property (nonatomic, readonly) BOOL hasReachedMamArchiveTop;

@property (nonatomic, readonly) BOOL hasExplicitOmemoTrustActivated;

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
-(void) activateExplicitOmemoTrust;
-(void) removeShareInteractions;

@end

NS_ASSUME_NONNULL_END
