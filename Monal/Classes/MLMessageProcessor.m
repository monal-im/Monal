//
//  MLMessageProcessor.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/1/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLMessageProcessor.h"
#import "DataLayer.h"
#import "SignalAddress.h"
#import "HelperTools.h"
#import "AESGcm.h"
#import "MLConstants.h"
#import "MLImageManager.h"
#import "XMPPIQ.h"
#import "MLPubSub.h"
#import "MLOMEMO.h"
#import "MLFiletransfer.h"
#import "MLMucProcessor.h"
#import "MLNotificationQueue.h"

@interface MLPubSub ()
-(void) handleHeadlineMessage:(XMPPMessage*) messageNode;
@end

static NSMutableDictionary* _typingNotifications;

@implementation MLMessageProcessor

+(void) initialize
{
    _typingNotifications = [[NSMutableDictionary alloc] init];
}

+(MLMessage* _Nullable) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account
{
    return [self processMessage:messageNode andOuterMessage:outerMessageNode forAccount:account withHistoryId:nil];
}

+(MLMessage* _Nullable) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account withHistoryId:(NSNumber* _Nullable) historyIdToUse
{
    NSAssert(messageNode != nil, @"messageNode should not be nil!");
    NSAssert(outerMessageNode != nil, @"outerMessageNode should not be nil!");
    NSAssert(account != nil, @"account should not be nil!");
    
    //this will be the return value f tis method
    //(a valid MLMessage, if this was a new message added to the db or nil, if it was another stanza not added
    //directly to the message_history table (but possibly altering it, e.g. marking someentr as read)
    MLMessage* message = nil;
    
    //history messages have already been collected mam-page wise and reordered before they are inserted into db db
    //(that's because mam always sorts the messages in a page by timestamp in ascending order)
    BOOL isMLhistory = NO;
    if([outerMessageNode check:@"{urn:xmpp:mam:2}result"] && [[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLhistory:"])
        isMLhistory = YES;
    NSAssert(!isMLhistory || historyIdToUse != nil, @"processing of MLhistory: mam messages is only possible if a history id was given");
    
    if([messageNode check:@"/<type=error>"])
    {
        DDLogError(@"Error type message received");
        
        if(![messageNode check:@"/@id"])
        {
            DDLogError(@"Ignoring error messages having an empty ID");
            return message;
        }
        
        NSString* errorType = [messageNode findFirst:@"error@type"];
        if(!errorType)
            errorType= @"unknown error";
        NSString* errorReason = [messageNode findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"];
        NSString* errorText = [messageNode findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"];
        DDLogInfo(@"Got errorType='%@', errorReason='%@', errorText='%@' for message '%@'", errorType, errorReason, errorText, [messageNode findFirst:@"/@id"]);
        
        if(errorReason)
            errorType = [NSString stringWithFormat:@"%@ - %@", errorType, errorReason];
        if(!errorText)
            errorText = NSLocalizedString(@"No further error description", @"");
        
        //update db
        [[DataLayer sharedInstance]
            setMessageId:[messageNode findFirst:@"/@id"]
            errorType:errorType
            errorReason:errorText
        ];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageErrorNotice object:nil userInfo:@{
            @"MessageID": [messageNode findFirst:@"/@id"],
            @"errorType": errorType,
            @"errorReason": errorText
        }];

        return message;
    }
    
    //ignore prosody mod_muc_notifications muc push stanzas (they are only needed to trigger an apns push)
    if([messageNode check:@"{http://quobis.com/xmpp/muc#push}notification"])
        return message;
    
    if([messageNode check:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event"])
    {
        [account.pubsub handleHeadlineMessage:messageNode];
        return message;
    }
    
    //ignore self messages after this (only pubsub data is from self)
    if([messageNode.fromUser isEqualToString:messageNode.toUser])
        return message;
    
    //ignore muc PMs (after discussion with holger we don't want to support that)
    if(![[messageNode findFirst:@"/@type"] isEqualToString:@"groupchat"] && [messageNode check:@"{http://jabber.org/protocol/muc#user}x"])
    {
        XMPPMessage* errorReply = [[XMPPMessage alloc] init];
        [errorReply.attributes setObject:@"error" forKey:@"type"];
        [errorReply.attributes setObject:messageNode.from forKey:@"to"];        //this has to be the full jid here
        [errorReply addChild:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"cancel"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"feature-not-implemented" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
            [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" withAttributes:@{} andChildren:@[] andData:@"MUC-PMs are not supported here!"]
        ] andData:nil]];
        [errorReply setStoreHint];
        [account send:errorReply];
        return message;
    }
    
    if([[messageNode findFirst:@"/@type"] isEqualToString:@"groupchat"])
    {
        // Ignore all group chat msgs from unkown groups
        if([[DataLayer sharedInstance] isContactInList:messageNode.fromUser forAccount:account.accountNo] == NO)
        {
            // ignore message
            DDLogWarn(@"Ignoring groupchat message from %@", messageNode.toUser);
            return message;
        }
    }
    else
    {
        //add contact if possible (ignore groupchats or already existing contacts)
        NSString* possibleUnkownContact;
        if([messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
            possibleUnkownContact = messageNode.toUser;
        else
            possibleUnkownContact = messageNode.fromUser;
        DDLogWarn(@"Adding possibly unknown contact for %@ to local contactlist (not updating remote roster!), doing nothing if contact is already known...", possibleUnkownContact);
        [[DataLayer sharedInstance] addContact:possibleUnkownContact forAccount:account.accountNo nickname:nil andMucNick:nil];
    }
    
    NSString* stanzaid = [outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@id"];
    //check stanza-id @by according to the rules outlined in XEP-0359
    if(!stanzaid)
    {
        if(![messageNode check:@"/<type=groupchat>"] && [account.connectionProperties.identity.jid isEqualToString:[messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@by"]])
            stanzaid = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
        else if([messageNode check:@"/<type=groupchat>"] && [messageNode.fromUser isEqualToString:[messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@by"]])
            stanzaid = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
    }
    
    NSString* messageId = [messageNode findFirst:@"/@id"];
    if(!messageId.length)
    {
        DDLogWarn(@"Empty ID using random UUID");
        messageId = [[NSUUID UUID] UUIDString];
    }
    
    //handle muc status changes or invites (this checks for the muc namespace itself)
    if([MLMucProcessor processMessage:messageNode forAccount:account])
        return message;     //the muc processor said we have stop processing
    
    NSString* decrypted;
    if([messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/header"])
    {
        if(isMLhistory)
        {
            //only show error for real messages having a fallback body, not for silent key exchange messages
            if([messageNode check:@"body#"])
            {
//use the fallback body on alpha builds (changes are good this fallback body really is the cleartext of the message because of "opportunistic" encryption)
#ifndef IS_ALPHA
                decrypted = NSLocalizedString(@"Message was encrypted with omemo and can't be decrypted anymore", @"");
#endif
            }
            else
                DDLogInfo(@"Ignoring encrypted mam history message without fallback body");
        }
        else
            decrypted = [account.omemo decryptMessage:messageNode];
    }
    
    NSString* buddyName = [messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid] ? messageNode.toUser : messageNode.fromUser;
    NSString* ownNick;
    NSString* actualFrom = messageNode.fromUser;
    NSString* participantJid = nil;
    if([messageNode check:@"/<type=groupchat>"] && messageNode.fromResource)
    {
        ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:messageNode.fromUser forAccount:account.accountNo];
        actualFrom = messageNode.fromResource;
        participantJid = [messageNode findFirst:@"/<type=groupchat>/{http://jabber.org/protocol/muc#user}x/item@jid"];
    }
    
    //inbound value for 1:1 chats
    BOOL inbound = [messageNode.toUser isEqualToString:account.connectionProperties.identity.jid];
    //inbound value for groupchat messages
    if(ownNick != nil)
    {
        inbound = ![ownNick isEqualToString:actualFrom];
        DDLogDebug(@"This is muc, inbound is now: %@ (ownNick: %@, actualFrom: %@)", inbound ? @"YES": @"NO", ownNick, actualFrom);
    }
    
    if([messageNode check:@"/<type=groupchat>/subject#"])
    {
        if(!isMLhistory)
        {
            NSString* subject = [messageNode findFirst:@"/<type=groupchat>/subject#"];
            NSString* currentSubject = [[DataLayer sharedInstance] mucSubjectforAccount:account.accountNo andRoom:messageNode.fromUser];
            DDLogInfo(@"Got MUC subject for %@: %@", messageNode.fromUser, subject);
            
            if(subject == nil || [subject isEqualToString:currentSubject])
                return message;
            
            DDLogVerbose(@"Updating subject in database: %@", subject);
            [[DataLayer sharedInstance] updateMucSubject:subject forAccount:account.accountNo andRoom:messageNode.fromUser];
            
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalMucSubjectChanged object:account userInfo:@{
                @"room": messageNode.fromUser,
                @"subject": subject,
            }];
        }
        return message;
    }
    
    //ignore all other groupchat messages coming from bare jid (only handle subject updates above)
    if([messageNode check:@"/<type=groupchat>"] && !messageNode.fromResource)
        return message;
    
    if([messageNode check:@"body#"] || decrypted)
    {
        BOOL unread = YES;
        BOOL showAlert = YES;
        
        //if incoming or mam catchup we DO want an alert, otherwise we don't
        //this will set unread=NO for MLhistory mssages, too (which is desired)
        if(
            !inbound ||
            ([outerMessageNode check:@"{urn:xmpp:mam:2}result"] && ![[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLcatchup:"])
        )
        {
            DDLogVerbose(@"Setting showAlert to NO");
            showAlert = NO;
            unread = NO;
        }
        
        NSString* messageType = kMessageTypeText;
        BOOL encrypted = NO;
        NSString* body = [messageNode findFirst:@"body#"];
        
        if(decrypted)
        {
            body = decrypted;
            encrypted = YES;
        }
        
        //messages with oob tag are filetransfers (but only if they are https urls)
        NSString* lowercaseBody = [body lowercaseString];
        if(body && [body isEqualToString:[messageNode findFirst:@"{jabber:x:oob}x/url#"]] && [lowercaseBody hasPrefix:@"https://"])
            messageType = kMessageTypeFiletransfer;
        //messages without spaces are potentially special ones
        else if([body rangeOfString:@" "].location == NSNotFound)
        {
            if([lowercaseBody hasPrefix:@"geo:"])
                messageType = kMessageTypeGeo;
            //encrypted messages having one single string prefixed with "aesgcm:" are filetransfers, too (tribal knowledge)
            else if(encrypted && [lowercaseBody hasPrefix:@"aesgcm://"])
                messageType = kMessageTypeFiletransfer;
            else if([lowercaseBody hasPrefix:@"https://"])
                messageType = kMessageTypeUrl;
        }
        DDLogInfo(@"Got message of type: %@", messageType);
        
        if(body)
        {
            NSNumber* historyId = nil;
            
            //handle LMC
            BOOL deleteMessage = NO;
            if([messageNode check:@"{urn:xmpp:message-correct:0}replace"])
            {
                NSString* messageIdToReplace = [messageNode findFirst:@"{urn:xmpp:message-correct:0}replace@id"];
                historyId = [[DataLayer sharedInstance] getHistoryIDForMessageId:messageIdToReplace from:messageNode.fromUser andAccount:account.accountNo];
                if([[DataLayer sharedInstance] checkLMCEligible:historyId encrypted:encrypted isMLhistory:isMLhistory])
                {
                    if(![body isEqualToString:kMessageDeletedBody])
                        [[DataLayer sharedInstance] updateMessageHistory:historyId withText:body];
                    else
                        deleteMessage = YES;
                }
                else
                    historyId = nil;
            }
            
            //handle normal messages or LMC messages that can not be found (but ignore deletion LMCs)
            if(historyId == nil && ![body isEqualToString:kMessageDeletedBody])
            {
                historyId = [[DataLayer sharedInstance]
                             addMessageToChatBuddy:buddyName
                                    withInboundDir:inbound
                                        forAccount:account.accountNo
                                          withBody:[body copy]
                                      actuallyfrom:actualFrom
                                    participantJid:participantJid
                                              sent:YES
                                            unread:unread
                                         messageId:messageId
                                   serverMessageId:stanzaid
                                       messageType:messageType
                                   andOverrideDate:[messageNode findFirst:@"{urn:xmpp:delay}delay@stamp|datetime"]
                                         encrypted:encrypted
                               displayMarkerWanted:[messageNode check:@"{urn:xmpp:chat-markers:0}markable"]
                                    usingHistoryId:historyIdToUse
                ];
            }
            
            message = [[DataLayer sharedInstance] messageForHistoryID:historyId];
            if(message != nil && historyId != nil)      //check historyId to make static analyzer happy
            {
                //send receive markers if requested, but DON'T do so for MLhistory messages
                if(
                    [[HelperTools defaultsDB] boolForKey:@"SendReceivedMarkers"] &&
                    ([messageNode check:@"{urn:xmpp:receipts}request"] || [messageNode check:@"{urn:xmpp:chat-markers:0}markable"]) &&
                    ![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid] &&
                    !isMLhistory
                )
                {
                    XMPPMessage* receiptNode = [[XMPPMessage alloc] init];
                    //the message type is needed so that the store hint is accepted by the server --> mirror the incoming type
                    receiptNode.attributes[@"type"] = [messageNode findFirst:@"/@type"];
                    receiptNode.attributes[@"to"] = messageNode.fromUser;
                    if([messageNode check:@"{urn:xmpp:receipts}request"])
                        [receiptNode setReceipt:[messageNode findFirst:@"/@id"]];
                    if([messageNode check:@"{urn:xmpp:chat-markers:0}markable"])
                        [receiptNode setChatmarkerReceipt:[messageNode findFirst:@"/@id"]];
                    [receiptNode setStoreHint];
                    [account send:receiptNode];
                }

                //check if we have an outgoing message sent from another client on our account
                //if true we can mark all messages from this buddy as already read by us (using the other client)
                //this only holds rue for non-MLhistory messages of course
                //WARNING: kMonalMessageDisplayedNotice goes to chatViewController, kMonalDisplayedMessageNotice goes to MLNotificationManager and activeChatsViewController/chatViewController
                //e.g.: kMonalMessageDisplayedNotice means "remote party read our message" and kMonalDisplayedMessageNotice means "we read a message"
                if(body && stanzaid && !inbound && !isMLhistory)
                {
                    DDLogInfo(@"Got outgoing message to contact '%@' sent by another client, removing all notifications for unread messages of this contact", buddyName);
                    NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:buddyName andAccount:account.accountNo tillStanzaId:stanzaid wasOutgoing:NO];
                    DDLogDebug(@"Marked as read: %@", unread);
                    
                    //remove notifications of all remotely read messages (indicated by sending a response message)
                    for(MLMessage* msg in unread)
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessageNotice object:account userInfo:@{@"message":msg}];
                    
                    //update unread count in active chats list
                    if([unread count])
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                            @"contact": [[DataLayer sharedInstance] contactForUsername:buddyName forAccount:account.accountNo]
                        }];
                }
                
                if(deleteMessage)
                {
                    [[DataLayer sharedInstance] deleteMessageHistory:historyId];
                    
                    DDLogInfo(@"Sending out kMonalDeletedMessageNotice notification for historyId %@", historyId);
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalDeletedMessageNotice object:account userInfo:@{
                        @"message": message,
                        @"historyId": historyId,
                        @"contact": [[DataLayer sharedInstance] contactForUsername:message.buddyName forAccount:account.accountNo],
                    }];
                }
                else
                {
                    [[DataLayer sharedInstance] addActiveBuddies:buddyName forAccount:account.accountNo];
                    
                    DDLogInfo(@"Sending out kMonalNewMessageNotice notification for historyId %@", historyId);
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalNewMessageNotice object:account userInfo:@{
                        @"message": message,
                        @"historyId": historyId,
                        @"showAlert": @(showAlert),
                        @"contact": [[DataLayer sharedInstance] contactForUsername:message.buddyName forAccount:account.accountNo],
                    }];
                    
                    //try to automatically determine content type of filetransfers
                    if(messageType == kMessageTypeFiletransfer && [[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"])
                        [MLFiletransfer checkMimeTypeAndSizeForHistoryID:historyId];
                }
            }
        }
    }
    
    //handle message receipts
    if(
        ([messageNode check:@"{urn:xmpp:receipts}received@id"] || [messageNode check:@"{urn:xmpp:chat-markers:0}received@id"]) &&
        [messageNode.toUser isEqualToString:account.connectionProperties.identity.jid]
    )
    {
        NSString* msgId;
        if([messageNode check:@"{urn:xmpp:receipts}received@id"])
            msgId = [messageNode findFirst:@"{urn:xmpp:receipts}received@id"];
        else
            msgId = [messageNode findFirst:@"{urn:xmpp:chat-markers:0}received@id"];        //fallback only
        if(msgId)
        {
            //save in DB
            [[DataLayer sharedInstance] setMessageId:msgId received:YES];
            
            //Post notice
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageReceivedNotice object:self userInfo:@{kMessageId:msgId}];
        }
    }
    
    //handle chat-markers in groupchats slightly different
    if([messageNode check:@"{urn:xmpp:chat-markers:0}displayed@id"] && ownNick != nil)
    {
        MLContact* groupchatContact = [[DataLayer sharedInstance] contactForUsername:buddyName forAccount:account.accountNo];
        //ignore unknown groupchats or channel-type mucs or stanzas from the groupchat itself (e.g. not from a participant having a full jid)
        if(groupchatContact.isGroup && [groupchatContact.mucType isEqualToString:@"group"] && messageNode.fromResource)
        {
            //incoming chat markers from own account (muc echo, muc "carbon")
            //WARNING: kMonalMessageDisplayedNotice goes to chatViewController, kMonalDisplayedMessageNotice goes to MLNotificationManager and activeChatsViewController/chatViewController
            //e.g.: kMonalMessageDisplayedNotice means "remote party read our message" and kMonalDisplayedMessageNotice means "we read a message"
            if(!inbound)
            {
                DDLogInfo(@"Got OWN muc display marker in %@ for message id: %@", buddyName, [messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"]);
                NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:buddyName andAccount:account.accountNo tillStanzaId:[messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"] wasOutgoing:NO];
                DDLogDebug(@"Marked as read: %@", unread);
                
                //remove notifications of all remotely read messages (indicated by sending a display marker)
                for(MLMessage* msg in unread)
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessageNotice object:account userInfo:@{@"message":msg}];
                
                //update unread count in active chats list
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                    @"contact": groupchatContact
                }];
            }
            //incoming chat markers from participant
            //this will mark groupchat messages as read as soon as one of the participants sends a displayed chat-marker
            //WARNING: kMonalMessageDisplayedNotice goes to chatViewController, kMonalDisplayedMessageNotice goes to MLNotificationManager and activeChatsViewController/chatViewController
            //e.g.: kMonalMessageDisplayedNotice means "remote party read our message" and kMonalDisplayedMessageNotice means "we read a message"
            else
            {
                DDLogInfo(@"Got remote muc display marker from %@ for message id: %@", messageNode.from, [messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"]);
                NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:buddyName andAccount:account.accountNo tillStanzaId:[messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"] wasOutgoing:YES];
                DDLogDebug(@"Marked as displayed: %@", unread);
                for(MLMessage* msg in unread)
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageDisplayedNotice object:account userInfo:@{@"message":msg, kMessageId:msg.messageId}];
            }
        }
    }
    else if([messageNode check:@"{urn:xmpp:chat-markers:0}displayed@id"])
    {
        //incoming chat markers from contact
        //WARNING: kMonalMessageDisplayedNotice goes to chatViewController, kMonalDisplayedMessageNotice goes to MLNotificationManager and activeChatsViewController/chatViewController
        //e.g.: kMonalMessageDisplayedNotice means "remote party read our message" and kMonalDisplayedMessageNotice means "we read a message"
        if(inbound)
        {
            DDLogInfo(@"Got remote display marker from %@ for message id: %@", messageNode.fromUser, [messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"]);
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:messageNode.fromUser andAccount:account.accountNo tillStanzaId:[messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"] wasOutgoing:YES];
            DDLogDebug(@"Marked as displayed: %@", unread);
            for(MLMessage* msg in unread)
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageDisplayedNotice object:account userInfo:@{@"message":msg, kMessageId:msg.messageId}];
        }
        //incoming chat markers from own account (carbon copy)
        //WARNING: kMonalMessageDisplayedNotice goes to chatViewController, kMonalDisplayedMessageNotice goes to MLNotificationManager and activeChatsViewController/chatViewController
        //e.g.: kMonalMessageDisplayedNotice means "remote party read our message" and kMonalDisplayedMessageNotice means "we read a message"
        else
        {
            DDLogInfo(@"Got OWN display marker to %@ for message id: %@", messageNode.toUser, [messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"]);
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:messageNode.toUser andAccount:account.accountNo tillStanzaId:[messageNode findFirst:@"{urn:xmpp:chat-markers:0}displayed@id"] wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //remove notifications of all remotely read messages (indicated by sending a display marker)
            for(MLMessage* msg in unread)
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessageNotice object:account userInfo:@{@"message":msg}];
            
            //update unread count in active chats list
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": [[DataLayer sharedInstance] contactForUsername:messageNode.toUser forAccount:account.accountNo]
            }];
        }
    }
    
    //handle typing notifications but ignore them in appex or for mam fetches (*any* mam fetches are ignored here, chatstates should *never* be in a mam archive!)
    if(![HelperTools isAppExtension] && ![outerMessageNode check:@"{urn:xmpp:mam:2}result"])
    {
        //only use "is typing" messages when not older than 2 minutes (always allow "not typing" messages)
        if(
            [messageNode check:@"{http://jabber.org/protocol/chatstates}*"] &&
            [[DataLayer sharedInstance] checkCap:@"http://jabber.org/protocol/chatstates" forUser:messageNode.fromUser andAccountNo:account.accountNo]
        )
        {
            //deduce state
            BOOL composing = NO;
            if([@"active" isEqualToString:[messageNode findFirst:@"{http://jabber.org/protocol/chatstates}*$"]])
                composing = NO;
            else if([@"composing" isEqualToString:[messageNode findFirst:@"{http://jabber.org/protocol/chatstates}*$"]])
                composing = YES;
            else if([@"paused" isEqualToString:[messageNode findFirst:@"{http://jabber.org/protocol/chatstates}*$"]])
                composing = NO;
            else if([@"inactive" isEqualToString:[messageNode findFirst:@"{http://jabber.org/protocol/chatstates}*$"]])
                composing = NO;
            
            //handle state
            if(
                (
                    composing &&
                    (
                        ![messageNode check:@"{urn:xmpp:delay}delay@stamp"] ||
                        [[NSDate date] timeIntervalSinceDate:[messageNode findFirst:@"{urn:xmpp:delay}delay@stamp|datetime"]] < 120
                    )
                ) ||
                !composing
            )
            {
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                    @"jid": messageNode.fromUser,
                    @"accountNo": account.accountNo,
                    @"isTyping": composing ? @YES : @NO
                }];
                //send "not typing" notifications (kMonalLastInteractionUpdatedNotice) 60 seconds after the last isTyping was received
                @synchronized(_typingNotifications) {
                    //copy needed values into local variables to not retain self by our timer block
                    NSString* jid = messageNode.fromUser;
                    //abort old timer on new isTyping or isNotTyping message
                    if(_typingNotifications[messageNode.fromUser])
                        ((monal_void_block_t) _typingNotifications[messageNode.fromUser])();
                    //start a new timer for every isTyping message
                    if(composing)
                    {
                        _typingNotifications[messageNode.fromUser] = createTimer(60, (^{
                            [[MLNotificationQueue currentQueue] postNotificationName:kMonalLastInteractionUpdatedNotice object:[[NSDate date] initWithTimeIntervalSince1970:0] userInfo:@{
                                @"jid": jid,
                                @"accountNo": account.accountNo,
                                @"isTyping": @NO
                            }];
                        }));
                    }
                }
            }
        }
    }
    
    return message;
}

@end
