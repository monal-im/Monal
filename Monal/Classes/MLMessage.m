//
//  MLMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLMessage.h"
#import "MLContact.h"

@implementation MLMessage

+(MLMessage*) messageFromDictionary:(NSDictionary*) dic
{
    MLMessage* message = [[MLMessage alloc] init];
    message.accountId = [NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
    
    message.buddyName = [dic objectForKey:@"buddy_name"];
    message.inbound = [(NSNumber*)[dic objectForKey:@"inbound"] boolValue];
    message.actualFrom = [dic objectForKey:@"af"];
    message.messageText = [dic objectForKey:@"message"];
    message.isMuc = [(NSNumber*)[dic objectForKey:@"Muc"] boolValue];
    
    message.messageId = [dic objectForKey:@"messageid"];
    message.stanzaId = [dic objectForKey:@"stanzaid"];
    message.messageDBId = [dic objectForKey:@"message_history_id"];
    message.timestamp = [dic objectForKey:@"thetime"];
    message.messageType = [dic objectForKey:@"messageType"];
    message.mucType = [dic objectForKey:@"muc_type"];
    message.participantJid = [dic objectForKey:@"participant_jid"];
    
    message.hasBeenDisplayed = [(NSNumber*)[dic objectForKey:@"displayed"] boolValue];
    message.hasBeenReceived = [(NSNumber*)[dic objectForKey:@"received"] boolValue];
    message.hasBeenSent = [(NSNumber*)[dic objectForKey:@"sent"] boolValue];
    message.encrypted = [(NSNumber*)[dic objectForKey:@"encrypted"] boolValue];
    
    message.unread = [(NSNumber*)[dic objectForKey:@"unread"] boolValue];
    message.displayMarkerWanted = [(NSNumber*)[dic objectForKey:@"displayMarkerWanted"] boolValue];
    
    message.previewText = [dic objectForKey:@"previewText"];
    message.previewImage = [NSURL URLWithString:[dic objectForKey:@"previewImage"]];
    
    message.errorType = [dic objectForKey:@"errorType"];
    message.errorReason = [dic objectForKey:@"errorReason"];
    
    message.filetransferMimeType = [dic objectForKey:@"filetransferMimeType"];
    message.filetransferSize = [dic objectForKey:@"filetransferSize"];
    
    return message;
}

-(void) updateWithMessage:(MLMessage*) msg
{
    self.accountId = msg.accountId;
    self.buddyName = msg.buddyName;
    self.inbound = msg.inbound;
    self.actualFrom = msg.actualFrom;
    self.messageText = msg.messageText;
    self.isMuc = msg.isMuc;
    self.messageId = msg.messageId;
    self.stanzaId = msg.stanzaId;
    self.messageDBId = msg.messageDBId;
    self.timestamp = msg.timestamp;
    self.messageType = msg.messageType;
    self.mucType = msg.mucType;
    self.participantJid = msg.participantJid;
    self.hasBeenDisplayed = msg.hasBeenDisplayed;
    self.hasBeenReceived = msg.hasBeenReceived;
    self.hasBeenSent = msg.hasBeenSent;
    self.encrypted = msg.encrypted;
    self.unread = msg.unread;
    self.displayMarkerWanted = msg.displayMarkerWanted;
    self.previewText = msg.previewText;
    self.previewImage = msg.previewImage;
    self.errorType = msg.errorType;
    self.errorReason = msg.errorReason;
    self.filetransferMimeType = msg.filetransferMimeType;
    self.filetransferSize = msg.filetransferSize;
}

-(BOOL) isEqualToContact:(MLContact*) contact
{
    return contact != nil &&
           [self.buddyName isEqualToString:contact.contactJid] &&
           [self.accountId isEqualToString:contact.accountId];
}

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return message != nil &&
           [self.accountId isEqualToString:message.accountId] &&
           [self.buddyName isEqualToString:message.buddyName] &&
           self.inbound == message.inbound &&
           [self.actualFrom isEqualToString:message.actualFrom] &&
           (
               // either the stanzaid is equal --> strong same message
               // or the message id is equal --> weak same message (but together with the message text it should be sufficient)
               [self.stanzaId isEqualToString:message.stanzaId] ||
               ([self.messageId isEqualToString:message.messageId] && [self.messageText isEqualToString:message.messageText])
           );
}

-(BOOL) isEqual:(id) object
{
    if(self == object)
        return YES;
    if([object isKindOfClass:[MLContact class]])
        return [self isEqualToContact:(MLContact*)object];
    if([object isKindOfClass:[MLMessage class]])
        return [self isEqualToMessage:(MLMessage*)object];
    return NO;
}

@end
