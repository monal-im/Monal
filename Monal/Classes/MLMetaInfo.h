//
//  MLMetaInfo.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/6/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLMetaInfo : NSObject

/**
 Retrieves opengraph meta tag from provided body
 */
+ (NSString * _Nullable) ogContentWithTag:(NSString *) tag inHTML:(NSString *) body;

@end

NS_ASSUME_NONNULL_END
