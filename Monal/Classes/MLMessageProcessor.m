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
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) xmpp* account;
@property (nonatomic, strong) MLXMPPConnection *connection;
@property (nonatomic, strong) MLOMEMO* omemo;
@end

static NSMutableDictionary* _typingNotifications;

@implementation MLMessageProcessor

+(void) initialize
{
    _typingNotifications = [[NSMutableDictionary alloc] init];
}

-(MLMessageProcessor *) initWithAccount:(xmpp*) account jid:(NSString *) jid connection:(MLXMPPConnection *) connection omemo:(MLOMEMO*) omemo {
    self.account = account;
    self.jid = jid;
    self.connection = connection;
    self.omemo = omemo;
    return self;
}


-(void) processMessage:(ParseMessage *) messageNode
{
    if([messageNode.type isEqualToString:kMessageErrorType])
    {
        DDLogError(@"Error type message received");
        
        if(!messageNode.idval.length)
        {
            DDLogError(@"Ignoring error messages having an empty ID");
            return;
        }
        
        //update db
        [[DataLayer sharedInstance] setMessageId:messageNode.idval errorType:messageNode.errorType ? messageNode.errorType : @""
                                     errorReason:messageNode.errorReason ? messageNode.errorReason : @""];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageErrorNotice object:nil  userInfo:@{@"MessageID":messageNode.idval,@"errorType":messageNode.errorType?messageNode.errorType:@"",@"errorReason":messageNode.errorReason?messageNode.errorReason:@""
        }];

        return;
    }
    
    if(messageNode.mucInvite)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalReceivedMucInviteNotice object:nil  userInfo:@{@"from":messageNode.from}];
    }
    NSString* recipient = messageNode.to;
    
    if(!recipient)
    {
        recipient = self.jid;
    }
    
    NSString* decrypted;
    if(messageNode.encryptedPayload) {
        decrypted = [self.omemo decryptMessage:messageNode];
    }
    
    if(messageNode.hasBody || messageNode.subject || decrypted)
    {
        NSString* ownNick;
     
        //processed messages already have server name
        if([messageNode.type isEqualToString:kMessageGroupChatType])
            ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:messageNode.from andServer:@"" forAccount:self.account.accountNo];
        
        if (ownNick!=nil && [messageNode.actualFrom isEqualToString:ownNick])
        {
            DDLogDebug(@"Dropping muc echo");
            return;
        }
        else
        {
            BOOL unread = YES;
            BOOL showAlert = YES;
            
            //if mam but catchup we do want an alert...
            if([messageNode.from isEqualToString:self.jid] || (messageNode.mamResult && ![messageNode.mamQueryId hasPrefix:@"MLcatchup:"]))
            {
                DDLogVerbose(@"Setting showAlert to NO");
                showAlert = NO;
                unread = NO;
            }
          
            NSString* messageType = nil;
            BOOL encrypted = NO;
            NSString* body = messageNode.messageText;
            
            if(messageNode.oobURL)
            {
                messageType = kMessageTypeImage;
                body = messageNode.oobURL;
            }
            
            if(decrypted)
            {
                body = decrypted;
                encrypted = YES;
            }
            
            if(!body && messageNode.subject)
            {
                messageType=kMessageTypeStatus;
                
                NSString* currentSubject = [[DataLayer sharedInstance] mucSubjectforAccount:self.account.accountNo andRoom:messageNode.from];
                if(![messageNode.subject isEqualToString:currentSubject])
                {
                    [[DataLayer sharedInstance] updateMucSubject:messageNode.subject forAccount:self.account.accountNo andRoom:messageNode.from];
                    if(self.postPersistAction)
                        self.postPersistAction(YES, encrypted, showAlert, messageNode.subject, messageType);
                }
                return;
            }
            
            NSString *messageId = messageNode.idval;
            if(!messageId.length)
            {
                DDLogError(@"Empty ID using random UUID");
                messageId = [[NSUUID UUID] UUIDString];
            }
            
            //history messages have to be collected mam-page wise and reordered before inserted into db
            //because mam always sorts the messages in a page by timestamp in ascending order
            //we don't want to call postPersistAction, too, beause we don't want to display push notifications for old messages
            if(messageNode.mamResult && [messageNode.mamQueryId hasPrefix:@"MLhistory:"])
                [self.account addMessageToMamPageArray:messageNode withBody:body andEncrypted:encrypted andShowAlert:showAlert andMessageType:messageType];
            else
            {
                [[DataLayer sharedInstance] addMessageFrom:messageNode.from
                                                        to:recipient
                                                forAccount:self.account.accountNo
                                                  withBody:[body copy]
                                              actuallyfrom:messageNode.actualFrom
                                                      sent:YES
                                                    unread:unread
                                                 messageId:messageId
                                           serverMessageId:messageNode.stanzaId
                                               messageType:messageType
                                           andOverrideDate:messageNode.delayTimeStamp
                                                 encrypted:encrypted
                                                 backwards:NO
                                            withCompletion:^(BOOL success, NSString* newMessageType) {
                    if(self.postPersistAction) {
                        self.postPersistAction(success, encrypted, showAlert, body, newMessageType);
                    }
                }];
            }
        }
    }
    
    if(messageNode.avatarData)
    {
        [[MLImageManager sharedInstance] setIconForContact:messageNode.actualFrom andAccount:self.account.accountNo WithData:messageNode.avatarData];
    }
    
    if(messageNode.receivedID)
    {
        //save in DB
        [[DataLayer sharedInstance] setMessageId:messageNode.receivedID received:YES];
        //Post notice
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageReceivedNotice object:self userInfo:@{@"MessageID":messageNode.receivedID}];
    }
    
    if([messageNode.type isEqualToString:kMessageHeadlineType])
    {
        [self processHeadline:messageNode];
    }
    
    //ignore typing notifications when in appex
    if(![HelperTools isAppExtension])
    {
        //only use "is typing" messages when not older than 2 minutes (always allow "not typing" messages)
        if([[DataLayer sharedInstance] checkCap:@"http://jabber.org/protocol/chatstates" forUser:messageNode.user andAccountNo:self.account.accountNo] &&
            ((messageNode.composing && (!messageNode.delayTimeStamp || [[NSDate date] timeIntervalSinceDate:messageNode.delayTimeStamp] < 120)) ||
            messageNode.notComposing)
        )
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                @"jid": messageNode.user,
                @"accountNo": self.account.accountNo,
                @"isTyping": messageNode.composing ? @YES : @NO
            }];
            //send "not typing" notifications (kMonalLastInteractionUpdatedNotice) 60 seconds after the last isTyping was received
            @synchronized(_typingNotifications) {
                //copy needed values into local variables to not retain self by our timer block
                NSString* account = self.account.accountNo;
                NSString* jid = messageNode.user;
                //abort old timer on new isTyping or isNotTyping message
                if(_typingNotifications[messageNode.user])
                    ((monal_void_block_t) _typingNotifications[messageNode.user])();
                //start a new timer for every isTyping message
                if(messageNode.composing)
                {
                    _typingNotifications[messageNode.user] = [HelperTools startTimer:60 withHandler:^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:[[NSDate date] initWithTimeIntervalSince1970:0] userInfo:@{
                            @"jid": jid,
                            @"accountNo": account,
                            @"isTyping": @NO
                        }];
                    }];
                }
            }
        }
    }
}
    
-(void) processHeadline:(ParseMessage *) messageNode
{
     if(messageNode.devices)
     {
         [self.omemo processOMEMODevices:messageNode.devices from:messageNode.from];
     }
}

@end
