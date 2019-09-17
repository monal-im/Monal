//
//  MLPush.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLPush : NSObject
+(NSString *) stringFromToken:(NSData *) tokenIn ;
-(void) postToPushServer:(NSString *) token;
-(NSString *) pushServer ; 
@end

NS_ASSUME_NONNULL_END
