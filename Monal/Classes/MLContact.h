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

@interface MLContact : NSObject <NSSecureCoding>

+(BOOL) supportsSecureCoding;

+(NSString*) ownDisplayNameForAccount:(xmpp*) account;

-(BOOL) isSubscribed;

+(MLContact*) createContactFromJid:(NSString*) jid andAccountNo:(NSString*) accountNo;

/**
 account number in the database should be an integer
 */

@property (nonatomic, copy) NSString* accountId;
@property (nonatomic, copy) NSString* contactJid;

@property (nonatomic, copy) NSString* fullName;
/**
 usually user assigned nick name
 */
@property (nonatomic, copy) NSString* nickName;

/**
 xmpp state text
 */
@property (nonatomic, copy) NSString* state;

/**
 xmpp status message
 */
@property (nonatomic, copy) NSString* statusMessage;
@property (nonatomic, copy) NSDate* lastMessageTime;

/**
 used to display the badge on a row
 */
@property (nonatomic, assign) NSInteger unreadCount;

@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isMuted;
@property (nonatomic, assign) BOOL isActiveChat;
@property (nonatomic, assign) BOOL isEncrypted;

@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy) NSString* groupSubject;
@property (nonatomic, copy) NSString* mucType;
@property (nonatomic, copy) NSString* accountNickInGroup;

@property (nonatomic, copy) NSString* subscription; //roster subbscription state
@property (nonatomic, copy) NSString* ask; //whether we have tried to subscribe

/**
 picks nick, full or note part of jid to display
 */
-(NSString*) contactDisplayName;

-(void) updateWithContact:(MLContact*) contact;

@end

NS_ASSUME_NONNULL_END
