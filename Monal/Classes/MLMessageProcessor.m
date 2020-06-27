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
#import "XMPPIQ.h"


@interface MLMessageProcessor ()
@property (atomic, strong) SignalContext *signalContext;
@property (atomic, strong) MLSignalStore *monalSignalStore;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) MLXMPPConnection *connection;
@end


@implementation MLMessageProcessor

-(MLMessageProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid connection:(MLXMPPConnection *) connection   signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore {
    self=[super init];
    self.accountNo = accountNo;
    self.jid= jid;
    self.signalContext=signalContext;
    self.monalSignalStore= monalSignalStore;
    self.connection= connection;
    return self;
}

-(MLMessageProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid connection:(MLXMPPConnection *) connection {
    self=[super init];
    self.accountNo = accountNo;
    self.jid= jid;
    self.connection= connection;
    return self;
}


-(void) processMessage:(ParseMessage *) messageNode
{
    if([messageNode.type isEqualToString:kMessageErrorType])
    {
        DDLogError(@"Error type message received");
        
        if([messageNode.errorReason isEqualToString:@"recipient-unavailable"]) {
               //ignore becasue with push this is moot
               return;
           }
        
        //update db
        [[DataLayer sharedInstance] setMessageId:messageNode.idval errorType:messageNode.errorType?messageNode.errorType:@""
                                     errorReason:messageNode.errorReason?messageNode.errorReason:@""];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageErrorNotice object:nil  userInfo:@{@"MessageID":messageNode.idval,@"errorType":messageNode.errorType?messageNode.errorType:@"",@"errorReason":messageNode.errorReason?messageNode.errorReason:@""
        }];

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
     
        //processed messages already have server name
        if([messageNode.type isEqualToString:kMessageGroupChatType])
        {
            ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:messageNode.from andServer:@"" forAccount:self.accountNo];
        }
        
        if (ownNick!=nil
            && [messageNode.actualFrom isEqualToString:ownNick])
        {
            DDLogDebug(@"Dropping muc echo");
            return;
        }
        else
        {
            NSString *jidWithoutResource =self.jid;
           
            //if mam but newer than last message we do want an alert..
            [[DataLayer sharedInstance] lastMessageDateForContact:messageNode.from andAccount:self.accountNo withCompletion:^(NSDate *lastDate) {
                BOOL unread=YES;
                BOOL showAlert=YES;
                
                if ([messageNode.from isEqualToString:jidWithoutResource]
                    || (messageNode.mamResult
                        && lastDate.timeIntervalSince1970>messageNode.delayTimeStamp.timeIntervalSince1970)) {
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
                    messageType=kMessageTypeStatus;
                    
                    [[DataLayer sharedInstance] mucSubjectforAccount:self.accountNo andRoom:messageNode.from withCompletion:^(NSString *currentSubject) {
                        if(![messageNode.subject isEqualToString:currentSubject]) {
                            [[DataLayer sharedInstance] updateMucSubject:messageNode.subject forAccount:self.accountNo andRoom:messageNode.from withCompletion:nil];
                            
                            if(self.postPersistAction) {
                                self.postPersistAction(YES, encrypted, showAlert, messageNode.subject, messageType);
                            }
                        }
                    }];
                    
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
        if(messageNode.stanzaId) {
            [[DataLayer sharedInstance] setMessageId:messageNode.receivedID stanzaId:messageNode.stanzaId];
        }
        //Post notice
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageReceivedNotice object:self userInfo:@{@"MessageID":messageNode.receivedID}];
    }
    
    if([messageNode.type isEqualToString:kMessageHeadlineType])
    {
        [self processHeadline:messageNode];
    }
    
}
    
-(void) processHeadline:(ParseMessage *) messageNode
{
     if(messageNode.devices)
     {
         [self processOMEMODevices:messageNode.devices from:messageNode.from];
     }
}


-(void) queryOMEMOBundleFrom:(NSString *) jid andDevice:(NSString *) deviceid
{
    if(!self.connection.supportsPubSub) return;
    XMPPIQ* query2 =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [query2 setiqTo:jid];
    [query2 requestBundles:deviceid];
    if(self.sendStanza) self.sendStanza(query2);
}

-(void) sendOMEMODevices:(NSArray *) devices {
    if(!self.connection.supportsPubSub) return;
    
    XMPPIQ *signalDevice = [[XMPPIQ alloc] initWithType:kiqSetType];
    [signalDevice publishDevices:devices];
    if(self.sendStanza) self.sendStanza(signalDevice);
}

-(void) processOMEMODevices:(NSArray *) receivedDevices from:(NSString *) source {
    if(receivedDevices)
    {
        if(!source || [source isEqualToString:self.connection.identity.jid])
        {
            source=self.connection.identity.jid;
            NSMutableArray *devices= [receivedDevices mutableCopy];
            NSSet *deviceSet = [NSSet setWithArray:receivedDevices];
            
            NSString * deviceString=[NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
            BOOL hasAddedDevice=NO;
            if(![deviceSet containsObject:deviceString])
            {
                [devices addObject:deviceString];
                hasAddedDevice=YES;
            }
            if(hasAddedDevice) //prevent infinte loop 
                [self sendOMEMODevices:devices];
        }
        
        NSArray *existingDevices=[self.monalSignalStore knownDevicesForAddressName:source];
        NSSet *deviceSet = [NSSet setWithArray:existingDevices];
        //only query if the device doesnt exist
        [receivedDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *deviceString  =(NSString *)obj;
            NSNumber *deviceNumber = [NSNumber numberWithInt:deviceString.intValue];
            if(![deviceSet containsObject:deviceNumber]) {
                [self queryOMEMOBundleFrom:source andDevice:deviceString];
            } else  {
               
            }
        }];
        
        //if not in device list remove from  knowndevices
        NSSet *iqSet = [NSSet setWithArray:receivedDevices];
        [existingDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSNumber *device  =(NSNumber *)obj;
            NSString *deviceString  =[NSString stringWithFormat:@"%@", device];
            if(![iqSet containsObject:deviceString]) {
                //device was removed
                SignalAddress *address = [[SignalAddress alloc] initWithName:source deviceId:(int) device.integerValue];
                [self.monalSignalStore deleteDeviceforAddress:address];
            }
        }];
        
    }
    
}
    
-(NSString *) decryptMessage:(ParseMessage *) messageNode {
#ifndef DISABLE_OMEMO
    if(messageNode.encryptedPayload)
    {
        SignalAddress *address = [[SignalAddress alloc] initWithName:messageNode.from.lowercaseString deviceId:(uint32_t)messageNode.sid.intValue];
        if(!self.signalContext) {
            DDLogError(@"Missing signal context");
            return NSLocalizedString(@"Error decrypting message",@ "");
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
            DDLogError(@"Message was not encrypted for this device: %d", self.monalSignalStore.deviceid);
            return [NSString stringWithFormat:NSLocalizedString(@"Message was not encrypted for this device. Please make sure the sender trusts deviceid %d and that they have you as a contact.",@ ""),self.monalSignalStore.deviceid];
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
            
            SignalCiphertext* ciphertext = [[SignalCiphertext alloc] initWithData:decoded type:messagetype];
            NSError* error;
            NSData* decryptedKey =  [cipher decryptCiphertext:ciphertext error:&error];
            if(error) {
                DDLogError(@"Could not decrypt to obtain key: %@", error);
                return [NSString stringWithFormat:@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", error];
            }
            NSData* key;
            NSData* auth;
            
            if(messagetype==SignalCiphertextTypePreKeyMessage)
            {
                if(self.signalAction) self.signalAction();
            }
            
            if(!decryptedKey){
                DDLogError(@"Could not decrypt to obtain key.");
                return NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person.",@ "");
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
                        DDLogError(@"Could not decrypt message with key  that was decrypted.");
                         return NSLocalizedString(@"Encrypted message was sent in an older format Monal can't decrypt. Please ask them to update their client. (GCM error)",@ "");
                    }
                    else  {
                        DDLogInfo(@"Decrypted message passing bask string.");
                    }
                    NSString *messageString= [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
                    return messageString;
                    
                } else  {
                    DDLogError(@"Could not get key");
                    return NSLocalizedString(@"Could not decrypt message",@ "");
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
