//
//  MLContact.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLContact.h"
#import "HelperTools.h"
#import "DataLayer.h"


NSString *const kSubBoth=@"both";
NSString *const kSubNone=@"none";
NSString *const kSubTo=@"to";
NSString *const kSubFrom=@"from";
NSString *const kSubRemove=@"remove";
NSString *const kAskSubscribe=@"subscribe";


@implementation MLContact

+(NSString*) ownDisplayNameForAccountNo:(NSString*) accountNo andOwnJid:(NSString*)jid
{
    NSDictionary* accountDic = [[DataLayer sharedInstance] detailsForAccount:accountNo];
    DDLogVerbose(@"Own nickname in accounts table %@: %@", accountNo, accountDic[kRosterName]);
    NSString* displayName = accountDic[kRosterName];
    if(!displayName || !displayName.length)
    {
        //default is local part, see https://docs.modernxmpp.org/client/design/#contexts
        //see also: MLContact.m (the only other source that decides what to use as display name)
        NSDictionary* jidParts = [HelperTools splitJid:jid];
        displayName = jidParts[@"node"];
    }
    DDLogVerbose(@"Calculated ownDisplayName for '%@': %@", jid, displayName);
    return displayName;
}

-(NSString*) contactDisplayName
{
    NSString* displayName;
    if(self.isGroup && self.accountNickInGroup && self.accountNickInGroup.length)
    {
        DDLogVerbose(@"Using accountNickInGroup: %@", self.accountNickInGroup);
        displayName = self.accountNickInGroup;
    }
    else if(self.nickName && self.nickName.length > 0)
    {
        DDLogVerbose(@"Using nickName: %@", self.nickName);
        displayName = self.nickName;
    }
    else if(self.fullName && self.fullName.length > 0)
    {
        DDLogVerbose(@"Using fullName: %@", self.fullName);
        displayName = self.fullName;
    }
    else
    {
        //default is local part, see https://docs.modernxmpp.org/client/design/#contexts
        NSDictionary* jidParts = [HelperTools splitJid:self.contactJid];
        displayName = jidParts[@"node"];
        DDLogVerbose(@"Using default: %@", jidParts[@"node"]);
    }
    DDLogVerbose(@"Calculated contactDisplayName for '%@': %@", self.contactJid, displayName);
    return displayName;
}

+(MLContact*) contactFromDictionary:(NSDictionary*) dic
{
    MLContact *contact = [[MLContact alloc] init];
    contact.contactJid = [dic objectForKey:@"buddy_name"];
    contact.nickName = [dic objectForKey:@"nick_name"];
    contact.fullName = [dic objectForKey:@"full_name"];
    contact.imageFile = [dic objectForKey:@"filename"];
    contact.subscription = [dic objectForKey:@"subscription"];
    contact.ask = [dic objectForKey:@"ask"];
    contact.accountId=[NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
    contact.groupSubject = [dic objectForKey:@"muc_subject"];
    contact.accountNickInGroup = [dic objectForKey:@"muc_nick"];
    contact.isGroup = [[dic objectForKey:@"Muc"] boolValue];
    contact.isPinned = [[dic objectForKey:@"pinned"] boolValue];
    contact.statusMessage = [dic objectForKey:@"status"];
    contact.state = [dic objectForKey:@"state"];
    contact.unreadCount = [[dic objectForKey:@"count"] integerValue];
    contact.isActiveChat = [[dic objectForKey:@"isActiveChat"] boolValue];
    //make sure isGroup is set correctly
    if(contact.groupSubject.length > 0 || contact.accountNickInGroup.length > 0)
        contact.isGroup = YES;
    return contact;
}

+(MLContact*) contactFromDictionary:(NSDictionary*) dic withDateFormatter:(NSDateFormatter*) formatter
{
    MLContact* contact = [self contactFromDictionary:dic];
    contact.lastMessageTime = [formatter dateFromString:[dic objectForKey:@"lastMessageTime"]]; 
    return contact;
}

#pragma mark - NSCoding

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.contactJid forKey:@"contactJid"];
    [coder encodeObject:self.nickName forKey:@"nickName"];
    [coder encodeObject:self.fullName forKey:@"fullName"];
    [coder encodeObject:self.imageFile forKey:@"imageFile"];
    [coder encodeObject:self.subscription forKey:@"subscription"];
    [coder encodeObject:self.ask forKey:@"ask"];
    [coder encodeObject:self.accountId forKey:@"accountId"];
    [coder encodeObject:self.groupSubject forKey:@"groupSubject"];
    [coder encodeObject:self.accountNickInGroup forKey:@"accountNickInGroup"];
    [coder encodeBool:self.isGroup forKey:@"isGroup"];
    [coder encodeBool:self.isPinned forKey:@"isPinned"];
    [coder encodeObject:self.statusMessage forKey:@"statusMessage"];
    [coder encodeObject:self.state forKey:@"state"];
    [coder encodeInteger:self.unreadCount forKey:@"unreadCount"];
    [coder encodeObject:self.lastMessageTime forKey:@"lastMessageTime"];
    [coder encodeBool:self.isActiveChat forKey:@"isActiveChat"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [super init];
    self.contactJid = [coder decodeObjectForKey:@"contactJid"];
    self.nickName = [coder decodeObjectForKey:@"nickName"];
    self.fullName = [coder decodeObjectForKey:@"fullName"];
    self.imageFile = [coder decodeObjectForKey:@"imageFile"];
    self.subscription = [coder decodeObjectForKey:@"subscription"];
    self.ask = [coder decodeObjectForKey:@"ask"];
    self.accountId = [coder decodeObjectForKey:@"accountId"];
    self.groupSubject = [coder decodeObjectForKey:@"groupSubject"];
    self.accountNickInGroup = [coder decodeObjectForKey:@"accountNickInGroup"];
    self.isGroup = [coder decodeBoolForKey:@"isGroup"];
    self.isPinned = [coder decodeBoolForKey:@"isPinned"];
    self.statusMessage = [coder decodeObjectForKey:@"statusMessage"];
    self.state = [coder decodeObjectForKey:@"state"];
    self.unreadCount = [coder decodeIntegerForKey:@"unreadCount"];
    self.lastMessageTime = [coder decodeObjectForKey:@"lastMessageTime"];
    self.isActiveChat = [coder decodeBoolForKey:@"isActiveChat"];
    return self;
}

-(void) updateWithContact:(MLContact*) contact
{
    self.contactJid = contact.contactJid;
    self.nickName = contact.nickName;
    self.fullName = contact.fullName;
    self.imageFile = contact.imageFile;
    self.subscription = contact.subscription;
    self.ask = contact.ask;
    self.accountId = contact.accountId;
    self.groupSubject = contact.groupSubject;
    self.accountNickInGroup = contact.accountNickInGroup;
    self.isGroup = contact.isGroup;
    self.isPinned = contact.isPinned;
    self.statusMessage = contact.statusMessage;
    self.state = contact.state;
    self.unreadCount = contact.unreadCount;
    self.lastMessageTime = contact.lastMessageTime;
    self.isActiveChat = contact.isActiveChat;
}

@end
