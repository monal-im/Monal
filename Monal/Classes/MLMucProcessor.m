//
//  MLMucProcessor.m
//  monalxmpp
//
//  Created by Thilo Molitor on 29.12.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MLConstants.h"
#import "MLMucProcessor.h"
#import "MLHandler.h"
#import "xmpp.h"
#import "DataLayer.h"
#import "XMPPDataForm.h"
#import "XMPPIQ.h"
#import "XMPPMessage.h"
#import "XMPPPresence.h"
#import "MLNotificationQueue.h"
#import "MLPubSub.h"
#import "MLPubSubProcessor.h"
#import "MLOMEMO.h"
#import "MLImageManager.h"

#define CURRENT_MUC_STATE_VERSION @6

@interface MLMucProcessor()
{
    __weak xmpp* _account;
    //persistent state
    NSObject* _stateLockObject;
    NSMutableDictionary* _roomFeatures;
    NSMutableDictionary* _joining;
    NSMutableSet* _firstJoin;
    NSDate* _lastPing;
    NSMutableSet* _noUpdateBookmarks;
    BOOL _hasFetchedBookmarks;
    //this won't be persisted because it is only for the ui
    NSMutableDictionary* _uiHandler;
}
@end

@implementation MLMucProcessor

-(id) initWithAccount:(xmpp*) account
{
    self = [super init];
    _account = account;
    _stateLockObject = [NSObject new];
    _roomFeatures = [NSMutableDictionary new];
    _joining = [NSMutableDictionary new];
    _firstJoin = [NSMutableSet new];
    _uiHandler = [NSMutableDictionary new];
    _lastPing = [NSDate date];
    _noUpdateBookmarks = [NSMutableSet new];
    _hasFetchedBookmarks = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleResourceBound:) name:kMLResourceBoundNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleCatchupDone:) name:kMonalFinishedCatchup object:nil];
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) setInternalState:(NSDictionary*) state
{
    //DDLogVerbose(@"Setting MUC state to: %@", state);
    
    //ignore state having wrong version code
    if(!state[@"version"] || ![state[@"version"] isEqual:CURRENT_MUC_STATE_VERSION])
    {
        DDLogDebug(@"Ignoring MUC state having wrong version: %@ != %@", state[@"version"], CURRENT_MUC_STATE_VERSION);
        return;
    }
    
    //extract state
    @synchronized(_stateLockObject) {
        _roomFeatures = [state[@"roomFeatures"] mutableCopy];
        _joining = [state[@"joining"] mutableCopy];
        _firstJoin = [state[@"firstJoin"] mutableCopy];
        _lastPing = state[@"lastPing"];
        _noUpdateBookmarks = [state[@"noUpdateBookmarks"] mutableCopy];
        _hasFetchedBookmarks = [state[@"hasFetchedBookmarks"] boolValue];
    }
}

-(NSDictionary*) getInternalState
{
    @synchronized(_stateLockObject) {
        NSDictionary* state = @{
            @"version": CURRENT_MUC_STATE_VERSION,
            @"roomFeatures": _roomFeatures,
            @"joining": _joining,
            @"firstJoin": _firstJoin,
            @"lastPing": _lastPing,
            @"noUpdateBookmarks": _noUpdateBookmarks,
            @"hasFetchedBookmarks": @(_hasFetchedBookmarks),
        };
        //DDLogVerbose(@"Returning MUC state: %@", state);
        return state;
    }
}

-(void) handleResourceBound:(NSNotification*) notification
{
    //this event will be called as soon as we are bound, but BEFORE mam catchup happens
    //NOTE: this event won't be called for smacks resumes!
    if(_account == ((xmpp*)notification.object))
    {
        @synchronized(_stateLockObject) {
            _roomFeatures = [NSMutableDictionary new];
            
            //make sure all idle timers get invalidated properly
            NSDictionary* joiningCopy = [_joining copy];
            for(NSString* room in joiningCopy)
                 [self removeRoomFromJoining:room];
            
            //don't clear _firstJoin and _noUpdateBookmarks to make sure half-joined mucs are still added to muc bookmarks
            
            //load all bookmarks 2 items as soon as our catchup is done (+notify only provides one/the last item)
            _hasFetchedBookmarks = NO;
        }
            
        //join MUCs from (current) muc_favorites db, the pending bookmarks fetch will join the remaining currently unknown mucs
        for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:_account.accountNo])
            [self join:entry[@"room"]];
    }
}

-(void) handleCatchupDone:(NSNotification*) notification
{
    //this event will be called as soon as mam OR smacks catchup on our account is done, it does not wait for muc mam catchups!
    if(_account == ((xmpp*)notification.object))
    {
        //fake incoming bookmarks push by pulling all bookmarks2 items (but only if we want to use bookmarks2 instead of old-style boommarks)
        if(!_hasFetchedBookmarks && _account.connectionProperties.supportsBookmarksCompat)
            [_account.pubsub fetchNode:@"urn:xmpp:bookmarks:1" from:_account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, bookmarks2Handler, $ID(type, @"publish"))];
    }
}

-(BOOL) isJoining:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return _joining[room] != nil;
    }
}

-(void) addUIHandler:(monal_id_block_t) handler forMuc:(NSString*) room
{
    //this will replace the old handler
    @synchronized(_stateLockObject) {
        _uiHandler[room] = handler;
    }
}

-(void) removeUIHandlerForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        [_uiHandler removeObjectForKey:room];
    }
}

-(monal_id_block_t) getUIHandlerForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return _uiHandler[room];
    }
}

-(void) processPresence:(XMPPPresence*) presenceNode
{
    //check for nickname conflict while joining and retry with underscore added to the end
    if([self isJoining:presenceNode.fromUser] && [presenceNode findFirst:@"/<type=error>/error/{urn:ietf:params:xml:ns:xmpp-stanzas}conflict"])
    {
        //load old nickname from db, add underscore and write it back to db so that it can be used by our next join
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:presenceNode.fromUser forAccount:_account.accountNo];
        nick = [NSString stringWithFormat:@"%@_", nick];
        [[DataLayer sharedInstance] initMuc:presenceNode.fromUser forAccountId:_account.accountNo andMucNick:nick];
        
        //try to join again
        DDLogInfo(@"Retrying muc join of %@ with new nick (appended underscore): %@", presenceNode.fromUser, nick);
        [self removeRoomFromJoining:presenceNode.fromUser];
        [self sendJoinPresenceFor:presenceNode.fromUser];
        return;
    }
    
    //check for all other errors
    if([presenceNode findFirst:@"/<type=error>"])
    {
        DDLogError(@"got muc error presence of %@!", presenceNode.fromUser);
        [self removeRoomFromJoining:presenceNode.fromUser];
        
        //delete muc from favorites table and update bookmarks
        if([self checkIfStillBookmarked:presenceNode.fromUser])
            [self deleteMuc:presenceNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
        
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Group/Channel error in %@", @""), presenceNode.fromUser] forMuc:presenceNode.fromUser withNode:presenceNode andIsSevere:YES];
        return;
    }
    
    //handle presences from muc bare jid
    if(presenceNode.fromResource == nil)
    {
        DDLogVerbose(@"Got muc presence from bare jid: %@", presenceNode.from);
        if([[DataLayer sharedInstance] isContactInList:presenceNode.fromUser forAccount:_account.accountNo])
        {
            //check vcard hash
            NSString* avatarHash = [presenceNode findFirst:@"{vcard-temp:x:update}x/photo#"];
            NSString* currentHash = [[DataLayer sharedInstance] getAvatarHashForContact:presenceNode.fromUser andAccount:_account.accountNo];
            DDLogVerbose(@"Checking if avatar hash in presence '%@' equals stored hash '%@'...", avatarHash, currentHash);
            if(avatarHash != nil && !(currentHash && [avatarHash isEqualToString:currentHash]))
            {
                DDLogInfo(@"Got new muc avatar hash '%@' for muc %@, fetching new image via vcard-temp...", avatarHash, presenceNode.fromUser);
                [self fetchAvatarForRoom:presenceNode.fromUser];
            }
            else if(avatarHash == nil && currentHash != nil && ![currentHash isEqualToString:@""])
            {
                [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:presenceNode.fromUser andAccountNo:_account.accountNo] WithData:nil];
                [[DataLayer sharedInstance] setAvatarHash:@"" forContact:presenceNode.fromUser andAccount:_account.accountNo];
                //delete cache to make sure the image will be regenerated
                [[MLImageManager sharedInstance] purgeCacheForContact:presenceNode.fromUser andAccount:_account.accountNo];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                    @"contact": [MLContact createContactFromJid:presenceNode.fromUser andAccountNo:_account.accountNo]
                }];
                DDLogInfo(@"Avatar of muc '%@' deleted successfully", presenceNode.fromUser);
            }
            else
                DDLogInfo(@"Avatar hash '%@' of muc %@ did not change, not updating avatar...", avatarHash, presenceNode.fromUser);
        }
        else
            DDLogInfo(@"Ignoring presence updates from %@, MUC not in buddylist", presenceNode.fromUser);
    }
    //handle reflected presences
    else
    {
        DDLogVerbose(@"Got muc presence from full jid: %@", presenceNode.from);
        
        //extract info if present (use an empty dict if no info is present)
        NSMutableDictionary* item = [[presenceNode findFirst:@"{http://jabber.org/protocol/muc#user}x/item@@"] mutableCopy];
        if(!item)
            item = [NSMutableDictionary new];
        
        //update jid to be a bare jid and add muc nick to our dict
        if(item[@"jid"])
            item[@"jid"] = [HelperTools splitJid:item[@"jid"]][@"user"];
        item[@"nick"] = presenceNode.fromResource;
        
        //handle presences
        if([presenceNode check:@"/<type=unavailable>"])
            [[DataLayer sharedInstance] removeParticipant:item fromMuc:presenceNode.fromUser forAccountId:_account.accountNo];
        else
        {
            if([[DataLayer sharedInstance] isContactInList:presenceNode.fromUser forAccount:_account.accountNo])
            {
                if(item[@"jid"] != nil)
                    [self handleMembersListUpdate:presenceNode];
                [[DataLayer sharedInstance] addParticipant:item toMuc:presenceNode.fromUser forAccountId:_account.accountNo];
            }
            else
                DDLogInfo(@"Ignoring presence updates from %@, MUC not in buddylist", presenceNode.fromUser);
        }
        
        //handle muc status codes in self-presences (after the above code, to make sure we are registered as participant in our db, too)
        if([presenceNode check:@"/{jabber:client}presence/{http://jabber.org/protocol/muc#user}x/status@code"])
            [self handleStatusCodes:presenceNode];        
    }
}

-(BOOL) processMessage:(XMPPMessage*) messageNode
{
    //handle member list updates of offline members (useful for members-only mucs)
    if([messageNode check:@"{http://jabber.org/protocol/muc#user}x/item"])
        [self handleMembersListUpdate:messageNode];
    
    //handle muc status codes
    [self handleStatusCodes:messageNode];
    
    //handle mediated invites
    if([messageNode check:@"{http://jabber.org/protocol/muc#user}x/invite"])
    {
        DDLogInfo(@"Got mediated muc invite from %@ for %@ --> joining...", [messageNode findFirst:@"{http://jabber.org/protocol/muc#user}x/invite@from"], messageNode.fromUser);
        [self sendDiscoQueryFor:messageNode.fromUser withJoin:YES andBookmarksUpdate:YES];
        return YES;     //stop processing in MLMessageProcessor
    }
    
    //handle direct invites
    if([messageNode check:@"{jabber:x:conference}x@jid"] && [[messageNode findFirst:@"{jabber:x:conference}x@jid"] length] > 0)
    {
        DDLogInfo(@"Got direct muc invite from %@ for %@ --> joining...", messageNode.fromUser, [messageNode findFirst:@"{jabber:x:conference}x@jid"]);
        [self sendDiscoQueryFor:[messageNode findFirst:@"{jabber:x:conference}x@jid"] withJoin:YES andBookmarksUpdate:YES];
        return YES;     //stop processing in MLMessageProcessor
    }
    
    //continue processing in MLMessageProcessor
    return NO;
}

-(void) handleMembersListUpdate:(XMPPStanza*) node
{
    if([[DataLayer sharedInstance] isContactInList:node.fromUser forAccount:_account.accountNo])
    {
        for(NSDictionary* entry in [node find:@"{http://jabber.org/protocol/muc#admin}query/item@@"])
        {
            NSMutableDictionary* item = [entry mutableCopy];
            if(!item || item[@"jid"] == nil)
                continue;       //ignore empty items or items without a jid

            //update jid to be a bare jid
            item[@"jid"] = [HelperTools splitJid:item[@"jid"]][@"user"];
            
#ifndef DISABLE_OMEMO
            BOOL isTypeGroup = [[[DataLayer sharedInstance] getMucTypeOfRoom:node.fromUser andAccount:_account.accountNo] isEqualToString:@"group"];
#endif
            
            if([@"none" isEqualToString:item[@"affiliation"]])
            {
                [[DataLayer sharedInstance] removeMember:item fromMuc:node.fromUser forAccountId:_account.accountNo];
#ifndef DISABLE_OMEMO
                if(isTypeGroup == YES)
                    [_account.omemo checkIfSessionIsStillNeeded:item[@"jid"] isMuc:NO];
#endif// DISABLE_OMEMO
            }
            else
            {
                [[DataLayer sharedInstance] addMember:item toMuc:node.fromUser forAccountId:_account.accountNo];
#ifndef DISABLE_OMEMO
                if(isTypeGroup == YES)
                    [_account.omemo subscribeAndFetchDevicelistIfNoSessionExistsForJid:item[@"jid"]];
#endif// DISABLE_OMEMO
            }
        }
    }
    else
        DDLogInfo(@"Ignoring handleMembersListUpdate for %@, MUC not in buddylist", node.fromUser);
}

-(void) handleStatusCodes:(XMPPStanza*) node
{
    NSSet* presenceCodes = [[NSSet alloc] initWithArray:[node find:@"/{jabber:client}presence/{http://jabber.org/protocol/muc#user}x/status@code|int"]];
    NSSet* messageCodes = [[NSSet alloc] initWithArray:[node find:@"/{jabber:client}message/{http://jabber.org/protocol/muc#user}x/status@code|int"]];
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:node.fromUser forAccount:_account.accountNo];
    
    //handle presence stanzas
    if(presenceCodes && [presenceCodes count])
    {
        for(NSNumber* code in presenceCodes)
            switch([code intValue])
            {
                //room created and needs configuration now
                case 201:
                {
                    //make instant room
                    DDLogInfo(@"Creating instant muc room using default config: %@", node.fromUser);
                    XMPPIQ* configNode = [[XMPPIQ alloc] initWithType:kiqSetType to:node.fromUser];
                    [configNode setInstantRoom];
                    [_account send:configNode];
                    break;
                }
                //muc service changed our nick
                case 210:
                {
                    //check if we haven't joined already (this status code is only valid while entering a room)
                    if([self isJoining:node.fromUser])
                    {
                        //update nick in database
                        DDLogInfo(@"Updating muc %@ nick in database to nick provided by server: '%@'...", node.fromUser, node.fromResource);
                        [[DataLayer sharedInstance] updateOwnNickName:node.fromResource forMuc:node.fromUser forAccount:_account.accountNo];
                    }
                    break;
                }
                //this is a self-presence (marking the end of the presence flood if we are in joining state)
                case 110:
                {
                    //check if we have joined already (we handle only non-joining self-presences here)
                    //joining self-presences are handled below
                    if(![self isJoining:node.fromUser])
                    {
                        //muc got destroyed
                        if([node check:@"/<type=unavailable>/{http://jabber.org/protocol/muc#user}x/destroy"])
                        {
                            [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Group/Channel got destroyed: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                            [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
                        }
                        else
                            ;           //ignore other non-joining self-presences for now
                    }
                    break;
                }
                //banned from room
                case 301:
                {
                    DDLogDebug(@"user '%@' got banned from room %@", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got banned from room %@", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got banned from: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                    }
                }
                //kicked from room
                case 307:
                {
                    DDLogDebug(@"user '%@' got kicked from room %@", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got kicked from room %@", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got kicked from: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                    }
                }
                //removed because of affiliation change --> reenter room
                case 321:
                {
                    DDLogDebug(@"user '%@' got affiliation changed for room %@", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got affiliation change for room %@", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self sendDiscoQueryFor:node.fromUser withJoin:YES andBookmarksUpdate:YES];
                    }
                }
                //removed because room is now members only (an we are not a member)
                case 322:
                {
                    DDLogDebug(@"user '%@' got removed from members-only room %@", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got removed from members-only room %@", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Kicked, because muc is now members-only: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                        [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
                    }
                }
                //removed because of system shutdown
                case 332:
                {
                    DDLogDebug(@"user '%@' got removed from room %@ because of system shutdown", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got removed from room %@ because of system shutdown", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Kicked, because of system shutdown: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                    }
                }
                default:
                    DDLogWarn(@"Got unhandled muc status code in presence from %@: %@", node.from, code);
            }
        
        //this is a self-presence marking the end of the presence flood, handle this code last because it resets _joining
        if([presenceCodes containsObject:@110] && [self isJoining:node.fromUser])
        {
            DDLogInfo(@"Successfully joined muc %@...", node.fromUser);
            
            //we are joined now, remove from joining list
            [self removeRoomFromJoining:node.fromUser];
            
            //we joined successfully --> add muc to our favorites (this will use the already up to date nick from buddylist db table)
            //and update bookmarks if this was the first time we joined this muc
            [[DataLayer sharedInstance] addMucFavorite:node.fromUser forAccountId:_account.accountNo andMucNick:nil];
            @synchronized(_stateLockObject) {
                DDLogVerbose(@"_firstJoin set: %@\n_noUpdateBookmarks set: %@", _firstJoin, _noUpdateBookmarks);
                //only update bookmarks on first join AND if not requested otherwise (batch join etc.)
                if([_firstJoin containsObject:node.fromUser] && ![_noUpdateBookmarks containsObject:node.fromUser])
                    [self updateBookmarks];
                [_firstJoin removeObject:node.fromUser];
                [_noUpdateBookmarks removeObject:node.fromUser];
            }
            
            if([[[DataLayer sharedInstance] getMucTypeOfRoom:node.fromUser andAccount:_account.accountNo] isEqualToString:@"group"])
                DDLogInfo(@"Recorded members and participants of group %@: %@", node.fromUser, [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:node.fromUser forAccountId:_account.accountNo]);
            else
            {
//these lists can potentially get really long for public channels --> restrict logging them to alpha builds
#ifdef IS_ALPHA
            DDLogInfo(@"Recorded members and participants of channel %@: %@", node.fromUser, [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:node.fromUser forAccountId:_account.accountNo]);
#endif
            }
            
            monal_id_block_t uiHandler = [self getUIHandlerForMuc:node.fromUser];
            if(uiHandler)
            {
                DDLogInfo(@"Calling UI handler for muc %@...", node.fromUser);
                dispatch_async(dispatch_get_main_queue(), ^{
                    uiHandler(@{
                        @"success": @YES,
                        @"muc": node.fromUser,
                        @"account": self->_account
                    });
                });
            }
            
            //MAYBE TODO: send out notification indicating we joined that room
            
            //query muc-mam for new messages
            BOOL supportsMam = NO;
            @synchronized(_stateLockObject) {
                if(_roomFeatures[node.fromUser] && [_roomFeatures[node.fromUser] containsObject:@"urn:xmpp:mam:2"])
                    supportsMam = YES;
            }
            if(supportsMam)
            {
                DDLogInfo(@"Muc %@ supports mam:2...", node.fromUser);
                
                //query mam since last received stanza ID because we could not resume the smacks session
                //(we would not have landed here if we were able to resume the smacks session)
                //this will do a catchup of everything we might have missed since our last connection
                //we possibly receive sent messages, too (this will update the stanzaid in database and gets deduplicate by messageid,
                //which is guaranteed to be unique (because monal uses uuids for outgoing messages)
                NSString* lastStanzaId = [[DataLayer sharedInstance] lastStanzaIdForMuc:node.fromUser andAccount:_account.accountNo];
                [_account delayIncomingMessageStanzasForArchiveJid:node.fromUser];
                XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:node.fromUser];
                if(lastStanzaId)
                {
                    DDLogInfo(@"Querying muc mam:2 archive after stanzaid '%@' for catchup", lastStanzaId);
                    [mamQuery setMAMQueryAfter:lastStanzaId];
                    [_account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
                }
                else
                {
                    DDLogInfo(@"Querying muc mam:2 archive for latest stanzaid to prime database");
                    [mamQuery setMAMQueryForLatestId];
                    [_account sendIq:mamQuery withHandler:$newHandler(self, handleMamResponseWithLatestId)];
                }
            }
            
            //we don't need to force saving of our new state because once this incoming presence gets counted by smacks the whole state will be saved
        }
    }
    //handle message stanzas
    else if([[node findFirst:@"/@type"] isEqualToString:@"groupchat"] && messageCodes && [messageCodes count])
    {
        for(NSNumber* code in messageCodes)
            switch([code intValue])
            {
                //config changes
                case 102:
                case 103:
                case 104:
                {
                    DDLogInfo(@"Muc config of %@ changed, sending new disco info query to reload muc config...", node.fromUser);
                    [self sendDiscoQueryFor:node.from withJoin:NO andBookmarksUpdate:NO];
                    break;
                }
                default:
                    DDLogWarn(@"Got unhandled muc status code in message from %@: %@", node.from, code);
            }
    }
}

-(void) join:(NSString*) room
{
    [self sendDiscoQueryFor:room withJoin:YES andBookmarksUpdate:YES];
}

-(void) leave:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks
{
    room = [room lowercaseString];
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountNo];
    if(nick == nil)
    {
        DDLogError(@"Cannot leave room '%@' on account %@ because nick is nil!", room, _account);
        return;
    }
    @synchronized(_stateLockObject) {
        if(_joining[room] != nil)
        {
            DDLogInfo(@"Aborting join of room '%@' on account %@", room, _account);
            [self removeRoomFromJoining:room];
        }
    }
    DDLogInfo(@"Leaving room '%@' on account %@ using nick '%@'...", room, _account, nick);
    //send unsubscribe even if we are not fully joined (join aborted), just to make sure we *really* leave ths muc
    XMPPPresence* presence = [XMPPPresence new];
    [presence leaveRoom:room withNick:nick];
    [_account send:presence];
    
    //delete muc from favorites table and update bookmarks if requested
    [self deleteMuc:room withBookmarksUpdate:updateBookmarks keepBuddylistEntry:NO];
}

-(void) sendDiscoQueryFor:(NSString*) roomJid withJoin:(BOOL) join andBookmarksUpdate:(BOOL) updateBookmarks
{
    if(roomJid == nil || _account == nil)
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Room jid or account must not be nil!" userInfo:nil];
    roomJid = [roomJid lowercaseString];
    DDLogInfo(@"Querying disco for muc %@...", roomJid);
    //mark room as "joining" as soon as possible to make sure we can handle join "aborts" (e.g. when processing bookmark updates while a joining disco query is already in flight)
    //this will fix race condition that makes us join a muc directly after it got removed from our favorites table and leaved through a bookmark update
    if(join)
    {
        @synchronized(_stateLockObject) {
            //don't join twice
            if(_joining[roomJid] != nil)
            {
                DDLogInfo(@"Already joining muc %@, not doing it twice", roomJid);
                return;
            }
            //add room to "currently joining" list (without any idle timer yet, because the iq handling will timeout the disco iq already)
            _joining[roomJid] = @(-1);      //TODO
            //we don't need to force saving of our new state because once this outgoing iq query gets handled by smacks the whole state will be saved
        }
    }
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:roomJid];
    [discoInfo setDiscoInfoNode];
    [_account sendIq:discoInfo withHandler:$newHandlerWithInvalidation(self, handleDiscoResponse, handleDiscoResponseInvalidation, $ID(roomJid), $BOOL(join), $BOOL(updateBookmarks))];
}

-(void) pingAllMucs
{
    if([[NSDate date] timeIntervalSinceDate:_lastPing] < MUC_PING)
    {
        DDLogInfo(@"Not pinging all mucs, last ping was less than %d seconds ago: %@", MUC_PING, _lastPing);
        return;
    }
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:_account.accountNo])
        [self ping:entry[@"room"] withLastPing:_lastPing];
    _lastPing = [NSDate date];
}

-(void) ping:(NSString*) roomJid
{
    [self ping:roomJid withLastPing:nil];
}

-(void) ping:(NSString*) roomJid withLastPing:(NSDate* _Nullable) lastPing
{
    if(![[DataLayer sharedInstance] isBuddyMuc:roomJid forAccount:_account.accountNo])
    {
        DDLogWarn(@"Tried to muc-ping non-muc jid '%@', trying to join regularily with disco...", roomJid);
        [self removeRoomFromJoining:roomJid];
        //this will check if this jid really is not a muc and delete it fom favorites and bookmarks, if not (and join normally if it turns out is a muc after all)
        [self sendDiscoQueryFor:roomJid withJoin:YES andBookmarksUpdate:YES];
        return;
    }
    
    XMPPIQ* ping = [[XMPPIQ alloc] initWithType:kiqGetType to:roomJid];
    ping.toResource = [[DataLayer sharedInstance] ownNickNameforMuc:roomJid forAccount:_account.accountNo];
    [ping setPing];
    //we don't need to handle this across smacks resumes or reconnects, because a new ping will be issued on the next smacks resume
    //(and full reconnets will rejoin all mucs anyways)
    [_account sendIq:ping withResponseHandler:^(XMPPIQ* result __unused) {
        DDLogInfo(@"Muc ping returned: we are still connected to %@, everything is fine", roomJid);
    } andErrorHandler:^(XMPPIQ* error) {
        if(error == nil)
        {
            DDLogWarn(@"Ping handler for %@ got invalidated, aborting ping...", roomJid);
            //make sure we try again without waiting another MUC_PING seconds, if possible (i.e. this ping was not triggered by ui)
            if(lastPing != nil)
                self->_lastPing = lastPing;
            return;
        }
        DDLogWarn([HelperTools extractXMPPError:error withDescription:@"Muc ping returned error"]);
        if([error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}not-acceptable"])
        {
            DDLogWarn(@"Ping failed with 'not-acceptable' --> we have to re-join %@", roomJid);
            @synchronized(self->_stateLockObject) {
                [self->_joining removeObjectForKey:roomJid];
            }
            //check if muc is still in our favorites table before we try to join it (could be deleted by a bookmarks update just after we sent out our ping)
            //this has to be done to avoid such a race condition that would otherwise re-add the muc back
            if([self checkIfStillBookmarked:roomJid])
                [self sendDiscoQueryFor:roomJid withJoin:YES andBookmarksUpdate:YES];
            else
                DDLogWarn(@"Not re-joining because muc %@ got removed from favorites table in the meantime", roomJid);
        }
        else if(
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}service-unavailable"] ||
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}feature-not-implemented"]
        )
        {
            DDLogInfo(@"The client is joined to %@, but the pinged client does not implement XMPP Ping (XEP-0199) --> do nothing", roomJid);
        }
        else if([error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            DDLogInfo(@"The client is joined to %@, but the occupant just changed their name (e.g. initiated by a different client) --> do nothing", roomJid);
        }
        else if(
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}remote-server-not-found"] ||
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}remote-server-timeout"]
        )
        {
            DDLogError(@"The remote server for room %@ is unreachable for unspecified reasons; this can be a temporary network failure or a server outage. No decision can be made based on this; Treat like a timeout --> do nothing", roomJid);
        }
        else
        {
            DDLogWarn(@"Any other error happened: The client is probably not joined to %@ any more. It should perform a re-join. --> we have to re-join", roomJid);
            @synchronized(self->_stateLockObject) {
                [self->_joining removeObjectForKey:roomJid];
            }
            //check if muc is still in our favorites table before we try to join it (could be deleted by a bookmarks updae just after we sent out our ping)
            //this has to be done to avoid such a race condition that would otherwise re-add the muc back
            if([self checkIfStillBookmarked:roomJid])
                [self sendDiscoQueryFor:roomJid withJoin:YES andBookmarksUpdate:YES];
            else
                DDLogWarn(@"Not re-joining %@ because this muc got removed from favorites table in the meantime", roomJid);
        }
    }];
}

-(void) publishAvatar:(UIImage*) image forMuc:(NSString*) room
{
    //should work for ejabberd >= 19.02 and prosody >= 0.11
    NSData* imageData = [HelperTools resizeAvatarImage:image withCircularMask:NO toMaxBase64Size:60000];
    NSString* imageHash = [HelperTools hexadecimalString:[HelperTools sha1:imageData]];
    
    DDLogInfo(@"Publishing avatar image for muc '%@' with hash %@", room, imageHash);
    XMPPIQ* vcard = [[XMPPIQ alloc] initWithType:kiqSetType to:room];
    [vcard setVcardAvatarWithData:imageData andType:@"image/jpeg"];
    [_account sendIq:vcard withHandler:$newHandler(self, handleAvatarPublishResult)];
}

$$instance_handler(handleAvatarPublishResult, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Publishing avatar for muc '%@' returned error: %@", iqNode.fromUser, [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"Failed to publish avatar image for group/channel %@", @"") withNode:iqNode andAccount:_account andIsSevere:YES];
        return;
    }
    DDLogInfo(@"Successfully published avatar for muc: %@", iqNode.fromUser);
$$

$$instance_handler(handleDiscoResponseInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, roomJid))
    DDLogInfo(@"Removing muc '%@' from _joining...", roomJid);
    [self removeRoomFromJoining:roomJid];
$$

$$instance_handler(handleDiscoResponse, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, roomJid), $$BOOL(join), $$BOOL(updateBookmarks))
    MLAssert([iqNode.fromUser isEqualToString:roomJid], @"Disco response jid not matching query jid!", (@{
        @"iqNode.fromUser": [NSString stringWithFormat:@"%@", iqNode.fromUser],
        @"roomJid": [NSString stringWithFormat:@"%@", roomJid],
    }));
    
    if([iqNode check:@"/<type=error>/error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}gone"])
    {
        DDLogError(@"Querying muc info returned this muc isn't available anymore: %@", [iqNode findFirst:@"error"]);
        [self removeRoomFromJoining:iqNode.fromUser];
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted
        [self deleteMuc:iqNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
        
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Group/Channel not available anymore: %@", @""), iqNode.fromUser] forMuc:iqNode.fromUser withNode:iqNode andIsSevere:YES];
        return;
    }
    
    if([iqNode check:@"/<type=error>/error<type=wait>"])
    {
        DDLogError(@"Querying muc info returned a temporary error: %@", [iqNode findFirst:@"error"]);
        [self removeRoomFromJoining:iqNode.fromUser];
        
        //do nothing: the error is only temporary (a s2s problem etc.), a muc ping will retry the join
        //this will keep the entry in local bookmarks table and remote bookmars
        //--> retry the join on mucPing or full login without smacks resume
        //this will also keep the buddy list entry
        //--> allow users to read the last messages before the muc got broken
        
        //only display an error banner, no notification (this is only temporary)
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Temporary failure to enter Group/Channel: %@", @""), roomJid] forMuc:roomJid withNode:iqNode andIsSevere:NO];
        return;
    }
    else if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Querying muc info returned a persistent error: %@", [iqNode findFirst:@"error"]);
        [self removeRoomFromJoining:iqNode.fromUser];
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted/broken
        [self deleteMuc:iqNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
        
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter Group/Channel %@", @""), roomJid] forMuc:roomJid withNode:iqNode andIsSevere:YES];
        return;
    }
    
    //extract features
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    
    //check if this is a muc
    if(![features containsObject:@"http://jabber.org/protocol/muc"])
    {
        DDLogError(@"muc disco returned that this jid is not a muc!");
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted/broken
        //AND: to not auto-delete contact list entries via malicious xmpp:?join links
        [self deleteMuc:iqNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
    
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter Group/Channel %@: This is not a Group/Channel!", @""), iqNode.fromUser] forMuc:iqNode.fromUser withNode:nil andIsSevere:YES];
        return;
    }
    
    //force join if this isn't already recorded as muc in our database but as normal user or not recorded at all
    if(!join && ![[DataLayer sharedInstance] isBuddyMuc:iqNode.fromUser forAccount:_account.accountNo])
        join = YES;
    
    //the join (join=YES) was aborted by a call to leave (isJoining: returns NO)
    if(join && ![self isJoining:iqNode.fromUser])
    {
        DDLogWarn(@"Ignoring muc disco result for '%@' on account %@: not joining anymore...", iqNode.fromUser, _account);
        return;
    }
        
    //extract further muc infos
    NSString* mucName = [iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\"];
    NSString* mucType = @"channel";
    //both are needed for omemo, see discussion with holger 2021-01-02/03 -- Thilo Molitor
    //see also: https://docs.modernxmpp.org/client/groupchat/
    if([features containsObject:@"muc_nonanonymous"] && [features containsObject:@"muc_membersonly"])
        mucType = @"group";
    
    //update db with new infos
    if(![[DataLayer sharedInstance] isBuddyMuc:iqNode.fromUser forAccount:_account.accountNo])
    {
        //remove old non-muc contact from contactlist (we don't want mucs as normal contacts on our (server) roster and shadowed in monal by the real muc contact)
        if([[DataLayer sharedInstance] contactDictionaryForUsername:iqNode.fromUser forAccount:_account.accountNo] != nil)
            [_account removeFromRoster:[MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo]];
        //add new muc buddy (potentially deleting a non-muc buddy having the same jid)
        NSString* nick = [self calculateNickForMuc:iqNode.fromUser];
        DDLogInfo(@"Adding new muc %@ using nick '%@' to buddylist...", iqNode.fromUser, nick);
        [[DataLayer sharedInstance] initMuc:iqNode.fromUser forAccountId:_account.accountNo andMucNick:nick];
        //add this room to firstJoin list
        @synchronized(_stateLockObject) {
            [_firstJoin addObject:iqNode.fromUser];
            if(updateBookmarks == NO)
                [_noUpdateBookmarks addObject:iqNode.fromUser];
        }
        //make public channels "mention only" on first join
        if([@"channel" isEqualToString:mucType])
            [[DataLayer sharedInstance] setMucAlertOnMentionOnly:iqNode.fromUser onAccount:_account.accountNo];
    }
    
    if(![mucType isEqualToString:[[DataLayer sharedInstance] getMucTypeOfRoom:iqNode.fromUser andAccount:_account.accountNo]])
    {
        DDLogInfo(@"Configuring muc %@ to type '%@'...", iqNode.fromUser, mucType);
        [[DataLayer sharedInstance] updateMucTypeTo:mucType forRoom:iqNode.fromUser andAccount:_account.accountNo];
    }
    
    if(mucName && [mucName length])
    {
        MLContact* mucContact = [MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo];
        if(![mucName isEqualToString:mucContact.fullName])
        {
            DDLogInfo(@"Configuring muc %@ to use name '%@'...", iqNode.fromUser, mucName);
            [[DataLayer sharedInstance] setFullName:mucName forContact:iqNode.fromUser andAccount:_account.accountNo];
        }
    }
    
    DDLogDebug(@"Updating muc contact...");
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
        @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo]
    }];
    
    @synchronized(_stateLockObject) {
        _roomFeatures[iqNode.fromUser] = features;
        //we don't need to force saving of our new state because once this incoming iq gets counted by smacks the whole state will be saved
    }
    
    if(join)
    {
        DDLogInfo(@"Clearing muc participants and members tables for %@", iqNode.fromUser);
        [[DataLayer sharedInstance] cleanupMembersAndParticipantsListFor:iqNode.fromUser forAccountId:_account.accountNo];
    
        //load members/admins/owners list
        DDLogInfo(@"Querying members/admin/owner lists for muc %@...", iqNode.fromUser);
        for(NSString* type in @[@"member", @"admin", @"owner"])
        {
            XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:iqNode.fromUser];
            [discoInfo setMucListQueryFor:type];
            [_account sendIq:discoInfo withHandler:$newHandler(self, handleMembersList, $ID(type))];
        }
    
        //now try to join this room if requested
        [self sendJoinPresenceFor:iqNode.fromUser];
    }
$$

-(void) sendJoinPresenceFor:(NSString*) room
{
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountNo];
    DDLogInfo(@"Trying to join muc '%@' with nick '%@' on account %@...", room, nick, _account);
    @synchronized(_stateLockObject) {
        //add room to "currently joining" list (and remove any present idle timer for this room)
        [[DataLayer sharedInstance] delIdleTimerWithId:_joining[room]];
        //add idle timer to display error if we did not receive the reflected join presence after 30 idle seconds
        //this will make sure the spinner ui will not spin indefinitely when adding a channel via ui
        NSNumber* timerId = [[DataLayer sharedInstance] addIdleTimerWithTimeout:@30 andHandler:$newHandler(self, handleJoinTimeout, $ID(room)) onAccountNo:_account.accountNo];
        _joining[room] = timerId;
        //we don't need to force saving of our new state because once this outgoing join presence gets handled by smacks the whole state will be saved
    }
    
    XMPPPresence* presence = [XMPPPresence new];
    [presence joinRoom:room withNick:nick];
    [_account send:presence];
}

$$instance_handler(handleJoinTimeout, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, room))
    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not join group/channel '%@': timeout", @""), room] forMuc:room withNode:nil andIsSevere:YES];
    //don't remove the muc, this could be a temporary (network induced) error
$$

$$instance_handler(handleMembersList, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, type))
    DDLogInfo(@"Got %@s list from %@...", type, iqNode.fromUser);
    [self handleMembersListUpdate:iqNode];
$$

$$instance_handler(handleMamResponseWithLatestId, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Muc mam latest stanzaid query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query new messages for Group/Channel (stanzaid) %@", @""), iqNode.fromUser] withNode:iqNode andAccount:_account andIsSevere:YES];
        [_account mamFinishedFor:iqNode.fromUser];
        return;
    }
    DDLogVerbose(@"Got latest muc stanza id to prime database with: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
    //only do this if we got a valid stanza id (not null)
    //if we did not get one we will get one when receiving the next muc message in this smacks session
    //if the smacks session times out before we get a message and someone sends us one or more messages before we had a chance to establish
    //a new smacks session, this messages will get lost because we don't know how to query the archive for this message yet
    //once we successfully receive the first mam-archived message stanza (could even be an XEP-184 ack for a sent message),
    //no more messages will get lost
    //we ignore this single message loss here, because it should be super rare and solving it would be really complicated
    if([iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
        [[DataLayer sharedInstance] setLastStanzaId:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"] forMuc:iqNode.fromUser andAccount:_account.accountNo];
    [_account mamFinishedFor:iqNode.fromUser];
$$

$$instance_handler(handleCatchup, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$BOOL(secondTry))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Muc mam catchup query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        
        //handle weird XEP-0313 monkey-patching XEP-0059 behaviour (WHY THE HELL??)
        if(!secondTry && [iqNode check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:iqNode.fromUser];
            DDLogInfo(@"Querying COMPLETE muc mam:2 archive for catchup");
            [mamQuery setCompleteMAMQuery];
            [_account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, YES))];
        }
        else
        {
            [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query new messages for Group/Channel (catchup) %@", @""), iqNode.fromUser] withNode:iqNode andAccount:_account andIsSevere:YES];
            [_account mamFinishedFor:iqNode.fromUser];
        }
        return;
    }
    if(![[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue] && [iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
    {
        DDLogVerbose(@"Paging through muc mam catchup results with after: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:iqNode.fromUser];
        [pageQuery setMAMQueryAfter:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]];
        [_account sendIq:pageQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
    }
    else if([[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue])
    {
        DDLogVerbose(@"Muc mam catchup finished");
        [_account mamFinishedFor:iqNode.fromUser];
    }
$$

-(void) fetchAvatarForRoom:(NSString*) room
{
    XMPPIQ* vcardQuery = [[XMPPIQ alloc] initWithType:kiqGetType to:room];
    [vcardQuery setVcardQuery];
    [_account sendIq:vcardQuery withHandler:$newHandler(self, handleVcardResponse)];
}

$$instance_handler(handleVcardResponse, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    BOOL deleteAvatar = ![iqNode check:@"{vcard-temp}vCard/PHOTO/BINVAL"];
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Failed to retrieve avatar of muc '%@', error: %@", iqNode.fromUser, [iqNode findFirst:@"error"]);
        deleteAvatar = YES;
    }
    
    if(deleteAvatar)
    {
        [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo] WithData:nil];
        [[DataLayer sharedInstance] setAvatarHash:@"" forContact:iqNode.fromUser andAccount:_account.accountNo];
        //delete cache to make sure the image will be regenerated
        [[MLImageManager sharedInstance] purgeCacheForContact:iqNode.fromUser andAccount:_account.accountNo];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
            @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo]
        }];
        DDLogInfo(@"Avatar of muc '%@' deleted successfully", iqNode.fromUser);
    }
    else
    {
        //this should be small enough to not crash the appex when loading the image from file later on but large enough to have excellent quality
        NSData* imageData = [iqNode findFirst:@"{vcard-temp}vCard/PHOTO/BINVAL#|base64"];
        if([HelperTools isAppExtension] && imageData.length > 128 * 1024)
        {
            DDLogWarn(@"Not processing avatar image data of muc '%@' because it is too big to be handled in appex (%lu bytes), rescheduling it to be fetched in mainapp", iqNode.fromUser, (unsigned long)imageData.length);
            [_account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(iqNode.fromUser))];
            return;
        }
        
        //this will consume a large portion of ram because it will be represented as uncomressed bitmap
        UIImage* image = [UIImage imageWithData:imageData];
        NSString* avatarHash = [HelperTools hexadecimalString:[HelperTools sha1:imageData]];
        //this upper limit is roughly 1.4MiB memory (600x600 with 4 byte per pixel)
        if(![HelperTools isAppExtension] || image.size.width * image.size.height < 600 * 600)
        {
            NSData* imageData = [HelperTools resizeAvatarImage:image withCircularMask:YES toMaxBase64Size:256000];
            [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo] WithData:imageData];
            [[DataLayer sharedInstance] setAvatarHash:avatarHash forContact:iqNode.fromUser andAccount:_account.accountNo];
            //delete cache to make sure the image will be regenerated
            [[MLImageManager sharedInstance] purgeCacheForContact:iqNode.fromUser andAccount:_account.accountNo];
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountNo:_account.accountNo]
            }];
            DDLogInfo(@"Avatar of muc '%@' fetched and updated successfully", iqNode.fromUser);
        }
        else
        {
            DDLogWarn(@"Not loading avatar image of muc '%@' because it is too big to be processed in appex (%lux%lu pixels), rescheduling it to be fetched in mainapp", iqNode.fromUser, (unsigned long)image.size.width, (unsigned long)image.size.height);
            [_account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(iqNode.fromUser))];
        }
    }
$$

//this handler will simply retry the vcard fetch attempt if in mainapp
$$instance_handler(fetchAvatarAgain, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, jid))
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"Not loading avatar image of '%@' because we are still in appex, rescheduling it again!", jid);
        [_account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid))];
    }
    else
        [self fetchAvatarForRoom:jid];
$$

-(void) handleError:(NSString*) description forMuc:(NSString*) room withNode:(XMPPStanza*) node andIsSevere:(BOOL) isSevere
{
    monal_id_block_t uiHandler = [self getUIHandlerForMuc:room];
    //call ui handler if registered for this room
    if(uiHandler)
    {
        //remove handler (it will only be called once)
        [self removeUIHandlerForMuc:room];
        
        if(node == nil)
        {
            DDLogInfo(@"Could not extract UI error message. node == nil");
            return;
        }
        
        //prepare data
        NSString* message = [HelperTools extractXMPPError:node withDescription:description];
        NSDictionary* data = @{
            @"success": @NO,
            @"muc": room,
            @"account": _account,
            @"errorMessage": message
        };
        
        DDLogInfo(@"Calling UI error handler with %@", data);
        dispatch_async(dispatch_get_main_queue(), ^{
            uiHandler(data);
        });
    }
    //otherwise call the general error handler
    else
        [HelperTools postError:description withNode:node andAccount:_account andIsSevere:isSevere];
}

-(void) updateBookmarks
{
    DDLogVerbose(@"Updating bookmarks on account %@", _account);
    //use bookmarks2, if server supports syncing between XEP-0048 and XEP-0402 bookmarks
    //use old-style XEP-0048 bookmarks, if not
    if(_account.connectionProperties.supportsBookmarksCompat)
        [_account.pubsub fetchNode:@"urn:xmpp:bookmarks:1" from:_account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, handleBookmarks2FetchResult)];
    else
        [_account.pubsub fetchNode:@"storage:bookmarks" from:_account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, handleBookarksFetchResult)];
}

-(BOOL) checkIfStillBookmarked:(NSString*) room
{
    room = [room lowercaseString];
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:_account.accountNo])
        if([room isEqualToString:[entry[@"room"] lowercaseString]])
            return YES;
    return NO;
}

-(NSSet*) getRoomFeaturesForMuc:(NSString*) room
{
    return _roomFeatures[room];
}

-(void) deleteMuc:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks keepBuddylistEntry:(BOOL) keepBuddylistEntry
{
    DDLogInfo(@"Deleting muc %@ on account %@...", room, _account);
    
    //create contact object before deleting it to retain the muc specific settings
    //(after deleting it from our db, the contact for this jid will look like an ordinary 1:1 contact)
    MLContact* contact = [MLContact createContactFromJid:room andAccountNo:_account.accountNo];
    
    //delete muc from favorites table and update bookmarks if requested
    [[DataLayer sharedInstance] deleteMuc:room forAccountId:_account.accountNo];
    if(updateBookmarks)
        [self updateBookmarks];
    
    //update buddylist (e.g. contact list) if requested
    if(keepBuddylistEntry)
        ;       //TODO: mark entry as destroyed to be displayed in the ui
    else
    {
        [[DataLayer sharedInstance] removeBuddy:room forAccount:_account.accountNo];
        [contact removeShareInteractions];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRemoved object:_account userInfo:@{
            @"contact": contact
        }];
    }
}

-(NSString*) calculateNickForMuc:(NSString*) room
{
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountNo];
    //use the account display name as nick, if nothing can be found in buddylist and muc_favorites db tables
    if(!nick)
    {
        nick = [MLContact ownDisplayNameForAccount:_account];
        DDLogInfo(@"Using default nick '%@' for room %@ on account %@", nick, room, _account);
    }
    return nick;
}

-(void) removeRoomFromJoining:(NSString*) room
{
    @synchronized(_stateLockObject) {
        DDLogVerbose(@"Removing from _joining[%@]: %@", room, _joining[room]);
        [[DataLayer sharedInstance] delIdleTimerWithId:_joining[room]];
        [_joining removeObjectForKey:room];
    }
}

@end
