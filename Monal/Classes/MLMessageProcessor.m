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
#import "MLOMEMO.h"


@interface MLMessageProcessor ()

@end

static NSMutableDictionary* _typingNotifications;

@implementation MLMessageProcessor

+(void) initialize
{
    _typingNotifications = [[NSMutableDictionary alloc] init];
}

+(void) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account
{
    if([messageNode check:@"/<type=error>"])
    {
        DDLogError(@"Error type message received");
        
        if(![messageNode check:@"/@id"])
        {
            DDLogError(@"Ignoring error messages having an empty ID");
            return;
        }
        
        //update db
        [[DataLayer sharedInstance]
            setMessageId:[messageNode findFirst:@"/@id"]
            errorType:[messageNode check:@"error@type"] ? [messageNode findFirst:@"error@type"] : @""
            errorReason:[messageNode check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"] ? [messageNode findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"] : @""
        ];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageErrorNotice object:nil userInfo:@{
            @"MessageID": [messageNode findFirst:@"/@id"],
            @"errorType": [messageNode check:@"error@type"] ? [messageNode findFirst:@"error@type"] : @"",
            @"errorReason": [messageNode check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"] ? [messageNode findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"] : @""
        }];

        return;
    }
    
    
    NSString* stanzaid = [outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@id"];
    //check stnaza-id @by according to the rules outlined in XEP-0359
    if(!stanzaid && [account.connectionProperties.identity.jid isEqualToString:[messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@by"]])
        stanzaid = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
        
    if([messageNode check:@"{http://jabber.org/protocol/muc#user}x/invite"])
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalReceivedMucInviteNotice object:nil userInfo:@{@"from": messageNode.from}];

    NSString* recipient = messageNode.to;
    if(!recipient)
        recipient = account.connectionProperties.identity.jid;
    
    NSString* decrypted;
    if([messageNode check:@"/{jabber:client}message/{eu.siacs.conversations.axolotl}encrypted/payload"])
        decrypted = [account.omemo decryptMessage:messageNode];
    
    if([messageNode check:@"body"] || [messageNode check:@"/<type=headline>/subject#"] || decrypted)
    {
        NSString* ownNick;
        NSString* actualFrom = messageNode.fromUser;
        
        //processed messages already have server name
        if([messageNode check:@"/<type=groupchat>"])
        {
            ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:messageNode.fromUser andServer:@"" forAccount:account.accountNo];
            actualFrom = messageNode.fromResource;
        }
        if(ownNick && actualFrom && [actualFrom isEqualToString:ownNick])
        {
            DDLogDebug(@"Dropping muc echo");
            return;
        }
        else
        {
            BOOL unread = YES;
            BOOL showAlert = YES;
            
            //if incoming or mam catchup we do want an alert, otherwise we don't
            if(
                [messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid] ||
                (
                    [outerMessageNode check:@"{urn:xmpp:mam:2}result"] &&
                    ![[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLcatchup:"]
                )
            )
            {
                DDLogVerbose(@"Setting showAlert to NO");
                showAlert = NO;
                unread = NO;
            }
          
            NSString* messageType = nil;
            BOOL encrypted = NO;
            NSString* body = [messageNode findFirst:@"body#"];
            
            if(body && [body isEqualToString:[messageNode findFirst:@"{jabber:x:oob}x/url#"]])
                messageType = kMessageTypeImage;
            
            if(decrypted)
            {
                body = decrypted;
                encrypted = YES;
            }
            
            if(!body && [messageNode check:@"/<type=headline>/subject#"])
            {
                messageType = kMessageTypeStatus;
                
                NSString* currentSubject = [[DataLayer sharedInstance] mucSubjectforAccount:account.accountNo andRoom:messageNode.fromUser];
                if(![[messageNode findFirst:@"/<type=headline>/subject#"] isEqualToString:currentSubject])
                {
                    [[DataLayer sharedInstance] updateMucSubject:[messageNode findFirst:@"/<type=headline>/subject#"] forAccount:account.accountNo andRoom:messageNode.fromUser];
                    [self postPersistActionForAccount:account andMessage:messageNode andOuterMessage:outerMessageNode andSuccess:YES andEncrypted:encrypted andShowAlert:showAlert andBody:[messageNode findFirst:@"/<type=headline>/subject#"] andMessageType:messageType andActualFrom:actualFrom];
                }
                return;
            }
            
            NSString* messageId = [messageNode findFirst:@"/@id"];
            if(!messageId.length)
            {
                DDLogError(@"Empty ID using random UUID");
                messageId = [[NSUUID UUID] UUIDString];
            }
            
            //history messages have to be collected mam-page wise and reordered before inserted into db
            //because mam always sorts the messages in a page by timestamp in ascending order
            //we don't want to call postPersistAction, too, beause we don't want to display push notifications for old messages
            if([outerMessageNode check:@"{urn:xmpp:mam:2}result"] && [[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLhistory:"])
                [account addMessageToMamPageArray:messageNode forOuterMessageNode:outerMessageNode withBody:body andEncrypted:encrypted andShowAlert:showAlert andMessageType:messageType];
            else
            {
                [[DataLayer sharedInstance] addMessageFrom:messageNode.fromUser
                                                        to:recipient
                                                forAccount:account.accountNo
                                                  withBody:[body copy]
                                              actuallyfrom:actualFrom
                                                      sent:YES
                                                    unread:unread
                                                 messageId:messageId
                                           serverMessageId:stanzaid
                                               messageType:messageType
                                           andOverrideDate:[messageNode findFirst:@"{urn:xmpp:delay}delay@stamp|datetime"]
                                                 encrypted:encrypted
                                                 backwards:NO
                                            withCompletion:^(BOOL success, NSString* newMessageType) {
                    [self postPersistActionForAccount:account andMessage:messageNode andOuterMessage:outerMessageNode andSuccess:success andEncrypted:encrypted andShowAlert:showAlert andBody:body andMessageType:newMessageType andActualFrom:actualFrom];
                }];
            }
        }
    }
    
    /*TODO: avatar data must be handled via pubsub
    if(messageNode.avatarData)
    {
        [[MLImageManager sharedInstance] setIconForContact:messageNode.actualFrom andAccount:account.accountNo WithData:messageNode.avatarData];
    }
    */
    
    if([messageNode check:@"{urn:xmpp:receipts}received@id"])
    {
        //save in DB
        [[DataLayer sharedInstance] setMessageId:[messageNode findFirst:@"{urn:xmpp:receipts}received@id"] received:YES];
        //Post notice
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageReceivedNotice object:self userInfo:@{@"MessageID": [messageNode findFirst:@"{urn:xmpp:receipts}received@id"]}];
    }

    if([messageNode check:@"/{jabber:client}message<type=headline>/{http://jabber.org/protocol/pubsub#event}event/items<node=eu\\.siacs\\.conversations\\.axolotl\\.devicelist>/item/{eu.siacs.conversations.axolotl}list"]) {
        NSArray<NSNumber*>* deviceIds = [messageNode find:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/items<node=eu\\.siacs\\.conversations\\.axolotl\\.devicelist>/item/{eu.siacs.conversations.axolotl}list/device@id|int"];
        NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];
        [account.omemo processOMEMODevices:deviceSet from:messageNode.fromUser];
    }

    //ignore typing notifications when in appex
    if(![HelperTools isAppExtension])
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
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
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
                        _typingNotifications[messageNode.fromUser] = [HelperTools startTimer:60 withHandler:^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:[[NSDate date] initWithTimeIntervalSince1970:0] userInfo:@{
                                @"jid": jid,
                                @"accountNo": account.accountNo,
                                @"isTyping": @NO
                            }];
                        }];
                    }
                }
            }
        }
    }
}

+(void) postPersistActionForAccount:(xmpp*) account andMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode andSuccess:(BOOL) success andEncrypted:(BOOL) encrypted andShowAlert:(BOOL) showAlert andBody:(NSString*) body andMessageType:(NSString*) newMessageType andActualFrom:(NSString*) actualFrom
{
    if(success)
    {
        if([messageNode check:@"{urn:xmpp:receipts}request"] && ![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            XMPPMessage* receiptNode = [[XMPPMessage alloc] init];
            //the message type is needed so that the store hint is accepted by the server
            [receiptNode.attributes setObject:[messageNode findFirst:@"/@type"] forKey:@"type"];
            [receiptNode.attributes setObject:messageNode.fromUser forKey:@"to"];
            [receiptNode setXmppId:[[NSUUID UUID] UUIDString]];
            [receiptNode setReceipt:[messageNode findFirst:@"/@id"]];
            [receiptNode setStoreHint];
            [account send:receiptNode];
        }

        void(^notify)(BOOL) = ^(BOOL success) {
            if(messageNode.fromUser)
            {
                MLMessage* message = [account parseMessageToMLMessage:messageNode withBody:body andEncrypted:encrypted andShowAlert:showAlert andMessageType:newMessageType andActualFrom:actualFrom];

                DDLogInfo(@"sending out kMonalNewMessageNotice notification");
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:account userInfo:@{@"message":message}];
            }
            else
                DDLogInfo(@"no messageNode.from, not notifying");
        };

        if(![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
            notify([[DataLayer sharedInstance] addActiveBuddies:messageNode.fromUser forAccount:account.accountNo]);
        else
            notify([[DataLayer sharedInstance] addActiveBuddies:messageNode.to forAccount:account.accountNo]);
    }
    else
        DDLogError(@"error adding message");
}

@end
