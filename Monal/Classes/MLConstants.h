//
//  MLConstants.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import <Foundation/Foundation.h>
#import "DDLog.h"

//used in OSX only really
#define kMonalWindowVisible @"kMonalWindowVisible"

#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMonalSentMessageNotice @"kMLSentMessageNotice"
#define kMonalSendFailedMessageNotice @"kMonalSendFailedMessageNotice"

#define kMonalMessageReceivedNotice @"kMonalMessageReceivedNotice"

#define kMonalContactOnlineNotice @"kMLContactOnlineNotice"
#define kMonalContactOfflineNotice @"kMLContactOfflineNotice"
#define kMLHasRoomsNotice @"kMLHasRoomsNotice"
#define kMLHasConnectedNotice @"kMLHasConnectedNotice"

#define kMLMAMPref @"kMLMAMPref"
#define kMLMAMMore @"kMLMAMMore"


#define kMonalCallStartedNotice @"kMonalCallStartedNotice"
#define kMonalCallRequestNotice @"kMonalCallRequestNotice"

#define kMonalAccountStatusChanged @"kMonalAccountStatusChanged"

#define kMonalContactRefresh @"kMonalContactRefresh"
#define kMonalRefreshContacts @"kMonalRefreshContacts"

#define kDelivered @"delivered"
#define kReceived @"received"

//contact cells
#define kusernameKey @"username"
#define kfullNameKey @"fullName"
#define kaccountNoKey @"accountNo"
#define kstateKey @"state"
#define kstatusKey @"status"

//info cells
#define kaccountNameKey @"accountName"
#define kinfoTypeKey @"type"
#define kinfoStatusKey @"status"

#if TARGET_OS_IPHONE
/*
 *  System Versioning Preprocessor Macros
 */
#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

#else
#endif

//temp not for relase
//#ifndef DEBUG
//#define DEBUG 1
//#endif

//temp for  a release
#ifndef DISABLE_OMEMO
#define DISABLE_OMEMO 1
#endif
