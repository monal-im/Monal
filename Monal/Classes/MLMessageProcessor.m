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
#import "EncodingTools.h"
#import "AESGcm.h"
#import "MLConstants.h"
#import "MLImageManager.h"


@interface MLMessageProcessor ()
@property (nonatomic, strong) SignalContext *signalContext;
@property (nonatomic, strong) MLSignalStore *monalSignalStore;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *accountNo;

@end


@implementation MLMessageProcessor

-(MLMessageProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore {
    self=[super init];
    self.accountNo = accountNo;
    self.jid= jid;
    self.signalContext=signalContext;
    self.monalSignalStore= monalSignalStore;
    return self;
}


-(void) processMessage:(ParseMessage *) messageNode
{
    
    if(messageNode.mucInvite)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalReceivedMucInviteNotice object:nil  userInfo:@{@"from":messageNode.from}];
        
        NSString *recipient=messageNode.to;
        
        if(!recipient)
        {
            recipient= self.jid;
        }
        
        if(messageNode.subject && messageNode.type==kMessageGroupChatType)
        {
            [[DataLayer sharedInstance] updateMucSubject:messageNode.subject forAccount:self.accountNo andRoom:messageNode.from withCompletion:nil];
            
        }
        NSString *decrypted;
        
#ifndef DISABLE_OMEMO
        if(messageNode.encryptedPayload)
        {
            SignalAddress *address = [[SignalAddress alloc] initWithName:messageNode.from deviceId:(uint32_t)messageNode.sid.intValue];
            if(!self.signalContext) return;
            
            
            __block NSDictionary *messageKey;
            [messageNode.signalKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary *currentKey = (NSDictionary *) obj;
                NSString* rid=[currentKey objectForKey:@"rid"];
                if(rid.integerValue==self.monalSignalStore.deviceid)
                {
                    messageKey=currentKey;
                    *stop=YES;
                }
                
            }];
            
            if(!messageKey)
            {
                decrypted=@"Message was not encrypted for this device";
            }
            else {
                SignalSessionCipher *cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
                SignalCiphertextType messagetype;
                
                if([[messageKey objectForKey:@"prekey"] isEqualToString:@"1"])
                {
                    messagetype=SignalCiphertextTypePreKeyMessage;
                } else  {
                    messagetype= SignalCiphertextTypeMessage;
                }
                
                NSData *decoded= [EncodingTools dataWithBase64EncodedString:[messageKey objectForKey:@"key"]];
                
                SignalCiphertext *ciphertext = [[SignalCiphertext alloc] initWithData:decoded type:messagetype];
                NSError *error;
                NSData *decryptedKey=  [cipher decryptCiphertext:ciphertext error:&error];
                
                NSData *key;
                NSData *auth;
                
                if(messagetype==SignalCiphertextTypePreKeyMessage)
                {
                    [self manageMyKeys];
                }
                
                if(!decryptedKey){
                    decrypted =@"There was an error decrypting this message.";
                }
                else  {
                    
                    if(decryptedKey.length==16*2)
                    {
                        key=[decryptedKey subdataWithRange:NSMakeRange(0,16)];
                        auth=[decryptedKey subdataWithRange:NSMakeRange(16,16)];
                    }
                    else {
                        key=decryptedKey;
                    }
                    
                    if(key){
                        NSData *iv = [EncodingTools dataWithBase64EncodedString:messageNode.iv];
                        NSData *decodedPayload = [EncodingTools dataWithBase64EncodedString:messageNode.encryptedPayload];
                        
                        NSData *decData = [AESGcm decrypt:decodedPayload withKey:key andIv:iv withAuth:auth];
                        decrypted= [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
                        
                    }
                }
            }
        }
#endif
        
        if(messageNode.hasBody || messageNode.subject|| decrypted)
        {
            NSString *ownNick;
            //TODO if muc find own nick to see if echo
            if(messageNode.type==kMessageGroupChatType)
            {
                ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:messageNode.from forAccount:self.accountNo];
            }
            
            if ([messageNode.type isEqualToString:kMessageGroupChatType]
                && [messageNode.actualFrom isEqualToString:ownNick])
            {
                //this is just a muc echo
            }
            else
            {
                NSString *jidWithoutResource =self.jid;
                
                BOOL unread=YES;
                BOOL showAlert=YES;
                if( [messageNode.from isEqualToString:jidWithoutResource] || messageNode.mamResult ) {
                    unread=NO;
                    showAlert=NO;
                }
                
                NSString *body=messageNode.messageText;
                if(decrypted) body=decrypted;
                
                NSString *messageType=nil;
                if(!body  && messageNode.subject)
                {
                    //TODO when we want o handle subject changes
                    //                                body =[NSString stringWithFormat:@"%@ changed the subject to: %@", messageNode.actualFrom, messageNode.subject];
                    messageType=kMessageTypeStatus;
                    return;
                }
                
                if(messageNode.oobURL)
                {
                    messageType=kMessageTypeImage;
                    body=messageNode.oobURL;
                }
                if(!body) body=@"";
                
                BOOL encrypted=NO;
                if(decrypted) encrypted=YES;
                
                NSString *messageId=messageNode.idval;
                if(messageId.length==0)
                {
                    NSLog(@"Empty ID using guid");
                    messageId=[[NSUUID UUID] UUIDString];
                }
                
                [[DataLayer sharedInstance] addMessageFrom:messageNode.from
                                                        to:recipient
                                                forAccount:self->_accountNo
                                                  withBody:body
                                              actuallyfrom:messageNode.actualFrom
                                                 delivered:YES
                                                    unread:unread
                                                 messageId:messageId
                                           serverMessageId:messageNode.stanzaId
                                               messageType:messageType
                                           andOverrideDate:messageNode.delayTimeStamp
                                                 encrypted:encrypted
                                            withCompletion:^(BOOL success, NSString *newMessageType) {
                                                if(success)
                                                {
                                                    if(messageNode.requestReceipt
                                                       && !messageNode.mamResult
                                                       && ![messageNode.from isEqualToString:
                                                            self.jid]
                                                       )
                                                    {
                                                        XMPPMessage *receiptNode = [[XMPPMessage alloc] init];
                                                        [receiptNode.attributes setObject:messageNode.from forKey:@"to"];
                                                        [receiptNode setXmppId:[[NSUUID UUID] UUIDString]];
                                                        [receiptNode setReceipt:messageNode.idval];
                                                        [self send:receiptNode];
                                                    }
                                                    
                                                    [self.networkQueue addOperationWithBlock:^{
                                                        
                                                        if(![messageNode.from isEqualToString:
                                                             self.fulluser]) {
                                                            [[DataLayer sharedInstance] addActiveBuddies:messageNode.from forAccount:self->_accountNo withCompletion:nil];
                                                        } else  {
                                                            [[DataLayer sharedInstance] addActiveBuddies:messageNode.to forAccount:self->_accountNo withCompletion:nil];
                                                        }
                                                        
                                                        
                                                        if(messageNode.from  ) {
                                                            NSString* actuallyFrom= messageNode.actualFrom;
                                                            if(!actuallyFrom) actuallyFrom=messageNode.from;
                                                            
                                                            NSString* messageText=messageNode.messageText;
                                                            if(!messageText) messageText=@"";
                                                            
                                                            BOOL shouldRefresh = NO;
                                                            if(messageNode.delayTimeStamp)  shouldRefresh =YES;
                                                            
                                                            NSArray *jidParts= [self.jid componentsSeparatedByString:@"/"];
                                                            
                                                            NSString *recipient;
                                                            if([jidParts count]>1) {
                                                                recipient= jidParts[0];
                                                            }
                                                            if(!recipient) recipient= self->_fulluser;
                                                            
                                                            
                                                            NSDictionary* userDic=@{@"from":messageNode.from,
                                                                                    @"actuallyfrom":actuallyFrom,
                                                                                    @"messageText":body,
                                                                                    @"to":messageNode.to?messageNode.to:recipient,
                                                                                    @"messageid":messageNode.idval?messageNode.idval:@"",
                                                                                    @"accountNo":self->_accountNo,
                                                                                    @"showAlert":[NSNumber numberWithBool:showAlert],
                                                                                    @"shouldRefresh":[NSNumber numberWithBool:shouldRefresh],
                                                                                    @"messageType":newMessageType?newMessageType:kMessageTypeText,
                                                                                    @"muc_subject":messageNode.subject?messageNode.subject:@"",
                                                                                    @"encrypted":[NSNumber numberWithBool:encrypted],
                                                                                    @"delayTimeStamp":messageNode.delayTimeStamp?messageNode.delayTimeStamp:@""
                                                                                    };
                                                            
                                                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:self userInfo:userDic];
                                                        }
                                                    }];
                                                }
                                                else {
                                                    DDLogVerbose(@"error adding message");
                                                }
                                                
                                            }];
                
            }
        }
        
        if(messageNode.avatarData)
        {
            
            [[MLImageManager sharedInstance] setIconForContact:messageNode.actualFrom andAccount:self->_accountNo WithData:messageNode.avatarData];
            
        }
        
        if(messageNode.receivedID)
        {
            //save in DB
            [[DataLayer sharedInstance] setMessageId:messageNode.receivedID received:YES];
            
            //Post notice
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageReceivedNotice object:self userInfo:@{kMessageId:messageNode.receivedID}];
            
        }
        
        
        
    }
    
    @end
