//
//  MLXEPSlashMeHandler.h
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2020/9/16.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/DataLayer.h>

NS_ASSUME_NONNULL_BEGIN

@class MLMessage;
@class UIFont;

@interface MLXEPSlashMeHandler : NSObject

+ (MLXEPSlashMeHandler* )sharedInstance;

/*
 By using NSString without attributes.
 */
-(NSString*) stringSlashMeWithMessage:(MLMessage*) msg;

/*
By using NSString with attributes.
*/
-(NSMutableAttributedString*) attributedStringSlashMeWithMessage:(MLMessage*) msg andFont:(UIFont*) font;
@end

NS_ASSUME_NONNULL_END
