//
//  MLChannelContact.m
//  monalxmpp
//
//  Created by admin on 03.12.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/MLChannelContact.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLMessage.h>

static NSMutableDictionary* _singletonCache;

@interface MLChannelContact ()
{
    NSString* _ownOccupantId;
    UIImage* _avatar;
}
@property (nonatomic, assign) BOOL isSelf;
@property (nonatomic) NSString* nick;
@property (nonatomic) NSString* occupantId;
@property (nonatomic) MLContact* mucContact;
@end

@implementation MLChannelContact

+(void) initialize
{
    _singletonCache = [NSMutableDictionary new];
}

+(MLChannelContact*) createChannelContactFromOccupantId:(NSString*) occupantId withNick:(NSString*) nick inMuc:(MLContact*) mucContact
{
    MLAssert(occupantId != nil, @"occupantId must not be nil");
    MLAssert(mucContact != nil, @"mucContact must not be nil");
    
    NSString* cacheKey = [NSString stringWithFormat:@"%@|%@|%@", occupantId, mucContact.contactJid, mucContact.accountID];
    @synchronized(_singletonCache) {
        if(_singletonCache[cacheKey] != nil)
        {
            MLChannelContact* obj = ((WeakContainer*)_singletonCache[cacheKey]).obj;
            if(obj != nil)
                return obj;
            else
                [_singletonCache removeObjectForKey:cacheKey];
        }
        
        MLChannelContact* retval = [MLChannelContact new];
        retval.occupantId = occupantId;
        retval.mucContact = mucContact;
        retval.nick = nick;
        retval->_ownOccupantId = [[DataLayer sharedInstance] getOwnOccupantIdForMuc:mucContact.contactJid onAccountID:mucContact.accountID];
        
        _singletonCache[cacheKey] = [[WeakContainer alloc] initWithObj:retval];
        return retval;
    }
}

-(instancetype) init
{
    self = [super init];
    //watch for all sorts of changes and update our singleton dynamically
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleParticipantUpdate:) name:kMonalMucParticipantsAndMembersUpdated object:nil];
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.occupantId forKey:@"occupantId"];
    [coder encodeObject:self.mucContact forKey:@"mucContact"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    //only decode whats needed to access/create the right singleton object.
    //decoding into a temporary object that will be discarded by the decoder
    //once awakeAfterUsingCoder returns a new object
    self = [self init];
    self.occupantId = [coder decodeObjectForKey:@"occupantId"];
    self.mucContact = [coder decodeObjectForKey:@"mucContact"];
    NSDictionary* participantInfo = [[DataLayer sharedInstance] getParticipantForOccupant:self.occupantId inRoom:self.mucContact.contactJid forAccountID:self.mucContact.accountID];
    if(participantInfo != nil)
        self.nick = participantInfo[@"room_nick"];
    else
        self.nick = self.occupantId;        //fallback
    return self;
}

//make sure this singleton remains a singleton, even after decoding
-(instancetype) awakeAfterUsingCoder:(NSCoder*) coder
{
    return [[self class] createChannelContactFromOccupantId:self.occupantId withNick:self.nick inMuc:self.mucContact];
}

-(void) handleParticipantUpdate:(NSNotification*) notification
{
    MLContact* contact = notification.userInfo[@"contact"];
    if([self.mucContact isEqual:contact])
    {
        NSDictionary* participantInfo = [[DataLayer sharedInstance] getParticipantForOccupant:self.occupantId inRoom:self.mucContact.contactJid forAccountID:self.mucContact.accountID];
        if(participantInfo != nil)
            self.nick = participantInfo[@"room_nick"];
        else
            self.nick = self.occupantId;        //fallback (should never happen when receiving this notification)
    }
}

-(NSString*) contactDisplayName
{
    return self.nick;
}

+(NSSet*) keyPathsForValuesAffectingContactDisplayName
{
    return [NSSet setWithObjects:@"nick", nil];
}

-(BOOL) isSelf
{
    return [self.occupantId isEqualToString:self->_ownOccupantId];
}

+(NSSet*) keyPathsForValuesAffectingIsSelf
{
    return [NSSet setWithObjects:@"occupantId", nil];
}

-(xmpp* _Nullable) account
{
    return [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.mucContact.accountID];
}

+(NSSet*) keyPathsForValuesAffectingAccount
{
    return [NSSet setWithObjects:@"mucContact.accountID", nil];
}

-(UIImage*) avatar
{
    return nil;
//     // return already cached image
//     if(_avatar != nil)
//         return _avatar;
//     // load avatar from MLImageManager (use self.avatar instead of _avatar to make sure KVO works properly)
//     self.avatar = [[MLImageManager sharedInstance] getIconForContact:self];
//     return _avatar;
}

+(NSSet*) keyPathsForValuesAffectingAvatar
{
    //nick is used for fallback avatar generation
    return [NSSet setWithObjects:@"nick", nil];
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
    return NO;
//     return [[MLImageManager sharedInstance] hasIconForContact:self];
}

// +(NSSet*) keyPathsForValuesAffectingHasAvatar
// {
//     return [NSSet setWithObjects:@"", nil];
// }

-(BOOL) isEqualToMessage:(MLMessage*) message
{
    return message != nil &&
           [self.occupantId isEqualToString:message.occupantId] &&
           [self.mucContact isEqual:message.contact];
}

-(BOOL) isEqualToContact:(id<MLContactProtocol>) contact
{
    if(contact == nil)
        return NO;
    if([contact isKindOfClass:[MLContact class]])
        return [self.mucContact.contactJid isEqualToString:((MLContact*)contact).contactJid] &&
            self.mucContact.accountID.intValue == ((MLContact*)contact).accountID.intValue;
    else if([contact isKindOfClass:[MLChannelContact class]])
        return [self.occupantId isEqualToString:((MLChannelContact*)contact).occupantId] &&
            [self.mucContact isEqualToContact:((MLChannelContact*)contact).mucContact];
    else
        MLAssert(NO, @"Can not check equality for unknown MLContactProtocol object", (@{@"self": self, @"contact": contact}));
}

-(BOOL) isEqual:(id _Nullable) object
{
    if(self == object)
        return YES;
    else if([object conformsToProtocol:@protocol(MLContactProtocol)])
        return [self isEqualToContact:(MLContact*)object];
    else if([object isKindOfClass:[MLMessage class]])
        return [self isEqualToMessage:(MLMessage*)object];
    else
        return NO;
}

-(NSUInteger) hash
{
    return [self.occupantId hash] ^ [self.mucContact hash];
}

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@|%@|%@", self.occupantId, self.mucContact.contactJid, self.mucContact.accountID];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@<%@> in muc: %@", self.occupantId, self.nick, self.mucContact];
}

@end
