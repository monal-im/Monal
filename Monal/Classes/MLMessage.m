//
//  MLMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <monalxmpp/MLMessage.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLChannelContact.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/xmpp.h>
#import "XMPPMessage.h"

static NSMutableDictionary* _singletonCache;

@implementation MLMessage
{
    id<MLContactProtocol> _contact;
}

+(void) initialize
{
    _singletonCache = [NSMutableDictionary new];
}

+(MLMessage*) createMessageFromHistoryID:(NSNumber*) historyID
{
    if(historyID == nil)
        return nil;
    NSArray<MLMessage*>* result = [[DataLayer sharedInstance] messagesForHistoryIDs:@[historyID]];
    if(![result count])
        return nil;
    return result[0];
}

+(MLMessage*) messageFromDictionary:(NSDictionary*) dic
{
    // Draft messages don't have a historyID and shouldn't be cached
    if([[dic objectForKey:@"messageType"] isEqualToString:kMessageTypeMessageDraft])
    {
        MLMessage* message = [MLMessage new];
        // Fill only the properties useful for a draft message
        // The timestamp is used when rendering MLContactCell, among other things
        message.messageText = [dic objectForKey:@"message"];
        message.messageType = [dic objectForKey:@"messageType"];
        message.timestamp = [dic objectForKey:@"thetime"];
        return message;
    }

    NSNumber* cacheKey = [dic objectForKey:@"message_history_id"];
    MLAssert(cacheKey != nil, @"A non-draft message can't have a nil historyID!");
    MLMessage* message = nil;
    @synchronized(_singletonCache) {
        if(_singletonCache[cacheKey] != nil)
        {
            MLMessage* obj = ((WeakContainer*)_singletonCache[cacheKey]).obj;
            DDLogDebug(@"Singleton cache for message filled: %@, entry: %@", cacheKey, obj);
            if(obj != nil)
                return obj;
            else
                [_singletonCache removeObjectForKey:cacheKey];
        }

        message = [MLMessage new];
        message.accountID = [dic objectForKey:@"account_id"];

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
        message.occupantId = [dic objectForKey:@"occupant_id"];

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
        
        _singletonCache[cacheKey] = [[WeakContainer alloc] initWithObj:message];
    }
    //fill reactions *after* adding this message to our singleton cache to not create an endless loop
    //(the reactions reference back to this message, but don't store a reference, so no retain cycle)
    message.reactions = [[DataLayer sharedInstance] getReactionsForHistoryId:message.messageDBId];
    return message;
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    //only encode things needed for draft messages (those are NOT singletons)
    //and the id used for the singleton (the message db id)
    [coder encodeObject:self.messageText forKey:@"messageText"];
    [coder encodeObject:self.messageDBId forKey:@"messageDBId"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
    [coder encodeObject:self.messageType forKey:@"messageType"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    //decode everything needed for message drafts and the singleton id.
    //if this is a singleton, this object will be replaced by the real
    //singleton one in awakeAfterUsingCoder
    self = [self init];
    self.messageText = [coder decodeObjectForKey:@"messageText"];
    self.messageDBId = [coder decodeObjectForKey:@"messageDBId"];
    self.timestamp = [coder decodeObjectForKey:@"timestamp"];
    self.messageType = [coder decodeObjectForKey:@"messageType"];
    return self;
}

//make sure this singleton remains a singleton, even after decoding (but only for non-draft messages)
-(instancetype) awakeAfterUsingCoder:(NSCoder*) coder
{
    if(![self.messageType isEqualToString:kMessageTypeMessageDraft])
        return [[self class] createMessageFromHistoryID:self.messageDBId];
    return self;        //draft messages are not singletons
}

-(instancetype) init
{
    self = [super init];
    //watch for all sorts of changes and update our singleton dynamically
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageUpdate:) name:kMonalUpdatedMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageDeletion:) name:kMonalDeletedMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleFiletransferUpdate:) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageSent:) name:kMonalSentMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageReceived:) name:kMonalMessageReceivedNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageDisplayed:) name:kMonalMessageDisplayedNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageError:) name:kMonalMessageErrorNotice object:nil];
    return self;
}

-(void) dealloc
{
    DDLogDebug(@"Deallocating %@", self.messageDBId);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleMessageUpdate:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLMessage* message = data[@"message"];
    MLAssert(message != nil, @"Notification without message");
    if(self.messageDBId.integerValue != message.messageDBId.integerValue)
        return;         //ignore updates of other messages
    NSNumber* LMCReplaced = data[@"LMCReplaced"];
    MLAssert(LMCReplaced != nil, @"Message update notification without LMCReplaced object");
    NSNumber* reactionsUpdate = data[@"reactionsUpdate"];
    MLAssert(reactionsUpdate != nil, @"Message update notification without reactionsUpdate object");
    if(LMCReplaced.boolValue)
    {
        // Message correction
        NSString* correctedText = data[@"correctedText"];
        MLAssert(correctedText != nil, @"Message correction notification without the corrected text");
        self.messageText = correctedText;
    }
    else if(reactionsUpdate.boolValue)
    {
        MLAssert(data[@"reactions"] != nil, @"Reactions updates MUST contain a reactions dictionary!");
        self.reactions = data[@"reactions"];
    }
    
    // MUC reflection and everything else
    DDLogDebug(@"Updating stanzaid of %p: %@", self, data[@"stanzaId"]);
    self.stanzaId = data[@"stanzaId"];
}

// Handle message retraction and moderation
-(void) handleMessageDeletion:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLAssert(data[@"historyId"] != nil, @"kMonalDeletedMessageNotice without historyId!");
    if(self.messageDBId.integerValue != [data[@"historyId"] integerValue])
        return;         //ignore deletions of other messages

    self.messageText = @"";
    self.messageType = kMessageTypeText;
    self.filetransferMimeType = @"";
    self.filetransferSize = @0;
    self.retracted = YES;
}

-(void) handleFiletransferUpdate:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLMessage* message = data[@"message"];
    MLAssert(message != nil, @"Notification without message");
    if(self.messageDBId.integerValue != message.messageDBId.integerValue)
        return;         //ignore filetransfer updates of other messages

    NSString* mimeType = data[@"mimeType"];
    NSNumber* filetransferSize = data[@"filetransferSize"];
    MLAssert(mimeType != nil && filetransferSize != nil, @"Notification without mimeType and/or filetransferSize");
    self.filetransferMimeType = mimeType;
    self.filetransferSize = filetransferSize;
}

-(void) handleMessageSent:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    XMPPMessage* messageNode = data[@"message"];
    MLAssert(messageNode != nil, @"Notification without message node");
    if([messageNode.id isEqualToString:self.messageId])
        self.hasBeenSent = YES;
}

-(void) handleMessageReceived:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    NSString* messageId = data[kMessageId];
    NSString* jid = data[@"jid"];
    MLAssert(messageId != nil && jid != nil, @"Notification without jid and/or messageId");
    if([messageId isEqualToString:self.messageId] && [jid isEqualToString:self.buddyName])
    {
        self.hasBeenSent = YES;
        self.hasBeenReceived = YES;
    }
}

-(void) handleMessageDisplayed:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLMessage* message = data[@"message"];
    MLAssert(message != nil, @"Notification without message");
    if(self.messageDBId.integerValue != message.messageDBId.integerValue)
        return;         //ignore displayed notices of other messages

    self.hasBeenSent = YES;
    self.hasBeenReceived = YES;
    self.hasBeenDisplayed = YES;
}

-(void) handleMessageError:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    NSString* jid = data[@"jid"];
    NSString* messageId = data[kMessageId];
    NSString* errorType = data[@"errorType"];
    NSString* errorReason = data[@"errorReason"];
    MLAssert(jid != nil && messageId != nil && errorType != nil && errorReason != nil, @"Notification is missing data");

    if([messageId isEqualToString:self.messageId] && [jid isEqualToString:self.buddyName])
    {
        //we don't want to show errors if the message has been received at least once
        if(!self.hasBeenReceived)
        {
            self.errorType = errorType;
            self.errorReason = errorReason;
        }
    }
}

-(NSString*) contactDisplayName
{
    if(self.isMuc)
    {
        if([kMucTypeGroup isEqualToString:self.mucType] && self.participantJid)
            return [[MLContact createContactFromJid:self.participantJid andAccountID:self.accountID] contactDisplayNameWithFallback:self.actualFrom];
        else
            return self.actualFrom;
    }
    else
        return [MLContact createContactFromJid:self.buddyName andAccountID:self.accountID].contactDisplayName;
}

-(xmpp* _Nullable) account
{
    return [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
}

-(id<MLContactProtocol>) contact
{
    if(self->_contact != nil)
        return self->_contact;
    if(self.isMuc)
    {
        if([kMucTypeChannel isEqualToString:[[DataLayer sharedInstance] getMucTypeOfRoom:self.buddyName andAccount:self.accountID]])
            return self->_contact = [MLChannelContact createChannelContactFromOccupantId:self.occupantId withNick:nilDefault(self.actualFrom, self.occupantId) inMuc:[MLContact createContactFromJid:self.buddyName andAccountID:self.accountID]];
        else
        {
            if(self.inbound)
                return self->_contact = [MLContact createContactFromJid:self.participantJid andAccountID:self.accountID];
            else
                return self->_contact = self.account.contact;
        }
    }
    else
    {
        if(self.inbound)
            return self->_contact = [MLContact createContactFromJid:self.buddyName andAccountID:self.accountID];
        else
            return self->_contact = self.account.contact;
    }
}

-(MLContact*) chatContact
{
    return [MLContact createContactFromJid:self.buddyName andAccountID:self.accountID];
}

-(BOOL) isEqualToContact:(id<MLContactProtocol>) contact
{
    return [self isEqual:contact];
}

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return message != nil &&
           self.accountID.intValue == message.accountID.intValue &&
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
    else if([object isKindOfClass:[MLMessage class]])
        return [self isEqualToMessage:(MLMessage*)object];
    else if([object conformsToProtocol:@protocol(MLContactProtocol)])
        return [(id<MLContactProtocol>)object isEqualToMessage:self];
    return NO;
}

-(NSUInteger) hash
{
    return [self.accountID hash] ^ [self.buddyName hash] ^ (self.inbound ? 1 : 0) ^
           [self.actualFrom hash] ^ [self.messageText hash] ^ [self.messageId hash] ^
           [self.stanzaId hash];
}

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@|%@", self.accountID, self.messageDBId];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@: %@ (%@) {%@messageID: %@, stanzaID: %@} --> %@ (%p)",
        self.accountID,
        self.isMuc ? @"1:1" : self.mucType,
        self.participantJid ? self.participantJid : self.buddyName,
        self.retracted ? @"retracted " : @"",
        self.messageId,
        self.stanzaId,
        self.messageDBId,
        self
    ];
}

@end
