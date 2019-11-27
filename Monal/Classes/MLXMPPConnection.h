//
//  MLXMPPConnection.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLXMPPServer.h"
#import "MLXMPPIdentity.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLXMPPConnection : NSObject

@property (nonatomic, readonly) MLXMPPServer *server;
@property (nonatomic, readonly) MLXMPPIdentity *identity;
@property (nonatomic, readonly) NSString* resource;
@property (nonatomic, readonly) NSString* boundJid;


//State
//Discovered caps

@end

NS_ASSUME_NONNULL_END
