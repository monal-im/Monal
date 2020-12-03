//
//  MLConstants.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import <Foundation/Foundation.h>
#import "MLHandler.h"

@import CocoaLumberjack;
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#import "MLLogFileManager.h"
#import "MLLogFormatter.h"


//configure app group constants
#define kAppGroup @"group.monal"

//this is in seconds
#define SHORT_PING 4.0
#define LONG_PING 16.0

@class MLContact;

//some typedefs used throughout the project
typedef void (^contactCompletion)(MLContact *selectedContact);
typedef void (^accountCompletion)(NSInteger accountRow);
typedef void (^monal_void_block_t)(void);

typedef enum NotificationPrivacySettingOption {
    DisplayNameAndMessage,
    DisplayOnlyName,
    DisplayOnlyPlaceholder
} NotificationPrivacySettingOption;


//some useful macros
#define weakify(var) __weak __typeof__(var) AHKWeak_##var = var
#define strongify(var) _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wshadow\"") __strong __typeof__(var) var = AHKWeak_##var; _Pragma("clang diagnostic pop")
#define nilWrapper(var) (var ? var : [NSNull null])
#define nilExtractor(var) (var == [NSNull null] ? nil : var)

//some xmpp related constants
#define kRegServer @"yax.im"
#define kMessageDeletedBody @"eu.siacs.conversations.message_deleted"

#define kXMLNS @"xmlns"
#define kId @"id"
#define kJid @"jid"
#define kMessageId @"kMessageId"

#define kRegisterNameSpace @"jabber:iq:register"
#define kDataNameSpace @"jabber:x:data"

//all other constants needed
#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMonalDeletedMessageNotice @"kMonalDeletedMessageNotice"
#define kMonalDisplayedMessageNotice @"kMonalDisplayedMessageNotice"
#define kMonalHistoryMessagesNotice @"kMonalHistoryMessagesNotice"
#define kMLMessageSentToContact @"kMLMessageSentToContact"
#define kMonalSentMessageNotice @"kMLSentMessageNotice"
#define kMonalMessageFiletransferUpdateNotice @"kMonalMessageFiletransferUpdateNotice"

#define kMonalLastInteractionUpdatedNotice @"kMonalLastInteractionUpdatedNotice"
#define kMonalMessageReceivedNotice @"kMonalMessageReceivedNotice"
#define kMonalMessageDisplayedNotice @"kMonalMessageDisplayedNotice"
#define kMonalMessageErrorNotice @"kMonalMessageErrorNotice"
#define kMonalReceivedMucInviteNotice @"kMonalReceivedMucInviteNotice"
#define kXMPPError @"kXMPPError"
#define kScheduleBackgroundFetchingTask @"kScheduleBackgroundFetchingTask"
#define kMonalUpdateUnread @"kMonalUpdateUnread"

#define kMLHasConnectedNotice @"kMLHasConnectedNotice"
#define kMonalFinishedCatchup @"kMonalFinishedCatchup"
#define kMonalFinishedOmemoBundleFetch @"kMonalFinishedOmemoBundleFetch"
#define kMonalUpdateBundleFetchStatus @"kMonalUpdateBundleFetchStatus"
#define kMonalIdle @"kMonalIdle"
#define kMonalFiletransfersIdle @"kMonalFiletransfersIdle"

#define kMonalPresentChat @"kMonalPresentChat"

#define kMLMAMPref @"kMLMAMPref"


#define kMonalCallStartedNotice @"kMonalCallStartedNotice"
#define kMonalCallRequestNotice @"kMonalCallRequestNotice"

#define kMonalAccountStatusChanged @"kMonalAccountStatusChanged"
#define kMonalAccountAuthRequest @"kMonalAccountAuthRequest"

#define kMonalRefresh @"kMonalRefresh"
#define kMonalContactRefresh @"kMonalContactRefresh"
#define kMonalXmppUserSoftWareVersionRefresh @"kMonalXmppUserSoftWareVersionRefresh"

// max count of char's in a single message (both: sending and receiving)
#define kMonalChatMaxAllowedTextLen 2048

#if TARGET_OS_MACCATALYST
#define kMonalChatFetchedMsgCnt 75
#else
#define kMonalChatFetchedMsgCnt 50
#endif

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

//temp not for release
#ifndef DEBUG
#define DEBUG 1
#endif

//use this to completely disable omemo in build
//#ifndef DISABLE_OMEMO
//#define DISABLE_OMEMO 1
//#endif

//build MLXMLNode query statistics (will only optimize MLXMLNode queries if *not* defined)
//#define QueryStatistics 1



