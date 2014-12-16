//
//  MLConstants.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import <Foundation/Foundation.h>
#import "DDLog.h"


#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMonalSentMessageNotice @"kMLSentMessageNotice"
#define kMonalSendFailedMessageNotice @"kMonalSendFailedMessageNotice"

#define kMonalContactOnlineNotice @"kMLContactOnlineNotice"
#define kMonalContactOfflineNotice @"kMLContactOfflineNotice"
#define kMLHasRoomsNotice @"kMLHasRoomsNotice"
#define kMonalCallStartedNotice @"kMonalCallStartedNotice"
#define kMLHasConnectedNotice @"kMLHasConnectedNotice"


/*
 *  System Versioning Preprocessor Macros
 */

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

