//
//  MLContact.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLContact.h"
#import "MLMessage.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "xmpp.h"
#import "MLXMPPManager.h"
#import "MLOMEMO.h"
#import "MLNotificationQueue.h"
#import "MLImageManager.h"

NSString *const kSubBoth=@"both";
NSString *const kSubNone=@"none";
NSString *const kSubTo=@"to";
NSString *const kSubFrom=@"from";
NSString *const kSubRemove=@"remove";
NSString *const kAskSubscribe=@"subscribe";

@interface MLContact ()
{
    NSInteger _unreadCount;
    monal_void_block_t _cancelNickChange;
    UIImage* _avatar;
}
@end

@implementation MLContact

+(MLContact*) makeDummyContact:(int) type
{
    if(type == 1)
    {
        return [self contactFromDictionary:@{
            @"buddy_name": @"user@example.org",
            @"nick_name": @"",
            @"full_name": @"",
            @"subscription": kSubBoth,
            @"ask": @"",
            @"account_id": @1,
            //@"muc_subject": nil,
            //@"muc_nick": nil,
            @"Muc": @NO,
            @"pinned": @NO,
            @"blocked": @NO,
            @"encrypt": @NO,
            @"muted": @NO,
            @"status": @"",
            @"state": @"online",
            @"count": @1,
            @"isActiveChat": @YES,
            @"lastInteraction": [[NSDate date] initWithTimeIntervalSince1970:0],
        }];
    }
    else if(type == 2)
    {
        return [self contactFromDictionary:@{
            @"buddy_name": @"group@example.org",
            @"nick_name": @"",
            @"full_name": @"Die coole Gruppe",
            @"subscription": kSubBoth,
            @"ask": @"",
            @"account_id": @1,
            //@"muc_subject": nil,
            @"muc_nick": @"my_group_nick",
            @"muc_type": @"group",
            @"Muc": @YES,
            @"pinned": @NO,
            @"blocked": @NO,
            @"encrypt": @NO,
            @"muted": @NO,
            @"status": @"",
            @"state": @"online",
            @"count": @2,
            @"isActiveChat": @YES,
            @"lastInteraction": [[NSDate date] initWithTimeIntervalSince1970:1640153174],
        }];
    }
    else if(type == 3)
    {
        return [self contactFromDictionary:@{
            @"buddy_name": @"channel@example.org",
            @"nick_name": @"",
            @"full_name": @"Der coolste Channel überhaupt",
            @"subscription": kSubBoth,
            @"ask": @"",
            @"account_id": @1,
            //@"muc_subject": nil,
            @"muc_nick": @"my_channel_nick",
            @"muc_type": @"channel",
            @"Muc": @YES,
            @"pinned": @NO,
            @"blocked": @NO,
            @"encrypt": @NO,
            @"muted": @NO,
            @"status": @"",
            @"state": @"online",
            @"count": @3,
            @"isActiveChat": @YES,
            @"lastInteraction": [[NSDate date] initWithTimeIntervalSince1970:1640157074],
        }];
    }
    else
    {
        return [self contactFromDictionary:@{
            @"buddy_name": @"user2@example.org",
            @"nick_name": @"",
            @"full_name": @"Zweiter User mit Roster Name",
            @"subscription": kSubBoth,
            @"ask": @"",
            @"account_id": @1,
            //@"muc_subject": nil,
            //@"muc_nick": nil,
            @"Muc": @NO,
            @"pinned": @NO,
            @"blocked": @NO,
            @"encrypt": @NO,
            @"muted": @NO,
            @"status": @"",
            @"state": @"online",
            @"count": @4,
            @"isActiveChat": @YES,
            @"lastInteraction": [[NSDate date] initWithTimeIntervalSince1970:1640157174],
        }];
    }
}

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
    return nilDefault(displayName, @"");
}

+(MLContact*) createContactFromJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    assert(jid != nil);
    assert(accountNo != nil && accountNo.intValue >= 0);
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
            @"mentionOnly": @NO,
            @"pinned": @NO,
            @"blocked": @NO,
            @"encrypt": @NO,
            @"muted": @NO,
            @"status": @"",
            @"state": @"offline",
            @"count": @0,
            @"isActiveChat": @NO,
            @"lastInteraction": [[NSDate date] initWithTimeIntervalSince1970:0],
        }];
    }
    else
        return [self contactFromDictionary:contactDict];
}

-(instancetype) init
{
    self = [super init];
    // watch for changes in lastInteractionTime and update dynamically
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleLastInteractionTimeUpdate:) name:kMonalLastInteractionUpdatedNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBlockListRefresh:) name:kMonalBlockListRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRefresh object:nil];
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleLastInteractionTimeUpdate:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    if(![self.contactJid isEqualToString:data[@"jid"]] || ![self.accountId isEqualToString:data[@"accountNo"]])
        return;     // ignore other accounts or contacts
    if(data[@"lastInteraction"] == nil)
        return;     // ignore typing notifications
    self.lastInteractionTime = data[@"lastInteraction"];
    //self.lastInteractionTime = [[DataLayer sharedInstance] lastInteractionOfJid:self.contactJid forAccountNo:self.accountId];
}

-(void) handleBlockListRefresh:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    if(![self.accountId isEqualToString:data[@"accountNo"]])
        return;         // ignore other accounts
    self.isBlocked = [[DataLayer sharedInstance] isBlockedJid:self.contactJid withAccountNo:self.accountId] == kBlockingMatchedNodeHost;
}

-(void) handleContactRefresh:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLContact* contact = data[@"contact"];
    if(![self.contactJid isEqualToString:contact.contactJid] || ![self.accountId isEqualToString:contact.accountId])
        return;     // ignore other accounts or contacts
    [self updateWithContact:contact];
    //only handle avatar updates if the property was already used and the old avatar is cached in this contact
    if(_avatar != nil)
    {
        UIImage* newAvatar = [[MLImageManager sharedInstance] getIconForContact:self];
        if(newAvatar != self->_avatar)
            self.avatar = newAvatar;            //use self.avatar instead of _avatar to make sure KVO works properly
    }
}

-(void) refresh
{
    [self updateWithContact:[MLContact createContactFromJid:self.contactJid andAccountNo:self.accountId]];
}

-(void) updateUnreadCount
{
    _unreadCount = -1;      // mark it as "uncached" --> will be recalculated on next access
}

-(NSString*) contactDisplayName
{
    DDLogVerbose(@"Calculating contact display name...");
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
        if(jidParts[@"node"] != nil)
            displayName = jidParts[@"node"];
        else
            displayName = jidParts[@"host"];

        DDLogVerbose(@"Using default: %@", displayName);
    }
    DDLogVerbose(@"Calculated contactDisplayName for '%@': %@", self.contactJid, displayName);
    return nilDefault(displayName, @"");
}

+(NSSet*) keyPathsForValuesAffectingContactDisplayName
{
    return [NSSet setWithObjects:@"nickName", @"fullName", @"contactJid", nil];
}

-(NSString*) nickNameView
{
    return nilDefault(self.nickName, @"");
}

-(void) setNickNameView:(NSString*) name
{
    if([self.nickName isEqualToString:name] || name == nil)
        return;             //no change at all
    self.nickName = name;
    // abort old change timer and start a new one
    if(_cancelNickChange)
        _cancelNickChange();
    // delay changes because we don't want to update the roster on our server too often while typing
    _cancelNickChange = createTimer(1.0, (^{
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
        [account updateRosterItem:self.contactJid withName:self.nickName];
    }));
}

+(NSSet*) keyPathsForValuesAffectingNickNameView
{
    return [NSSet setWithObjects:@"nickName", nil];
}

-(UIImage*) avatar
{
    //return already cached image
    if(_avatar != nil)
        return _avatar;
    //load avatar from MLImageManager (use self.avatar instead of _avatar to make sure KVO works properly)
    self.avatar = [[MLImageManager sharedInstance] getIconForContact:self];
    return _avatar;
}

-(void) setAvatar:(UIImage*) avatar
{
    if(avatar != nil)
        _avatar = avatar;
    else
        _avatar = [[UIImage alloc] init];           //empty dummy image, to not save nil (should never happen, MLImageManager has default images)
}

-(BOOL) isSubscribed
{
    return [self.subscription isEqualToString:kSubBoth]
        || [self.subscription isEqualToString:kSubTo];
}

-(BOOL) isInRoster
{
    return [self.subscription isEqualToString:kSubBoth]
        || [self.subscription isEqualToString:kSubTo]
        || [self.ask isEqualToString:kAskSubscribe];
}

// this will cache the unread count on first access
-(NSInteger) unreadCount
{
    if(_unreadCount == -1)
        _unreadCount = [[[DataLayer sharedInstance] countUserUnreadMessages:self.contactJid forAccount:self.accountId] integerValue];
    return _unreadCount;
}

-(void) toggleMute:(BOOL) mute
{
    if(self.isMuted == mute)
        return;
    if(mute)
        [[DataLayer sharedInstance] muteJid:self.contactJid onAccount:self.accountId];
    else
        [[DataLayer sharedInstance] unMuteJid:self.contactJid onAccount:self.accountId];
    self.isMuted = mute;
}

-(void) toggleMentionOnly:(BOOL) mentionOnly
{
    if(!self.isGroup || self.isMentionOnly == mentionOnly)
        return;
    if(mentionOnly)
        [[DataLayer sharedInstance] setMucAlertOnMentionOnly:self.contactJid onAccount:self.accountId];
    else
        [[DataLayer sharedInstance] setMucAlertOnAll:self.contactJid onAccount:self.accountId];
    self.isMentionOnly = mentionOnly;
}

-(BOOL) toggleEncryption:(BOOL) encrypt
{
#ifdef DISABLE_OMEMO
    return NO;
#else
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    if(account == nil || account.omemo == nil)
        return NO;
    NSArray* knownDevices = [account.omemo knownDevicesForAddressName:self.contactJid];
    if(!self.isEncrypted && encrypt && knownDevices.count == 0)
    {
        // request devicelist again
        [account.omemo queryOMEMODevices:self.contactJid];
        return NO;
    }
    
    if(self.isEncrypted == encrypt)
        return YES;
    
    if(encrypt)
        [[DataLayer sharedInstance] encryptForJid:self.contactJid andAccountNo:self.accountId];
    else
        [[DataLayer sharedInstance] disableEncryptForJid:self.contactJid andAccountNo:self.accountId];
    self.isEncrypted = encrypt;
    return YES;
#endif
}

-(void) resetOmemoSession
{
#ifndef DISABLE_OMEMO
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    if(account == nil || account.omemo == nil) {
        return;
    }
    [account.omemo clearAllSessionsForJid:self.contactJid];
#endif
}

-(void) togglePinnedChat:(BOOL) pinned
{
    if(self.isPinned == pinned)
        return;
    if(pinned)
        [[DataLayer sharedInstance] pinChat:self.accountId andBuddyJid:self.contactJid];
    else
        [[DataLayer sharedInstance] unPinChat:self.accountId andBuddyJid:self.contactJid];
    self.isPinned = pinned;
    // update active chats
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    if(account == nil) {
        return;
    }
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{@"contact":self, @"pinningChanged": @YES}];
}

-(BOOL) toggleBlocked:(BOOL) block
{
    if(self.isBlocked == block)
        return YES;
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    if(!account.connectionProperties.supportsBlocking)
        return NO;
    [[MLXMPPManager sharedInstance] blocked:block Jid:self];
    return YES;
}

-(void) removeFromRoster
{
    [[MLXMPPManager sharedInstance] removeContact:self];
}

-(void) addToRoster
{
    [[MLXMPPManager sharedInstance] addContact:self];
}

-(void) clearHistory
{
    [[DataLayer sharedInstance] clearMessagesWithBuddy:self.contactJid onAccount:self.accountId];
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
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
    [coder encodeBool:self.isMentionOnly forKey:@"isMentionOnly"];
    [coder encodeBool:self.isPinned forKey:@"isPinned"];
    [coder encodeBool:self.isBlocked forKey:@"isBlocked"];
    [coder encodeObject:self.statusMessage forKey:@"statusMessage"];
    [coder encodeObject:self.state forKey:@"state"];
    [coder encodeInteger:self->_unreadCount forKey:@"unreadCount"];
    [coder encodeBool:self.isActiveChat forKey:@"isActiveChat"];
    [coder encodeBool:self.isEncrypted forKey:@"isEncrypted"];
    [coder encodeBool:self.isMuted forKey:@"isMuted"];
    [coder encodeObject:self.lastInteractionTime forKey:@"lastInteractionTime"];
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
    self.isMentionOnly = [coder decodeBoolForKey:@"isMentionOnly"];
    self.isPinned = [coder decodeBoolForKey:@"isPinned"];
    self.isBlocked = [coder decodeBoolForKey:@"isBlocked"];
    self.statusMessage = [coder decodeObjectForKey:@"statusMessage"];
    self.state = [coder decodeObjectForKey:@"state"];
    self->_unreadCount = [coder decodeIntegerForKey:@"unreadCount"];
    self.isActiveChat = [coder decodeBoolForKey:@"isActiveChat"];
    self.isEncrypted = [coder decodeBoolForKey:@"isEncrypted"];
    self.isMuted = [coder decodeBoolForKey:@"isMuted"];
    self.lastInteractionTime = [coder decodeObjectForKey:@"lastInteractionTime"];
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
    self.isMentionOnly = contact.isMentionOnly;
    self.isPinned = contact.isPinned;
    self.isBlocked = contact.isBlocked;
    self.statusMessage = contact.statusMessage;
    self.state = contact.state;
    self->_unreadCount = contact->_unreadCount;
    self.isActiveChat = contact.isActiveChat;
    self.isEncrypted = contact.isEncrypted;
    self.isMuted = contact.isMuted;
    // don't update lastInteractionTime from contact, we dynamically update ourselves by handling kMonalLastInteractionUpdatedNotice
    // self.lastInteractionTime = contact.lastInteractionTime;
}

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return message != nil &&
           [self.contactJid isEqualToString:message.buddyName] &&
           [self.accountId isEqualToString:message.accountId];
}

-(BOOL) isEqualToContact:(MLContact*) contact
{
    return contact != nil &&
           [self.contactJid isEqualToString:contact.contactJid] &&
           [self.accountId isEqualToString:contact.accountId];
}

-(BOOL) isEqual:(id _Nullable) object
{
    if(object == nil || self == object)
        return YES;
    else if([object isKindOfClass:[MLContact class]])
        return [self isEqualToContact:(MLContact*)object];
    else if([object isKindOfClass:[MLMessage class]])
        return [self isEqualToMessage:(MLMessage*)object];
    else
        return NO;
}

-(NSUInteger) hash
{
    return [self.contactJid hash] ^ [self.accountId hash];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@: %@", self.accountId, self.contactJid];
}

+(MLContact*) contactFromDictionary:(NSDictionary*) dic
{
    MLContact* contact = [[MLContact alloc] init];
    contact.contactJid = [dic objectForKey:@"buddy_name"];
    contact.nickName = nilDefault([dic objectForKey:@"nick_name"], @"");
    contact.fullName = nilDefault([dic objectForKey:@"full_name"], @"");
    contact.subscription = nilDefault([dic objectForKey:@"subscription"], kSubNone);
    contact.ask = nilDefault([dic objectForKey:@"ask"], @"");
    contact.accountId = [NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
    contact.groupSubject = nilDefault([dic objectForKey:@"muc_subject"], @"");
    contact.accountNickInGroup = nilDefault([dic objectForKey:@"muc_nick"], @"");
    contact.mucType = [dic objectForKey:@"muc_type"];
    contact.isGroup = [[dic objectForKey:@"Muc"] boolValue];
    if(contact.isGroup  && !contact.mucType)
        contact.mucType = @"channel";       //default value
    contact.isMentionOnly = [[dic objectForKey:@"mentionOnly"] boolValue];
    contact.isPinned = [[dic objectForKey:@"pinned"] boolValue];
    contact.isBlocked = [[dic objectForKey:@"blocked"] boolValue];
    contact.statusMessage = nilDefault([dic objectForKey:@"status"], @"");
    contact.state = nilDefault([dic objectForKey:@"state"], @"online");
    contact->_unreadCount = -1;
    contact.isActiveChat = [[dic objectForKey:@"isActiveChat"] boolValue];
    contact.isEncrypted = [[dic objectForKey:@"encrypt"] boolValue];
    contact.isMuted = [[dic objectForKey:@"muted"] boolValue];
    // initial value comes from db, all other values get updated by our kMonalLastInteractionUpdatedNotice handler
    contact.lastInteractionTime = [dic objectForKey:@"lastInteraction"];        //no default needed, already done in DataLayer
    contact->_avatar = nil;
    return contact;
}

@end
