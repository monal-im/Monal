//
//  MLXMPPIdentity.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Imutable class to contain the specifics of an XMPP user
 */
@interface MLXMPPIdentity : NSObject

@property (nonatomic, readonly) NSString *jid;
@property (nonatomic, readonly) NSString* password;
@property (nonatomic, readonly) NSString* resource;

-(NSString *) user;
-(NSString *) domain;

-(id) initWithJid:(NSString *)jid andPassword:(NSString *) password;

@end

NS_ASSUME_NONNULL_END
