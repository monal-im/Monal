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
    if([messageNode.type isEqualToString:kMessageErrorType])
    {
        DDLogError(@"Error type message received");
        return;
    }
    
    if(messageNode.mucInvite)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalReceivedMucInviteNotice object:nil  userInfo:@{@"from":messageNode.from}];
    }
    NSString *recipient=messageNode.to;
    
    if(!recipient)
    {
        recipient= self.jid;
    }
    
  
    NSString *decrypted =[self decryptMessage:messageNode];
    
    if(messageNode.hasBody || messageNode.subject|| decrypted)
    {
        NSString *ownNick;
     
        if(messageNode.type==kMessageGroupChatType)
        {
            ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:messageNode.from forAccount:self.accountNo];
        }
        
        if ([messageNode.type isEqualToString:kMessageGroupChatType]
            && [messageNode.actualFrom isEqualToString:ownNick])
        {
            DDLogDebug(@"Dropping muc echo");
            return;
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
            
            NSString *messageType=nil;
            BOOL encrypted=NO;
            NSString *body=messageNode.messageText;
            
            if(messageNode.oobURL)
            {
                messageType=kMessageTypeImage;
                body=messageNode.oobURL;
            }
            
            if(decrypted) {
                body=decrypted;
                encrypted=YES;
            }
            
         
            if(!body  && messageNode.subject)
            {
                //TODO when we want o handle subject changes
                //                                body =[NSString stringWithFormat:@"%@ changed the subject to: %@", messageNode.actualFrom, messageNode.subject];
                messageType=kMessageTypeStatus;
                
                [[DataLayer sharedInstance] updateMucSubject:messageNode.subject forAccount:self.accountNo andRoom:messageNode.from withCompletion:nil];
                body=messageNode.subject;
                
                if(self.postPersistAction) {
                    self.postPersistAction(YES, encrypted, showAlert, body, messageType);
                }
                return;
            }
            
            NSString *messageId=messageNode.idval;
            if(messageId.length==0)
            {
                DDLogError(@"Empty ID using guid");
                messageId=[[NSUUID UUID] UUIDString];
            }
            
            [[DataLayer sharedInstance] addMessageFrom:messageNode.from
                                                    to:recipient
                                            forAccount:self->_accountNo
                                              withBody:[body copy]
                                          actuallyfrom:messageNode.actualFrom
                                             delivered:YES
                                                unread:unread
                                             messageId:messageId
                                       serverMessageId:messageNode.stanzaId
                                           messageType:messageType
                                       andOverrideDate:messageNode.delayTimeStamp
                                             encrypted:encrypted
                                        withCompletion:^(BOOL success, NSString *newMessageType) {
                                            if(self.postPersistAction) {
                                                self.postPersistAction(success, encrypted, showAlert, body, newMessageType);
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
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageReceivedNotice object:self userInfo:@{@"MessageID":messageNode.receivedID}];
    }
}
    
    
-(NSString *) decryptMessage:(ParseMessage *) messageNode {
#ifndef DISABLE_OMEMO
    if(messageNode.encryptedPayload)
    {
        SignalAddress *address = [[SignalAddress alloc] initWithName:messageNode.from deviceId:(uint32_t)messageNode.sid.intValue];
        if(!self.signalContext) {
            DDLogError(@"Missing signal context");
            return @"Error decrypting message";
        }
        
        __block NSDictionary *messageKey;
        [messageNode.signalKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *currentKey = (NSDictionary *) obj;
            NSString* rid=[currentKey objectForKey:@"rid"];
            if(rid.intValue==self.monalSignalStore.deviceid)
            {
                messageKey=currentKey;
                *stop=YES;
            }
            
        }];
        
        if(!messageKey)
        {
            DDLogError(@"Message was not encrypted for this device");
            return @"Message was not encrypted for this device";
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
                if(self.signalAction) self.signalAction();
            }
            
            if(!decryptedKey){
                DDLogError(@"There was an error decrypting this message.");
                return @"There was an error decrypting this message.";
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
                    if(!decData) {
                        DDLogError(@"could not decrypt message");
                    }
                    else  {
                        DDLogInfo(@"Decrypted message passing bask string.");
                    }
                    NSString *messageString= [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
                    return messageString;
                    
                } else  {
                    DDLogError(@"Could not get key");
                    return @"Could not decrypt message";
                }
            }
        }
    } else {
        return nil;
    }
#else
    return nil;
#endif
}

@end
