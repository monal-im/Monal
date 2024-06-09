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
#import "MLVoIPProcessor.h"
#import "MonalAppDelegate.h"
#import "MLMucProcessor.h"

@import Intents;

NSString* const kSubBoth = @"both";
NSString* const kSubNone = @"none";
NSString* const kSubTo = @"to";
NSString* const kSubFrom = @"from";
NSString* const kSubRemove = @"remove";
NSString* const kAskSubscribe = @"subscribe";

static NSMutableDictionary* _singletonCache;

@interface MLContact ()
{
    NSInteger _unreadCount;
    monal_void_block_t _cancelNickChange;
    monal_void_block_t _cancelFullNameChange;
    UIImage* _avatar;
}
@property (nonatomic, assign) BOOL isSelfChat;
@property (nonatomic, assign) BOOL isInRoster;
@property (nonatomic, assign) BOOL isSubscribedTo;
@property (nonatomic, assign) BOOL isSubscribedFrom;
@property (nonatomic, assign) BOOL hasIncomingContactRequest;

@property (nonatomic, strong) NSNumber* accountId;
@property (nonatomic, strong) NSString* contactJid;
@property (nonatomic, strong) NSString* fullName;
@property (nonatomic, strong) NSString* nickName;

@property (nonatomic, strong) NSDate* _Nullable lastInteractionTime;

@property (nonatomic, assign) NSInteger unreadCount;

@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isMuted;
@property (nonatomic, assign) BOOL isActiveChat;

@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, strong) NSString* groupSubject;
@property (nonatomic, strong) NSString* mucType;
@property (nonatomic, strong) NSString* accountNickInGroup;
@property (nonatomic, assign) BOOL isMentionOnly;

@property (nonatomic, strong) NSString* subscription;
@property (nonatomic, strong) NSString* ask;

@property (nonatomic, strong) NSString* contactDisplayName;
@end

@implementation MLContact

+(void) initialize
{
    _singletonCache = [NSMutableDictionary new];
}

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
    NSString* displayName = accountDic[kRosterName];
    DDLogVerbose(@"Own nickname in accounts table %@: '%@'", account.accountNo, displayName);
    if(!displayName || !displayName.length)
    {
        // default is local part, see https://docs.modernxmpp.org/client/design/#contexts
        NSDictionary* jidParts = [HelperTools splitJid:account.connectionProperties.identity.jid];
        displayName = jidParts[@"node"];
    }
    DDLogVerbose(@"Calculated ownDisplayName for '%@': %@", account.connectionProperties.identity.jid, displayName);
    return nilDefault(displayName, @"");
}

+(MLContact*) createContactFromDatabaseWithJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo
{
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
            @"lastInteraction": nilWrapper(nil),
        }];
    }
    else
        return [self contactFromDictionary:contactDict];
}

+(MLContact*) createContactFromJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo
{
    MLAssert(jid != nil, @"jid must not be nil");
    MLAssert(accountNo != nil && accountNo.intValue >= 0, @"accountNo must not be nil and > 0");
    
    NSString* cacheKey = [NSString stringWithFormat:@"%@|%@", accountNo, jid];
    @synchronized(_singletonCache) {
        if(_singletonCache[cacheKey] != nil)
        {
            if(((WeakContainer*)_singletonCache[cacheKey]).obj != nil)
                return ((WeakContainer*)_singletonCache[cacheKey]).obj;
            else
                [_singletonCache removeObjectForKey:cacheKey];
        }
        
        MLContact* retval = [self createContactFromDatabaseWithJid:jid andAccountNo:accountNo];
        
        _singletonCache[cacheKey] = [[WeakContainer alloc] initWithObj:retval];
        return retval;
    }
}

-(instancetype) init
{
    self = [super init];
    //watch for all sorts of changes and update our singleton dynamically
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleLastInteractionTimeUpdate:) name:kMonalLastInteractionUpdatedNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBlockListRefresh:) name:kMonalBlockListRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kMonalRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRemoved object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMucSubjectChange:) name:kMonalMucSubjectChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnreadCount) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnreadCount) name:kMonalDeletedMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnreadCount) name:kMLMessageSentToContact object:nil];
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleLastInteractionTimeUpdate:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    NSNumber* notificationAccountNo = data[@"accountNo"];
    
    if(![self.contactJid isEqualToString:data[@"jid"]] || self.accountId.intValue != notificationAccountNo.intValue)
        return;     // ignore other accounts or contacts
    if(data[@"lastInteraction"] == nil)
        return;     // ignore typing notifications
    
    //this will be nil if "urn:xmpp:idle:1" is not supported by any of the contact's devices
    DDLogVerbose(@"Updating lastInteractionTime=%@ of %@", data[@"lastInteraction"], self);
    self.lastInteractionTime = nilExtractor(data[@"lastInteraction"]);
}

-(void) handleBlockListRefresh:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    NSNumber* notificationAccountNo = data[@"accountNo"];
    if(self.accountId.intValue != notificationAccountNo.intValue)
        return;         // ignore other accounts
    long blockingType = [[DataLayer sharedInstance] isBlockedContact:self];
    self.isBlocked = blockingType == kBlockingMatchedNodeHost;
    DDLogInfo(@"Updated contact %@ to blocking state %ld => isBlocked=%@", self, blockingType, bool2str(self.isBlocked));
}

-(void) handleContactRefresh:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLContact* contact = data[@"contact"];
    if(![self.contactJid isEqualToString:contact.contactJid] || self.accountId.intValue != contact.accountId.intValue)
        return;     // ignore other accounts or contacts
    [self refresh];
    [self updateUnreadCount];
    //only handle avatar updates if the property was already used and the old avatar is cached in this contact
    if(_avatar != nil)
    {
        UIImage* newAvatar = [[MLImageManager sharedInstance] getIconForContact:self];
        if(newAvatar != self->_avatar)
        {
            DDLogDebug(@"Setting new avatar for %@", self);
            self.avatar = newAvatar;            //use self.avatar instead of _avatar to make sure KVO works properly
        }
    }
}

-(void) handleMucSubjectChange:(NSNotification*) notification
{
    xmpp* account = notification.object;
    NSString* room = notification.userInfo[@"room"];
    NSString* subject = notification.userInfo[@"subject"];
    if(![self.contactJid isEqualToString:room] || self.accountId.intValue != account.accountNo.intValue)
        return;     // ignore other accounts or contacts
    self.groupSubject = nilDefault(subject, @"");
}

-(void) refresh
{
    [self updateWithContact:[[self class] createContactFromDatabaseWithJid:self.contactJid andAccountNo:self.accountId]];
}

-(void) updateUnreadCount
{
    _unreadCount = -1;      // mark it as "uncached" --> will be recalculated on next access
}

-(NSString*) contactDisplayNameWithFallback:(NSString* _Nullable) fallbackName;
{
    return [self contactDisplayNameWithFallback:fallbackName andSelfnotesPrefix:YES];
}
    
-(NSString*) contactDisplayNameWithFallback:(NSString* _Nullable) fallbackName andSelfnotesPrefix:(BOOL) hasSelfnotesPrefix
{
    DDLogVerbose(@"Calculating contact display name...");
    NSString* displayName;
    if(!self.isSelfChat)
    {
        if(fallbackName == nil)
        {
            //default is local part, see https://docs.modernxmpp.org/client/design/#contexts
            NSDictionary* jidParts = [HelperTools splitJid:self.contactJid];
            fallbackName = jidParts[@"host"];
            if(jidParts[@"node"] != nil)
                fallbackName = jidParts[@"node"];
        }
        
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
            DDLogVerbose(@"Using fallback: %@", fallbackName);
            displayName = fallbackName;
        }
    }
    else
    {
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
        if(hasSelfnotesPrefix)
        {
            //add "Note to self: " prefix for selfchats
            if([[DataLayer sharedInstance] enabledAccountCnts].intValue > 1)
                displayName = [NSString stringWithFormat:NSLocalizedString(@"Notes to self: %@", @""), [[self class] ownDisplayNameForAccount:account]];
            else
                displayName = NSLocalizedString(@"Notes to self", @"");
        }
        else
            displayName = [[self class] ownDisplayNameForAccount:account];
    }
    
    DDLogVerbose(@"Calculated contactDisplayName for '%@': %@", self.contactJid, displayName);
    MLAssert(displayName != nil, @"Display name should never be nil!", (@{
        @"jid": nilWrapper(self.contactJid),
        @"nickName": nilWrapper(self.nickName),
        @"fullName": nilWrapper(self.fullName),
        @"fallbackName": nilWrapper(fallbackName)
    }));
    return displayName;
}

-(NSString*) contactDisplayName
{
    return [self contactDisplayNameWithFallback:nil];
}

+(NSSet*) keyPathsForValuesAffectingContactDisplayName
{
    return [NSSet setWithObjects:@"nickName", @"fullName", @"contactJid", nil];
}

-(NSString*) contactDisplayNameWithoutSelfnotesPrefix
{
    return [self contactDisplayNameWithFallback:nil andSelfnotesPrefix:NO];
}

+(NSSet*) keyPathsForValuesAffectingContactDisplayNameWithoutSelfnotesPrefix
{
    return [NSSet setWithObjects:@"nickName", @"fullName", @"contactJid", nil];
}

-(NSString*) nickNameView
{
    return nilDefault(self.nickName, @"");
}

-(void) setNickNameView:(NSString*) name
{
    MLAssert(!self.isGroup, @"Using nickNameView only allowed for 1:1 contacts!", (@{@"contact": self}));
    if([self.nickName isEqualToString:name] || name == nil)
        return;             //no change at all
    self.nickName = name;
    // abort old change timer and start a new one
    if(_cancelNickChange)
        _cancelNickChange();
    // delay changes because we don't want to update the roster on our server too often while typing
    _cancelNickChange = createTimer(2.0, (^{
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
        [account updateRosterItem:self withName:self.nickName];
    }));
}

+(NSSet*) keyPathsForValuesAffectingNickNameView
{
    return [NSSet setWithObjects:@"nickName", nil];
}

-(NSString*) fullNameView
{
    return nilDefault(self.fullName, @"");
}

-(void) setFullNameView:(NSString*) name
{
    MLAssert(self.isGroup, @"Using fullNameView only allowed for mucs!", (@{@"contact": self}));
    if([self.fullName isEqualToString:name] || name == nil)
        return;             //no change at all
    self.fullName = name;
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    [[DataLayer sharedInstance] setFullName:self.fullName forContact:self.contactJid andAccount:account.accountNo];
    // abort old change timer and start a new one
    if(_cancelFullNameChange)
        _cancelFullNameChange();
    // delay changes because we don't want to update the roster on our server too often while typing
    _cancelFullNameChange = createTimer(2.0, (^{
        [account.mucProcessor changeNameOfMuc:self.contactJid to:self.fullName];
    }));
}

+(NSSet*) keyPathsForValuesAffectingFullNameView
{
    return [NSSet setWithObjects:@"fullName", nil];
}

-(UIImage*) avatar
{
    // return already cached image
    if(_avatar != nil)
        return _avatar;
    // load avatar from MLImageManager (use self.avatar instead of _avatar to make sure KVO works properly)
    self.avatar = [[MLImageManager sharedInstance] getIconForContact:self];
    return _avatar;
}

-(void) setAvatar:(UIImage*) avatar
{
    if(avatar != nil)
        _avatar = avatar;
    else
        _avatar = [UIImage new];           //empty dummy image, to not save nil (should never happen, MLImageManager has default images)
}

-(BOOL) hasAvatar
{
    return [[MLImageManager sharedInstance] hasIconForContact:self];
}

-(BOOL) isSelfChat
{
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    return [self.contactJid isEqualToString:account.connectionProperties.identity.jid];
}

+(NSSet*) keyPathsForValuesAffectingIsSelfChat
{
    return [NSSet setWithObjects:@"contactJid", @"accountId", nil];
}

-(BOOL) isInRoster
{
    // mucs have a subscription of both (ensured by the datalayer)
    return [self.subscription isEqualToString:kSubBoth]
        || [self.subscription isEqualToString:kSubTo]
        || [self.ask isEqualToString:kAskSubscribe];
}

+(NSSet*) keyPathsForValuesAffectingIsInRoster
{
    return [NSSet setWithObjects:@"subscription", @"ask", nil];
}

-(BOOL) isSubscribedTo
{
    return [self.subscription isEqualToString:kSubBoth]
        || [self.subscription isEqualToString:kSubTo];
}

+(NSSet*) keyPathsForValuesAffectingIsSubscribedTo
{
    return [NSSet setWithObjects:@"subscription", nil];
}

-(BOOL) isSubscribedFrom
{
    return [self.subscription isEqualToString:kSubBoth]
        || [self.subscription isEqualToString:kSubFrom];
}

+(NSSet*) keyPathsForValuesAffectingIsSubscribedFrom
{
    return [NSSet setWithObjects:@"subscription", nil];
}

-(BOOL) isSubscribedBoth
{
    return [self.subscription isEqualToString:kSubBoth];
}

+(NSSet*) keyPathsForValuesAffectingIsSubscribedBoth
{
    return [NSSet setWithObjects:@"subscription", nil];
}

-(BOOL) hasIncomingContactRequest
{
    return self.isGroup == NO && [[DataLayer sharedInstance] hasContactRequestForContact:self];
}

+(NSSet*) keyPathsForValuesAffectingHasIncomingContactRequest
{
    return [NSSet setWithObjects:@"isGroup", nil];
}

-(BOOL) hasOutgoingContactRequest
{
    return self.isGroup == NO && [self.ask isEqualToString:kAskSubscribe];
}

+(NSSet*) keyPathsForValuesAffectingHasOutgoingContactRequest
{
    return [NSSet setWithObjects:@"isGroup", @"ask", nil];
}

// this will cache the unread count on first access
-(NSInteger) unreadCount
{
    if(_unreadCount == -1)
        _unreadCount = [[[DataLayer sharedInstance] countUserUnreadMessages:self.contactJid forAccount:self.accountId] integerValue];
    return _unreadCount;
}

-(void) removeShareInteractions
{
    [INInteraction deleteInteractionsWithIdentifiers:@[[NSString stringWithFormat:@"%@|%@", self.accountId, self.contactJid]] completion:^(NSError* error) {
        if(error != nil)
            DDLogError(@"Could not delete all SiriKit interactions: %@", error);
    }];
}

-(void) toggleMute:(BOOL) mute
{
    if(self.isMuted == mute)
        return;
    if(mute)
        [[DataLayer sharedInstance] muteContact:self];
    else
        [[DataLayer sharedInstance] unMuteContact:self];
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
    if(self.isGroup == NO)
    {
        NSSet* knownDevices = [account.omemo knownDevicesForAddressName:self.contactJid];
        if(!self.isEncrypted && encrypt && knownDevices.count == 0)
        {
            // request devicelist again
            [account.omemo subscribeAndFetchDevicelistIfNoSessionExistsForJid:self.contactJid];
            return NO;
        }
    }
    else if([self.mucType isEqualToString:@"group"] == NO)
    {
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
    if(account == nil)
        return;
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{@"contact":self, @"pinningChanged": @YES}];
}

-(BOOL) toggleBlocked:(BOOL) block
{
    if(self.isBlocked == block)
        return YES;
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountId];
    if(account == nil)
        return NO;
    if(!account.connectionProperties.supportsBlocking)
        return NO;
    [[MLXMPPManager sharedInstance] block:block contact:self];
    return YES;
}

-(void) removeFromRoster
{
    [[MLXMPPManager sharedInstance] removeContact:self];
    [self removeShareInteractions];
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
    self = [self init];
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
    updateIfIdNotEqual(self.contactJid, contact.contactJid);
    updateIfIdNotEqual(self.nickName, contact.nickName);
    updateIfIdNotEqual(self.fullName, contact.fullName);
    updateIfIdNotEqual(self.subscription, contact.subscription);
    updateIfIdNotEqual(self.ask, contact.ask);
    updateIfIdNotEqual(self.accountId, contact.accountId);
    updateIfIdNotEqual(self.groupSubject, contact.groupSubject);
    updateIfIdNotEqual(self.accountNickInGroup, contact.accountNickInGroup);
    updateIfPrimitiveNotEqual(self.isGroup, contact.isGroup);
    if(self.isGroup)
        updateIfIdNotEqual(self.mucType, nilDefault(contact.mucType, @"channel"));
    updateIfPrimitiveNotEqual(self.isMentionOnly, contact.isMentionOnly);
    updateIfPrimitiveNotEqual(self.isPinned, contact.isPinned);
    updateIfPrimitiveNotEqual(self.isBlocked, contact.isBlocked);
    updateIfIdNotEqual(self.statusMessage, contact.statusMessage);
    updateIfIdNotEqual(self.state, contact.state);
    updateIfPrimitiveNotEqual(self->_unreadCount, contact->_unreadCount);
    updateIfPrimitiveNotEqual(self.isActiveChat, contact.isActiveChat);
    updateIfPrimitiveNotEqual(self.isEncrypted, contact.isEncrypted);
    updateIfPrimitiveNotEqual(self.isMuted, contact.isMuted);
    //don't update lastInteractionTime from contact, we dynamically update ourselves by handling kMonalLastInteractionUpdatedNotice
    //updateIfIdNotEqual(self.lastInteractionTime, contact.lastInteractionTime);
}

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return message != nil &&
           [self.contactJid isEqualToString:message.buddyName] &&
           self.accountId.intValue == message.accountId.intValue;
}

-(BOOL) isEqualToContact:(MLContact*) contact
{
    return contact != nil &&
           [self.contactJid isEqualToString:contact.contactJid] &&
           self.accountId.intValue == contact.accountId.intValue;
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

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@|%@", self.accountId, self.contactJid];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@: %@ (%@) %@%@%@, kSub=%@", self.accountId, self.contactJid, self.isGroup ? self.mucType : @"1:1", self.isInRoster ? @"inRoster" : @"not(inRoster)", self.hasIncomingContactRequest ? @"[incomingContactRequest]" : @"", self.hasOutgoingContactRequest ? @"[outgoingContactRequest]" : @"", self.subscription];
}

+(MLContact*) contactFromDictionary:(NSDictionary*) dic
{
    MLContact* contact = [MLContact new];
    contact.contactJid = [dic objectForKey:@"buddy_name"];
    contact.nickName = nilDefault([dic objectForKey:@"nick_name"], @"");
    contact.fullName = nilDefault([dic objectForKey:@"full_name"], @"");
    contact.subscription = nilDefault([dic objectForKey:@"subscription"], kSubNone);
    contact.ask = nilDefault([dic objectForKey:@"ask"], @"");
    contact.accountId = [dic objectForKey:@"account_id"];
    contact.groupSubject = nilDefault([dic objectForKey:@"muc_subject"], @"");
    contact.accountNickInGroup = nilDefault([dic objectForKey:@"muc_nick"], @"");
    contact.mucType = [dic objectForKey:@"muc_type"];
    contact.isGroup = [[dic objectForKey:@"Muc"] boolValue];
    if(contact.isGroup  && !contact.mucType)
        contact.mucType = @"channel";       //default value
    contact.mucType = nilDefault(contact.mucType, @"");
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
    contact.lastInteractionTime = nilExtractor([dic objectForKey:@"lastInteraction"]);        //no default needed, already done in DataLayer
    contact->_avatar = nil;
    return contact;
}

@end
