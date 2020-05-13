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

@interface MLContact : NSObject <NSCoding>

/**
 account number in the database should be an integer
 */

@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *contactJid;

@property (nonatomic, copy) NSString *fullName;
/**
 usually user assigned nick name
 */
@property (nonatomic, copy) NSString *nickName;

@property (nonatomic, copy) NSString *imageFile;

/**
 xmpp state text
 */
@property (nonatomic, copy) NSString *state;

/**
 xmpp status message
 */
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, copy) NSDate *lastMessageTime;

/**
 used to display the badge on a row
 */
@property (nonatomic, assign) NSInteger unreadCount;

@property (nonatomic, assign) BOOL isOnline;

@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy) NSString *groupSubject;
@property (nonatomic, copy) NSString *accountNickInGroup;

@property (nonatomic, copy) NSString *subscription; //roster subbscription state
@property (nonatomic, copy) NSString *ask; //whether we have tried to subscribe 

/**
 picks nick, full or jid to display
 */
-(NSString *) contactDisplayName;

+(MLContact *) contactFromDictionary:(NSDictionary *) dic;
+(MLContact *) contactFromDictionary:(NSDictionary *) dic withDateFormatter:(NSDateFormatter *) formatter;

@end

NS_ASSUME_NONNULL_END
