//
//  MLXEPSlashMeHandler.m
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2020/9/16.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLXEPSlashMeHandler.h"

@implementation MLXEPSlashMeHandler

#pragma mark initilization
+ (MLXEPSlashMeHandler* )sharedInstance
{
    static dispatch_once_t once;
    static MLXEPSlashMeHandler* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[MLXEPSlashMeHandler alloc] init] ;        
    });
    return sharedInstance;
}

- (NSString*)stringSlashMeWithAccountId:(NSString*)accountId buddy:(NSString*)buddy nickName:(NSString*)nickName fullName:(NSString*)fullName actualFrom:(NSString*)actualFrom message:(NSString*)msg isGroup:(BOOL) isGroup
{
    NSRange replacedRange = NSMakeRange(0, 3);
    
    NSString* displayName = @"";
    
    if (isGroup)
    {
        
        if (actualFrom != nil)
        {
            displayName = actualFrom;
        }
        else
        {
            displayName = @"";
        }
    }
    else
    {
        if (fullName == nil || fullName.length == 0)
        {
            if (nickName == nil  || nickName.length == 0)
            {
                displayName = buddy;
            }
            else
            {
                displayName = nickName;
            }
        }
        else
        {
            displayName = fullName;
        }
    }
    
    NSMutableString *replacedMessageText = [[NSMutableString alloc] initWithString:msg];
    NSMutableString *replacedName  = [[NSMutableString alloc] initWithString:[NSString stringWithFormat:@"* %@",displayName]];
    
    [replacedMessageText replaceCharactersInRange:replacedRange withString:replacedName];
        
    return replacedMessageText;
}

- (NSMutableAttributedString*)attributedStringSlashMeWithAccountId:(NSString*)accountId buddy:(NSString*)buddy nickName:(NSString*)nickName fullName:(NSString*)fullName actualFrom:(NSString*)actualFrom message:(NSString*)msg isGroup:(BOOL) isGroup withFont:(UIFont*) font
{
    NSString* resultString = [self stringSlashMeWithAccountId:(NSString*)accountId
                                                        buddy:buddy
                                                     nickName:nickName
                                                     fullName:fullName
                                                   actualFrom:actualFrom
                                                      message:msg
                                                      isGroup:isGroup];
    
    NSDictionary *attrMsgDict = @{
        NSFontAttributeName:font
    };
    
    NSMutableAttributedString *replaceAttrMessageText = [[NSMutableAttributedString alloc] initWithString:resultString attributes:attrMsgDict];
    return replaceAttrMessageText;
}

@end
