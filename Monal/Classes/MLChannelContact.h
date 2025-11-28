//
//  MLChannelContact.h
//  monalxmpp
//
//  Created by Thilo Molitor on 03.12.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <monalxmpp/MLContactProtocol.h>

#ifndef MLChannelContact_h
#define MLChannelContact_h

NS_ASSUME_NONNULL_BEGIN

@interface MLChannelContact : NSObject <NSSecureCoding, MLContactProtocol>

+(MLChannelContact*) createChannelContactFromOccupantId:(NSString*) occupantId withNick:(NSString*) nick inMuc:(MLContact*) mucContact;

@property (nonatomic, readonly) NSString* nick;
@property (nonatomic, readonly) NSString* occupantId;
@property (nonatomic, readonly) MLContact* mucContact;

@end

NS_ASSUME_NONNULL_END

#endif /* MLChannelContact_h */
