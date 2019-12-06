//
//  MLContact.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLContact : NSObject

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

/**
 picks nick, full or jid to display
 */
-(NSString *) contactDisplayName;

+(MLContact *) contactFromDictionary:(NSDictionary *) dic;
+(MLContact *) contactFromDictionary:(NSDictionary *) dic withDateFormatter:(NSDateFormatter *) formatter;

@end

NS_ASSUME_NONNULL_END
