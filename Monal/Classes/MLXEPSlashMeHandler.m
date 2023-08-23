//
//  MLXEPSlashMeHandler.m
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2020/9/16.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLXEPSlashMeHandler.h"
#import "MLMessage.h"
#import "MLXMPPManager.h"

@import UIKit.NSAttributedString;

@implementation MLXEPSlashMeHandler

#pragma mark initilization
+ (MLXEPSlashMeHandler* )sharedInstance
{
    static dispatch_once_t once;
    static MLXEPSlashMeHandler* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [MLXEPSlashMeHandler new] ;        
    });
    return sharedInstance;
}

- (NSString*) stringSlashMeWithMessage:(MLMessage*) msg
{
    NSRange replacedRange = NSMakeRange(0, 3);
    
    NSString* displayName;
    if(msg.inbound == NO)
        displayName = [MLContact ownDisplayNameForAccount:[[MLXMPPManager sharedInstance] getConnectedAccountForID:msg.accountId]];
    else
        displayName = msg.contactDisplayName;
    
    NSMutableString* replacedMessageText = [[NSMutableString alloc] initWithString:msg.messageText];
    NSMutableString* replacedName  = [[NSMutableString alloc] initWithString:[NSString stringWithFormat:@"* %@", displayName]];
    
    [replacedMessageText replaceCharactersInRange:replacedRange withString:replacedName];
        
    return replacedMessageText;
}

-(NSMutableAttributedString*) attributedStringSlashMeWithMessage:(MLMessage*) msg andFont:(UIFont*) font
{
    NSString* resultString = [self stringSlashMeWithMessage:msg];
    NSMutableAttributedString* replaceAttrMessageText = [[NSMutableAttributedString alloc] initWithString:resultString];
    [replaceAttrMessageText addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, resultString.length)];
    return replaceAttrMessageText;
}

@end
