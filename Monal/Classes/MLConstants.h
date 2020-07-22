//
//  MLConstants.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import <Foundation/Foundation.h>
#import "MLContact.h"

@import CocoaLumberjack;
#ifdef  DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelInfo;
#endif
#import "MLLogFileManager.h"


typedef void (^contactCompletion)(MLContact *selectedContact);
typedef void (^accountCompletion)(NSInteger accountRow);
typedef void (^monal_void_block_t)();

#define kAppGroup @"group.monal"

#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMLMessageSentToContact @"kMLMessageSentToContact"
#define kMonalSentMessageNotice @"kMLSentMessageNotice"
#define kMonalSendFailedMessageNotice @"kMonalSendFailedMessageNotice"

#define kMonalLastInteractionUpdatedNotice @"kMonalLastInteractionUpdatedNotice"
#define kMonalMessageReceivedNotice @"kMonalMessageReceivedNotice"
#define kMonalMessageErrorNotice @"kMonalMessageErrorNotice"
#define kMonalReceivedMucInviteNotice @"kMonalReceivedMucInviteNotice"

#define kMLHasRoomsNotice @"kMLHasRoomsNotice"
#define kMLHasConnectedNotice @"kMLHasConnectedNotice"
#define kMonalFinishedCatchup @"kMonalFinishedCatchup"
#define kMonalIdle @"kMonalIdle"

#define kMonalPresentChat @"kMonalPresentChat"

#define kMLMAMPref @"kMLMAMPref"


#define kMonalCallStartedNotice @"kMonalCallStartedNotice"
#define kMonalCallRequestNotice @"kMonalCallRequestNotice"

#define kMonalAccountStatusChanged @"kMonalAccountStatusChanged"
#define kMonalAccountAuthRequest @"kMonalAccountAuthRequest"

#define kMonalContactRefresh @"kMonalContactRefresh"
#define kMonalRefreshContacts @"kMonalRefreshContacts"

// chat
#define kMonalChatMaxAllowedTextLen 2048 // max count of char's in a single message

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

//temp not for relase
#ifndef DEBUG
#define DEBUG 1
#endif

//temp for  a release
//#ifndef DISABLE_OMEMO
//#define DISABLE_OMEMO 1
//#endif
