//
//  MLMessage.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM (NSInteger, MessageType) {
    MessageTypeText =0,
    MessageTypeImage,
    MessageTypeUrl,
    MessageTypeStatus
};

/**
 message object intended to be passed around and eventually used to render
 */
@interface MLMessage : NSObject


/**
 account number in the database should be an integer
 */
@property (nonatomic, copy) NSNumber *accountId;

/**
 The message's unique identifier
 */
@property (nonatomic, copy) NSString *messageId;

/**
 Actual sender will differ from the "from" when in a group chat
 */
@property (nonatomic, copy) NSString *actualFrom;
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy) NSString *to;

@property (nonatomic, assign) MessageType messagetype;

@property (nonatomic, copy) NSString *messageText;

/**
 If the text was parsed into a URL
 */
@property (nonatomic, copy) NSURL *url;

@property (nonatomic, copy) NSDate *delayTimeStamp;
@property (nonatomic, copy) NSDate *sentTime;

/**
 usually used to indicate if the message was  encrypted on the wire, not in this payload
 */
@property (nonatomic, assign) BOOL encrypted;

/**
 whether the text was sent out on the wire not if it was delivered to the recipient
 */
@property (nonatomic, assign) BOOL sent;



@end

NS_ASSUME_NONNULL_END
