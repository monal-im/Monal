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

@property (nonatomic, readonly) NSString *user;
@property (nonatomic, readonly) NSString *domain;

-(NSString *) user;
-(NSString *) domain;


/**
 Creates a new identity. Password can be null if we plan on using oauth.
 */
-(id) initWithJid:(nonnull NSString *)jid password:(NSString *) password andResource:(nonnull NSString *) resource;

/**
 Update password is only used when using Oauth or the password is changed in app
 */
-(void) updatPassword:(NSString *) newPassword;

@end

NS_ASSUME_NONNULL_END
