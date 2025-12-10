//
//  MLReactionsEntry.m
//  monalxmpp
//
//  Created by Thilo Molitor  on 08.12.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLReactionsEntry.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLChannelContact.h>

@interface MLReactionsEntry ()
@property (nonatomic) NSNumber* historyId;
@property (nonatomic) NSString* user;
@property (nonatomic) NSString* _Nullable jid;
@property (nonatomic) NSString* _Nullable occupantId;
@property (nonatomic) NSString* _Nullable mucNick;
@property (nonatomic) NSSet<NSString*>* reactions;
@property (nonatomic) NSDate* timestamp;
@property (nonatomic) MLMessage* message;
@property (nonatomic) id<MLContactProtocol> contact;
@end

@implementation MLReactionsEntry

-(instancetype) initWithDictionary:(NSDictionary*) dict
{
    self = [super init];
    MLAssert(dict[@"jid"] != nil || dict[@"occupant_id"] != nil, @"Either jid or occupant_id have to be non nil!", (@{@"dict": dict}));
    MLAssert(!(dict[@"jid"] != nil && dict[@"occupant_id"] != nil), @"Reactions should all have either a jid or be recieved in a channel and have an occupantId, not both!", (@{@"dict": dict}));
    
    self.historyId = dict[@"message_history_id"];
    self.user = dict[@"user"];
    self.jid = dict[@"jid"];
    self.occupantId = dict[@"occupant_id"];
    self.mucNick = dict[@"muc_nick"];
    self.reactions = [HelperTools createReactionsSetFromString:dict[@"reactions"]];
    self.timestamp = [HelperTools parseDateTimeString:dict[@"timestamp"]];
    
    //jid and occupantId will never be both set
    if(self.jid != nil)     //this is a non-anon muc or an 1:1 chat
        self.contact = [MLContact createContactFromJid:self.jid andAccountID:dict[@"account_id"]];
    else                    //this is a channel-type muc
        self.contact = [MLChannelContact
            createChannelContactFromOccupantId:self.occupantId
            withNick:nilDefault(self.mucNick, self.occupantId)
            inMuc:self.message.chatContact
        ];
    
    return self;
}

-(MLMessage*) message
{
    return [MLMessage createMessageFromHistoryID:self.historyId];
}

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return [self.message isEqual:message];
}

-(BOOL) isEqualToContact:(id<MLContactProtocol>) contact
{
    if(contact == nil)
        return NO;
    return [self.contact isEqual:contact];
}

-(BOOL) isEqualToReactionsEntry:(MLReactionsEntry*) reactions
{
    return self.historyId == reactions.historyId &&
        [self.user isEqualToString:reactions.user] &&
        [self.reactions isEqual:reactions.reactions];
}

-(BOOL) isEqual:(id) object
{
    if(self == object)
        return YES;
    else if([object isKindOfClass:[MLReactionsEntry class]])
        return [self isEqualToReactionsEntry:object];
    else if([object isKindOfClass:[MLMessage class]])
        return [self isEqualToMessage:object];
    else if([object conformsToProtocol:@protocol(MLContactProtocol)])
        return [self isEqualToContact:object];
    return NO;
}

-(NSUInteger) hash
{
    return [self.historyId hash] ^ [self.user hash] ^ [self.contact hash] ^
           [self.reactions hash] ^ [self.mucNick hash] ^ [self.timestamp hash];
}

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@|%@", self.historyId, self.user];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"Reactions to {%@} from {%@} at %@: %@",
        self.message,
        self.contact,
        self.timestamp,
        self.reactions
    ];
}

@end
