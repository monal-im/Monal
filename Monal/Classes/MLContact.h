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
@property (nonatomic, copy) NSString *contactDisplayName;

@property (nonatomic, copy) NSString *image;

/**
 xmpp state text
 */
@property (nonatomic, copy) NSString *state;

/**
 xmppp sttus message
 */
@property (nonatomic, copy) NSString *statusMessage;



@end

NS_ASSUME_NONNULL_END
