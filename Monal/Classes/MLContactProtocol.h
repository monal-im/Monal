//
//  MLContactProtocol.h
//  monalxmpp
//
//  Created by Thilo Molitor on 03.12.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#ifndef MLContactProtocol_h
#define MLContactProtocol_h

NS_ASSUME_NONNULL_BEGIN

@class UIImage;
@class MLMessage;
@class xmpp;

@protocol MLContactProtocol <NSObject>

@property (nonatomic, readonly) BOOL isMuc;
@property (nonatomic, readonly) BOOL isSelf;
@property (nonatomic, readonly) NSString* contactDisplayName;
@property (nonatomic, readonly) xmpp* _Nullable account;

@property (nonatomic, readonly, copy) UIImage* avatar;
@property (nonatomic, readonly) BOOL hasAvatar;

@property (readonly) NSString* id;     //for Identifiable protocol

-(BOOL) isEqualToContact:(id<MLContactProtocol>) contact;
-(BOOL) isEqualToMessage:(MLMessage*) message;
-(BOOL) isEqual:(id _Nullable) object;

@end

NS_ASSUME_NONNULL_END

#endif /* MLContactProtocol_h */
