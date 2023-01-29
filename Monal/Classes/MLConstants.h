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
#ifdef IS_ALPHA
    #define kAppGroup @"group.monalalpha"
    #define kMonalOpenURL [NSURL URLWithString:@"monalAlphaOpen://"]
    #define kBackgroundProcessingTask @"im.monal.alpha.process"
    #define kBackgroundRefreshingTask @"im.monal.alpha.refresh"
#else
    #define kAppGroup @"group.monal"
    #define kMonalOpenURL [NSURL URLWithString:@"monalOpen://"]
    #define kBackgroundProcessingTask @"im.monal.process"
    #define kBackgroundRefreshingTask @"im.monal.refresh"
#endif

#define kMonalKeychainName @"Monal"

//this is in seconds
#if TARGET_OS_MACCATALYST
	#define SHORT_PING 16.0
	#define LONG_PING 32.0
    #define MUC_PING 600
    #define BGFETCH_DEFAULT_INTERVAL 3600*1
#else
	#define SHORT_PING 4.0
	#define LONG_PING 16.0
    #define MUC_PING 3600
    #define BGFETCH_DEFAULT_INTERVAL 3600*3
#endif

@class MLContact;

//some typedefs used throughout the project
typedef void (^contactCompletion)(MLContact* _Nonnull selectedContact);
typedef void (^accountCompletion)(NSInteger accountRow);
typedef void (^monal_void_block_t)(void);
typedef void (^monal_id_block_t)(id _Nonnull);
typedef void (^monal_upload_completion_t)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error);

typedef enum NotificationPrivacySettingOption {
    DisplayNameAndMessage,
    DisplayOnlyName,
    DisplayOnlyPlaceholder
} NotificationPrivacySettingOption;


//some useful macros
#define weakify(var)                        __weak __typeof__(var) AHKWeak_##var = var
#define strongify(var)                      _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wshadow\"") __strong __typeof__(var) var = AHKWeak_##var; _Pragma("clang diagnostic pop")
#define nilWrapper(var)                     (var == nil ? (id)[NSNull null] : (id)var)
#define nilExtractor(var)                   ((id)var == [NSNull null] ? nil : var)
#define nilDefault(var, def)                (var == nil || (id)var == [NSNull null] ? def : var)
#define emptyDefault(var, eq, def)          (var == nil || (id)var == [NSNull null] || [var isEqual:eq] ? def : var)
#define updateIfIdNotEqual(a, b)            if(a != b && ![a isEqual:b]) a = b
#define updateIfPrimitiveNotEqual(a, b)     if(a != b) a = b
#define var                                 __auto_type 
#define let                                 const __auto_type
#define bool2str(b)                         (b ? @"YES" : @"NO")

//make sure we don't define this twice
#ifndef STRIP_PARENTHESES
    //see https://stackoverflow.com/a/62984543/3528174
    #define STRIP_PARENTHESES(X) __ESC(__ISH X)
    #define __ISH(...) __ISH __VA_ARGS__
    #define __ESC(...) __ESC_(__VA_ARGS__)
    #define __ESC_(...) __VAN ## __VA_ARGS__
    #define __VAN__ISH
#endif

#define unreachable() { \
    DDLogError(@"unreachable: %s %d %s", __FILE__, __LINE__, __func__); \
    NSAssert(NO, @"unreachable"); \
    while(1); \
}

// https://clang-analyzer.llvm.org/faq.html#unlocalized_string
__attribute__((annotate("returns_localized_nsstring")))
static inline NSString* _Nonnull LocalizationNotNeeded(NSString* _Nonnull s)
{
  return s;
}

//some xmpp related constants
#define kId @"id"
#define kMessageId @"kMessageId"

#define kRegisterNameSpace @"jabber:iq:register"

//all other constants needed
#define kMonalCallRemoved @"kMonalCallRemoved"
#define kMonalCallAdded @"kMonalCallAdded"
#define kMonalIncomingJMIStanza @"kMonalIncomingJMIStanza"
#define kMonalIncomingVoipCall @"kMonalIncomingVoipCall"
#define kMonalIncomingSDP @"kMonalIncomingSDP"
#define kMonalIncomingICECandidate @"kMonalIncomingICECandidate"
#define kMonalWillBeFreezed @"kMonalWillBeFreezed"
#define kMonalIsFreezed @"kMonalIsFreezed"
#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMonalMucSubjectChanged @"kMonalMucSubjectChanged"
#define kMonalDeletedMessageNotice @"kMonalDeletedMessageNotice"
#define kMonalDisplayedMessagesNotice @"kMonalDisplayedMessagesNotice"
#define kMonalHistoryMessagesNotice @"kMonalHistoryMessagesNotice"
#define kMLMessageSentToContact @"kMLMessageSentToContact"
#define kMonalSentMessageNotice @"kMLSentMessageNotice"
#define kMonalMessageFiletransferUpdateNotice @"kMonalMessageFiletransferUpdateNotice"

#define kMonalNewPresenceNotice @"kMonalNewPresenceNotice"
#define kMonalLastInteractionUpdatedNotice @"kMonalLastInteractionUpdatedNotice"
#define kMonalMessageReceivedNotice @"kMonalMessageReceivedNotice"
#define kMonalMessageDisplayedNotice @"kMonalMessageDisplayedNotice"
#define kMonalMessageErrorNotice @"kMonalMessageErrorNotice"
#define kMonalReceivedMucInviteNotice @"kMonalReceivedMucInviteNotice"
#define kXMPPError @"kXMPPError"
#define kScheduleBackgroundTask @"kScheduleBackgroundTask"
#define kMonalUpdateUnread @"kMonalUpdateUnread"

#define kMLIsLoggedInNotice @"kMLIsLoggedInNotice"
#define kMLResourceBoundNotice @"kMLResourceBoundNotice"
#define kMonalFinishedCatchup @"kMonalFinishedCatchup"
#define kMonalFinishedOmemoBundleFetch @"kMonalFinishedOmemoBundleFetch"
#define kMonalUpdateBundleFetchStatus @"kMonalUpdateBundleFetchStatus"
#define kMonalIdle @"kMonalIdle"
#define kMonalFiletransfersIdle @"kMonalFiletransfersIdle"
#define kMonalNotIdle @"kMonalNotIdle"

#define kMonalBackgroundChanged @"kMonalBackgroundChanged"
#define kMLMAMPref @"kMLMAMPref"

#define kMonalAccountStatusChanged @"kMonalAccountStatusChanged"

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
