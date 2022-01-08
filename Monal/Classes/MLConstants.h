//
//  MLConstants.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import "MLHandler.h"

@import CocoaLumberjack;
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#import "MLLogFileManager.h"
#import "MLLogFormatter.h"


//configure app group constants
#define kAppGroup @"group.monal"
#define kMonalKeychainName @"Monal"

//this is in seconds
#if TARGET_OS_MACCATALYST
	#define SHORT_PING 16.0
	#define LONG_PING 32.0
#else
	#define SHORT_PING 4.0
	#define LONG_PING 16.0
#endif

@class MLContact;

//some typedefs used throughout the project
typedef void (^contactCompletion)(MLContact *selectedContact);
typedef void (^accountCompletion)(NSInteger accountRow);
typedef void (^monal_void_block_t)(void);
typedef void (^monal_id_block_t)(id);

typedef enum NotificationPrivacySettingOption {
    DisplayNameAndMessage,
    DisplayOnlyName,
    DisplayOnlyPlaceholder
} NotificationPrivacySettingOption;


//some useful macros
#define weakify(var)                        __weak __typeof__(var) AHKWeak_##var = var
#define strongify(var)                      _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wshadow\"") __strong __typeof__(var) var = AHKWeak_##var; _Pragma("clang diagnostic pop")
#define nilWrapper(var)                     (var == nil           ? [NSNull null] : var)
#define nilExtractor(var)                   (var == [NSNull null] ? nil           : var)
#define nilDefault(var, def)                (var == nil ? def : var)
#define updateIfIdNotEqual(a, b)            if(a != b && ![a isEqual:b]) a = b
#define updateIfPrimitiveNotEqual(a, b)     if(a != b) a = b


//see https://stackoverflow.com/a/62984543/3528174
#define STRIP_PARENTHESES(X) __ESC(__ISH X)
#define __ISH(...) __ISH __VA_ARGS__
#define __ESC(...) __ESC_(__VA_ARGS__)
#define __ESC_(...) __VAN ## __VA_ARGS__
#define __VAN__ISH

#if defined(IS_ALPHA) || defined(DEBUG)
    #define unreachable() { \
        DDLogError(@"unreachable: %s %d %s", __FILE__, __LINE__, __func__); \
        NSAssert(NO, @"unreachable"); \
    }
#else
    #define unreachable() { \
        DDLogError(@"unreachable: %s %d %s", __FILE__, __LINE__, __func__); \
    }
#endif

// https://clang-analyzer.llvm.org/faq.html#unlocalized_string
__attribute__((annotate("returns_localized_nsstring")))
static inline NSString* LocalizationNotNeeded(NSString* s)
{
  return s;
}

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
#define kMonalWillBeFreezed @"kMonalWillBeFreezed"
#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMonalMucSubjectChanged @"kMonalMucSubjectChanged"
#define kMonalDeletedMessageNotice @"kMonalDeletedMessageNotice"
#define kMonalDisplayedMessagesNotice @"kMonalDisplayedMessagesNotice"
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

#define kMonalBackgroundChanged @"kMonalBackgroundChanged"

#define kMonalPresentChat @"kMonalPresentChat"

#define kMLMAMPref @"kMLMAMPref"


#define kMonalCallStartedNotice @"kMonalCallStartedNotice"
#define kMonalCallRequestNotice @"kMonalCallRequestNotice"

#define kMonalAccountStatusChanged @"kMonalAccountStatusChanged"
#define kMonalAccountAuthRequest @"kMonalAccountAuthRequest"

#define kMonalRefresh @"kMonalRefresh"
#define kMonalContactRefresh @"kMonalContactRefresh"
#define kMonalXmppUserSoftWareVersionRefresh @"kMonalXmppUserSoftWareVersionRefresh"
#define kMonalBlockListRefresh @"kMonalBlockListRefresh"
#define kMonalContactRemoved @"kMonalContactRemoved"

// max count of char's in a single message (both: sending and receiving)
#define kMonalChatMaxAllowedTextLen 2048

#if TARGET_OS_MACCATALYST
#define kMonalBackscrollingMsgCount 75
#else
#define kMonalBackscrollingMsgCount 50
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

//blocking rules
#define kBlockingNoMatch 0
#define kBlockingMatchedNodeHostResource 1
#define kBlockingMatchedNodeHost 2
#define kBlockingMatchedHostResource 3
#define kBlockingMatchedHost 4

//use this to completely disable omemo in build
//#ifndef DISABLE_OMEMO
//#define DISABLE_OMEMO 1
//#endif

//build MLXMLNode query statistics (will only optimize MLXMLNode queries if *not* defined)
//#define QueryStatistics 1

#define geoPattern  @"^geo:(-?(?:90|[1-8][0-9]|[0-9])(?:\\.[0-9]{1,32})?),(-?(?:180|1[0-7][0-9]|[0-9]{1,2})(?:\\.[0-9]{1,32})?)$"
