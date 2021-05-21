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
#import "xmpp.h"

NSString *const kSubBoth=@"both";
NSString *const kSubNone=@"none";
NSString *const kSubTo=@"to";
NSString *const kSubFrom=@"from";
NSString *const kSubRemove=@"remove";
NSString *const kAskSubscribe=@"subscribe";


@implementation MLContact

+(BOOL) supportsSecureCoding
{
    return YES;
}

+(NSString*) ownDisplayNameForAccount:(xmpp*) account
{
    NSDictionary* accountDic = [[DataLayer sharedInstance] detailsForAccount:account.accountNo];
    DDLogVerbose(@"Own nickname in accounts table %@: %@", account.accountNo, accountDic[kRosterName]);
    NSString* displayName = accountDic[kRosterName];
    if(!displayName || !displayName.length)
    {
        //default is local part, see https://docs.modernxmpp.org/client/design/#contexts
        NSDictionary* jidParts = [HelperTools splitJid:account.connectionProperties.identity.jid];
        displayName = jidParts[@"node"];
    }
    DDLogVerbose(@"Calculated ownDisplayName for '%@': %@", account.connectionProperties.identity.jid, displayName);
    return displayName;
}

-(NSString*) contactDisplayName
{
    NSString* displayName;
    if(self.nickName && self.nickName.length > 0)
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
    MLContact* contact = [[MLContact alloc] init];
    contact.contactJid = [dic objectForKey:@"buddy_name"];
    contact.nickName = [dic objectForKey:@"nick_name"];
    contact.fullName = [dic objectForKey:@"full_name"];
    contact.subscription = [dic objectForKey:@"subscription"];
    contact.ask = [dic objectForKey:@"ask"];
    contact.accountId = [NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
    contact.groupSubject = [dic objectForKey:@"muc_subject"];
    contact.accountNickInGroup = [dic objectForKey:@"muc_nick"];
    contact.mucType = [dic objectForKey:@"muc_type"];
    contact.isGroup = [[dic objectForKey:@"Muc"] boolValue];
    if(contact.isGroup  && !contact.mucType)
        contact.mucType = @"channel";       //default value
    contact.isPinned = [[dic objectForKey:@"pinned"] boolValue];
    contact.isBlocked = [[dic objectForKey:@"blocked"] boolValue];
    contact.statusMessage = [dic objectForKey:@"status"];
    contact.state = [dic objectForKey:@"state"];
    contact.unreadCount = [[dic objectForKey:@"count"] integerValue];
    contact.isActiveChat = [[dic objectForKey:@"isActiveChat"] boolValue];
    contact.isEncrypted = [[dic objectForKey:@"encrypt"] boolValue];
    contact.isMuted = [[dic objectForKey:@"muted"] boolValue];
    contact.lastMessageTime = [dic objectForKey:@"lastMessageTime"];
    return contact;
}

#pragma mark - NSCoding

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.contactJid forKey:@"contactJid"];
    [coder encodeObject:self.nickName forKey:@"nickName"];
    [coder encodeObject:self.fullName forKey:@"fullName"];
    [coder encodeObject:self.subscription forKey:@"subscription"];
    [coder encodeObject:self.ask forKey:@"ask"];
    [coder encodeObject:self.accountId forKey:@"accountId"];
    [coder encodeObject:self.groupSubject forKey:@"groupSubject"];
    [coder encodeObject:self.accountNickInGroup forKey:@"accountNickInGroup"];
    [coder encodeObject:self.mucType forKey:@"mucType"];
    [coder encodeBool:self.isGroup forKey:@"isGroup"];
    [coder encodeBool:self.isPinned forKey:@"isPinned"];
    [coder encodeBool:self.isBlocked forKey:@"isBlocked"];
    [coder encodeObject:self.statusMessage forKey:@"statusMessage"];
    [coder encodeObject:self.state forKey:@"state"];
    [coder encodeInteger:self.unreadCount forKey:@"unreadCount"];
    [coder encodeBool:self.isActiveChat forKey:@"isActiveChat"];
    [coder encodeBool:self.isEncrypted forKey:@"isEncrypted"];
    [coder encodeBool:self.isMuted forKey:@"isMuted"];
    [coder encodeObject:self.lastMessageTime forKey:@"lastMessageTime"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [super init];
    self.contactJid = [coder decodeObjectForKey:@"contactJid"];
    self.nickName = [coder decodeObjectForKey:@"nickName"];
    self.fullName = [coder decodeObjectForKey:@"fullName"];
    self.subscription = [coder decodeObjectForKey:@"subscription"];
    self.ask = [coder decodeObjectForKey:@"ask"];
    self.accountId = [coder decodeObjectForKey:@"accountId"];
    self.groupSubject = [coder decodeObjectForKey:@"groupSubject"];
    self.accountNickInGroup = [coder decodeObjectForKey:@"accountNickInGroup"];
    self.mucType = [coder decodeObjectForKey:@"mucType"];
    self.isGroup = [coder decodeBoolForKey:@"isGroup"];
    self.isPinned = [coder decodeBoolForKey:@"isPinned"];
    self.isBlocked = [coder decodeBoolForKey:@"isBlocked"];
    self.statusMessage = [coder decodeObjectForKey:@"statusMessage"];
    self.state = [coder decodeObjectForKey:@"state"];
    self.unreadCount = [coder decodeIntegerForKey:@"unreadCount"];
    self.isActiveChat = [coder decodeBoolForKey:@"isActiveChat"];
    self.isEncrypted = [coder decodeBoolForKey:@"isEncrypted"];
    self.isMuted = [coder decodeBoolForKey:@"isMuted"];
    self.lastMessageTime = [coder decodeObjectForKey:@"lastMessageTime"];
    return self;
}

-(void) updateWithContact:(MLContact*) contact
{
    self.contactJid = contact.contactJid;
    self.nickName = contact.nickName;
    self.fullName = contact.fullName;
    self.subscription = contact.subscription;
    self.ask = contact.ask;
    self.accountId = contact.accountId;
    self.groupSubject = contact.groupSubject;
    self.accountNickInGroup = contact.accountNickInGroup;
    self.mucType = contact.mucType;
    self.isGroup = contact.isGroup;
    self.isPinned = contact.isPinned;
    self.isBlocked = contact.isBlocked;
    self.statusMessage = contact.statusMessage;
    self.state = contact.state;
    self.unreadCount = contact.unreadCount;
    self.isActiveChat = contact.isActiveChat;
    self.isEncrypted = contact.isEncrypted;
    self.isMuted = contact.isEncrypted;
    self.lastMessageTime = contact.lastMessageTime;
}

-(BOOL) isSubscribed
{
    return [self.subscription isEqualToString:kSubBoth]
        || [self.subscription isEqualToString:kSubFrom];
}

+(MLContact*) createContactFromJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    assert(jid != nil);
    assert(accountNo != nil && accountNo.intValue >= 0);
    // MLContact* contact = [MLContact contactFromDictionary:[[DataLayer sharedInstance] dictForUsername:jid forAccount:accountNo]];
    NSDictionary* contactDict = [[DataLayer sharedInstance] contactDictionaryForUsername:jid forAccount:accountNo];
    
    // check if we know this contact and return a dummy one if not
    if(contactDict == nil)
    {
        DDLogInfo(@"Returning dummy MLContact for %@ on accountNo %@", jid, accountNo);
        return [self contactFromDictionary:@{
            @"buddy_name": jid.lowercaseString,
            @"nick_name": @"",
            @"full_name": @"",
            @"subscription": kSubNone,
            @"ask": @"",
            @"account_id": accountNo,
            //@"muc_subject": nil,
            //@"muc_nick": nil,
            @"Muc": @NO,
            @"pinned": @NO,
            @"blocked": @NO,
            @"encrypt": @NO,
            @"muted": @NO,
            @"status": @"",
            @"state": @"offline",
            @"count": @0,
            @"isActiveChat": @NO,
        }];
    }
    else
        return [self contactFromDictionary:contactDict];
}

@end
