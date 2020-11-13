//
//  MLXEPSlashMeHandler.h
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2020/9/16.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLXEPSlashMeHandler : NSObject

+ (MLXEPSlashMeHandler* )sharedInstance;

/*
 By using NSString without attributes.
 */
- (NSString*)stringSlashMeWithAccountId:(NSString*)accountId
							displayName:(NSString*)displayName
                             actualFrom:(NSString*)actualFrom
                                message:(NSString*)msg
                                isGroup:(BOOL) isGroup;

/*
By using NSString with attributes.
*/
- (NSMutableAttributedString*)attributedStringSlashMeWithAccountId:(NSString*)accountId
													   displayName:(NSString*)displayName
                                                        actualFrom:(NSString*)actualFrom
                                                           message:(NSString*)msg
                                                           isGroup:(BOOL)isGroup
                                                          withFont:(UIFont*) font;
@end

NS_ASSUME_NONNULL_END
