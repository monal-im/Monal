//
//  MLEncryptedPayload.h
//  Monal
//
//  Created by Anurodh Pokharel on 4/19/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLEncryptedPayload : NSObject
@property (nonatomic, strong, readonly) NSData* body; // the acully encrytped content
@property (nonatomic, strong, readonly) NSData* key; //key + tag as needed by OMEMO
@property (nonatomic, strong, readonly) NSData* iv;
@property (nonatomic, strong, readonly) NSData* authTag; //just tag

-(MLEncryptedPayload *) initWithBody:(NSData *) body key:(NSData *) key iv:(NSData *) iv authTag:(NSData *) authTag;
-(MLEncryptedPayload *) initWithKey:(NSData *) key iv:(NSData *) iv;

@end

NS_ASSUME_NONNULL_END
