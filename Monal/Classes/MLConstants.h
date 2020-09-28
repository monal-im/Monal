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
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#import "MLLogFileManager.h"
#import "MLLogFormatter.h"


//configure app group constants
#define kAppGroup @"group.monal"


// some typedefs used throughout the project
typedef void (^contactCompletion)(MLContact *selectedContact);
typedef void (^accountCompletion)(NSInteger accountRow);
typedef void (^monal_void_block_t)(void);


//some xmpp related constants
#define kRegServer @"yax.im"

#define kXMLNS @"xmlns"
#define kId @"id"
#define kJid @"jid"

#define kRegisterNameSpace @"jabber:iq:register"
#define kDataNameSpace @"jabber:x:data"
#define kBobNameSpace @"urn:xmpp:bob"
#define kStanzasNameSpace @"urn:ietf:params:xml:ns:xmpp-stanzas"


//all other constants needed
#define kMonalNewMessageNotice @"kMLNewMessageNotice"
#define kMonalHistoryMessagesNotice @"kMonalHistoryMessagesNotice"
#define kMLMessageSentToContact @"kMLMessageSentToContact"
#define kMonalSentMessageNotice @"kMLSentMessageNotice"

#define kMonalLastInteractionUpdatedNotice @"kMonalLastInteractionUpdatedNotice"
#define kMonalMessageReceivedNotice @"kMonalMessageReceivedNotice"
#define kMonalMessageErrorNotice @"kMonalMessageErrorNotice"
#define kMonalReceivedMucInviteNotice @"kMonalReceivedMucInviteNotice"

#define kMLHasConnectedNotice @"kMLHasConnectedNotice"
#define kMonalFinishedCatchup @"kMonalFinishedCatchup"
#define kMonalIdle @"kMonalIdle"

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

//temp for  a release
//#ifndef DISABLE_OMEMO
//#define DISABLE_OMEMO 1
//#endif
