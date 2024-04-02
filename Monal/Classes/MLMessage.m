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
    MLMessage* message = [MLMessage new];
    message.accountId = [dic objectForKey:@"account_id"];
    
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
    
    message.retracted = [(NSNumber*)[dic objectForKey:@"retracted"] boolValue];
    
    return message;
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.accountId forKey:@"accountId"];
    [coder encodeObject:self.buddyName forKey:@"buddyName"];
    [coder encodeBool:self.inbound forKey:@"inbound"];
    [coder encodeObject:self.actualFrom forKey:@"actualFrom"];
    [coder encodeObject:self.messageText forKey:@"messageText"];
    [coder encodeBool:self.isMuc forKey:@"isMuc"];
    [coder encodeObject:self.messageId forKey:@"messageId"];
    [coder encodeObject:self.stanzaId forKey:@"stanzaId"];
    [coder encodeObject:self.messageDBId forKey:@"messageDBId"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
    [coder encodeObject:self.messageType forKey:@"messageType"];
    [coder encodeObject:self.mucType forKey:@"mucType"];
    [coder encodeObject:self.participantJid forKey:@"participantJid"];
    [coder encodeBool:self.hasBeenDisplayed forKey:@"hasBeenDisplayed"];
    [coder encodeBool:self.hasBeenReceived forKey:@"hasBeenReceived"];
    [coder encodeBool:self.hasBeenSent forKey:@"hasBeenSent"];
    [coder encodeBool:self.encrypted forKey:@"encrypted"];
    [coder encodeBool:self.unread forKey:@"unread"];
    [coder encodeBool:self.displayMarkerWanted forKey:@"displayMarkerWanted"];
    [coder encodeObject:self.previewText forKey:@"previewText"];
    [coder encodeObject:self.previewImage forKey:@"previewImage"];
    [coder encodeObject:self.errorType forKey:@"errorType"];
    [coder encodeObject:self.errorReason forKey:@"errorReason"];
    [coder encodeObject:self.filetransferMimeType forKey:@"filetransferMimeType"];
    [coder encodeObject:self.filetransferSize forKey:@"filetransferSize"];
    [coder encodeBool:self.retracted forKey:@"retracted"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    self.accountId = [coder decodeObjectForKey:@"accountId"];
    self.buddyName = [coder decodeObjectForKey:@"buddyName"];
    self.inbound = [coder decodeBoolForKey:@"inbound"];
    self.actualFrom = [coder decodeObjectForKey:@"actualFrom"];
    self.messageText = [coder decodeObjectForKey:@"messageText"];
    self.isMuc = [coder decodeBoolForKey:@"isMuc"];
    self.messageId = [coder decodeObjectForKey:@"messageId"];
    self.stanzaId = [coder decodeObjectForKey:@"stanzaId"];
    self.messageDBId = [coder decodeObjectForKey:@"messageDBId"];
    self.timestamp = [coder decodeObjectForKey:@"timestamp"];
    self.messageType = [coder decodeObjectForKey:@"messageType"];
    self.mucType = [coder decodeObjectForKey:@"mucType"];
    self.participantJid = [coder decodeObjectForKey:@"participantJid"];
    self.hasBeenDisplayed = [coder decodeBoolForKey:@"hasBeenDisplayed"];
    self.hasBeenReceived = [coder decodeBoolForKey:@"hasBeenReceived"];
    self.hasBeenSent = [coder decodeBoolForKey:@"hasBeenSent"];
    self.encrypted = [coder decodeBoolForKey:@"encrypted"];
    self.unread = [coder decodeBoolForKey:@"unread"];
    self.displayMarkerWanted = [coder decodeBoolForKey:@"displayMarkerWanted"];
    self.previewText = [coder decodeObjectForKey:@"previewText"];
    self.previewImage = [coder decodeObjectForKey:@"previewImage"];
    self.errorType = [coder decodeObjectForKey:@"errorType"];
    self.errorReason = [coder decodeObjectForKey:@"errorReason"];
    self.filetransferMimeType = [coder decodeObjectForKey:@"filetransferMimeType"];
    self.filetransferSize = [coder decodeObjectForKey:@"filetransferSize"];
    self.retracted = [coder decodeBoolForKey:@"retracted"];
    return self;
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
    self.retracted = msg.retracted;
}

-(NSString*) contactDisplayName
{
    if(self.isMuc)
    {
        if([@"group" isEqualToString:self.mucType] && self.participantJid)
            return [[MLContact createContactFromJid:self.participantJid andAccountNo:self.accountId] contactDisplayNameWithFallback:self.actualFrom];
        else
            return self.actualFrom;
    }
    else
        return [MLContact createContactFromJid:self.buddyName andAccountNo:self.accountId].contactDisplayName;
}

-(BOOL) isEqualToContact:(MLContact*) contact
{
    return contact != nil &&
           [self.buddyName isEqualToString:contact.contactJid] &&
           self.accountId.intValue == contact.accountId.intValue;
}

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return message != nil &&
           self.accountId.intValue == message.accountId.intValue &&
           [self.buddyName isEqualToString:message.buddyName] &&
           self.inbound == message.inbound &&
           [self.actualFrom isEqualToString:message.actualFrom] &&
           (
               // either the stanzaid is equal --> strong same message
               // or the message id is equal (could be stanza id or origin id) --> weak same message, if stanza id
               [self.stanzaId isEqualToString:message.stanzaId] ||
               [self.messageId isEqualToString:message.messageId]
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

-(NSUInteger) hash
{
    return [self.accountId hash] ^ [self.buddyName hash] ^ (self.inbound ? 1 : 0) ^
           [self.actualFrom hash] ^ [self.messageText hash] ^ [self.messageId hash] ^
           [self.stanzaId hash];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@: %@ {%@messageID: %@, stanzaID: %@} --> %@",
        self.accountId,
        self.participantJid ? self.participantJid : self.buddyName,
        self.retracted ? @"retracted " : @"",
        self.messageId,
        self.stanzaId,
        self.messageDBId
    ];
}

@end
