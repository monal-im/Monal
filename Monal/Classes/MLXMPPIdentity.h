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

@property (atomic) NSString* jid;
@property (atomic) NSString* resource;
@property (atomic, readonly) NSString* fullJid;

@property (atomic, readonly) NSString* user;
@property (atomic, readonly) NSString* password;
@property (atomic, readonly) NSString* domain;

/**
 Creates a new identity.
 */
-(id) initWithJid:(nonnull NSString *)jid password:(nonnull NSString *) password andResource:(nonnull NSString *) resource;

/**
 Update password is only used when the password is changed in app
 */
-(void) updatPassword:(NSString *) newPassword;

-(void) bindJid:(NSString*) jid;

@end

NS_ASSUME_NONNULL_END
