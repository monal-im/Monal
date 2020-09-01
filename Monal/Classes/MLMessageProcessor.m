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


@interface MLMessageProcessor ()
@property (atomic, strong) SignalContext *signalContext;
@property (atomic, strong) MLSignalStore *monalSignalStore;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) MLXMPPConnection *connection;
@end

static NSMutableDictionary* _typingNotifications;

@implementation MLMessageProcessor

+(void) initialize
{
    _typingNotifications = [[NSMutableDictionary alloc] init];
}

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
            if([messageNode.from isEqualToString:self.jid] || (messageNode.mamResult && ![@"MLcatchup" isEqualToString:messageNode.mamQueryId]))
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
            
            
            if(!body  && messageNode.subject)
            {
                messageType=kMessageTypeStatus;
                
                NSString* currentSubject = [[DataLayer sharedInstance] mucSubjectforAccount:self.accountNo andRoom:messageNode.from];
                if(![messageNode.subject isEqualToString:currentSubject])
                {
                    [[DataLayer sharedInstance] updateMucSubject:messageNode.subject forAccount:self.accountNo andRoom:messageNode.from];
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
            
            if([@"MLbefore" isEqualToString:messageNode.mamQueryId])
            {
                //TODO: handle backwards paging differently (negative database history ids)
                //TODO: we don't want to call self.postPersistAction here, but do something like this:
                //[[NSNotificationCenter defaultCenter] postNotificationName:kMonalHistoryMessageNotice object:self.account userInfo:@{@"message":message}];
                //(see xmpp.m from line 1240 upwards)
            }
            else
            {
                [[DataLayer sharedInstance] addMessageFrom:messageNode.from
                                                        to:recipient
                                                forAccount:self->_accountNo
                                                withBody:[body copy]
                                            actuallyfrom:messageNode.actualFrom
                                                    sent:YES
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
    
    if([messageNode.type isEqualToString:kMessageHeadlineType])
    {
        [self processHeadline:messageNode];
    }
    
    //ignore typing notifications when in appex
    if(![HelperTools isAppExtension])
    {
        //only use "is typing" messages when not older than 2 minutes (always allow "not typing" messages)
        if([[DataLayer sharedInstance] checkCap:@"http://jabber.org/protocol/chatstates" forUser:messageNode.user andAccountNo:self.accountNo] &&
            ((messageNode.composing && (!messageNode.delayTimeStamp || [[NSDate date] timeIntervalSinceDate:messageNode.delayTimeStamp] < 120)) ||
            messageNode.notComposing)
        )
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                @"jid": messageNode.user,
                @"accountNo": self.accountNo,
                @"isTyping": messageNode.composing ? @YES : @NO
            }];
            //send "not typing" notifications (kMonalLastInteractionUpdatedNotice) 60 seconds after the last isTyping was received
            @synchronized(_typingNotifications) {
                //copy needed values into local variables to not retain self by our timer block
                NSString* account = self.accountNo;
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
            
            NSData *decoded= [HelperTools dataWithBase64EncodedString:[messageKey objectForKey:@"key"]];
            
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
                    NSData *iv = [HelperTools dataWithBase64EncodedString:messageNode.iv];
                    NSData *decodedPayload = [HelperTools dataWithBase64EncodedString:messageNode.encryptedPayload];
                    
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
