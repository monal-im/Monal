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

#define CURRENT_MUC_STATE_VERSION @3

@interface MLMucProcessor()

@end

@implementation MLMucProcessor

static NSObject* _stateLockObject;

//persistent state
static NSMutableDictionary* _roomFeatures;
static NSMutableSet* _joining;
static NSMutableSet* _firstJoin;
static NSDate* _lastPing;

//this won't be persisted because it is only for the ui
static NSMutableDictionary* _uiHandler;

+(void) initialize
{
    _stateLockObject = [[NSObject alloc] init];
    _roomFeatures = [[NSMutableDictionary alloc] init];
    _joining = [[NSMutableSet alloc] init];
    _firstJoin = [[NSMutableSet alloc] init];
    _uiHandler = [[NSMutableDictionary alloc] init];
    _lastPing = [NSDate date];
}

+(void) setState:(NSDictionary*) state
{
    //ignore state having wrong version code
    if(!state[@"version"] || ![state[@"version"] isEqual:CURRENT_MUC_STATE_VERSION])
        return;
    
    //extract state
    @synchronized(_stateLockObject) {
        _roomFeatures = [state[@"roomFeatures"] mutableCopy];
        _joining = [state[@"joining"] mutableCopy];
        _firstJoin = [state[@"firstJoin"] mutableCopy];
        _lastPing = state[@"lastPing"];
    }
}

+(NSDictionary*) state
{
    @synchronized(_stateLockObject) {
        return @{
            @"version": CURRENT_MUC_STATE_VERSION,
            @"roomFeatures": _roomFeatures,
            @"joining": _joining,
            @"firstJoin": _firstJoin,
            @"lastPing": _lastPing,
        };
    }
}

+(BOOL) isJoining:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return [_joining containsObject:room];
    }
}

+(void) addUIHandler:(monal_id_block_t) handler forMuc:(NSString*) room
{
    //this will replace the old handler
    @synchronized(_stateLockObject) {
        _uiHandler[room] = handler;
    }
}

+(void) removeUIHandlerForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        [_uiHandler removeObjectForKey:room];
    }
}

+(monal_id_block_t) getUIHandlerForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return _uiHandler[room];
    }
}

+(void) processPresence:(XMPPPresence*) presenceNode forAccount:(xmpp*) account
{
    //check for nickname conflict while joining and retry with underscore added to the end
    if([self isJoining:presenceNode.fromUser] && [presenceNode findFirst:@"/<type=error>/error/{urn:ietf:params:xml:ns:xmpp-stanzas}conflict"])
    {
        //load old nickname from db, add underscore and write it back to db so that it can be used by our next join
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:presenceNode.fromUser forAccount:account.accountNo];
        nick = [NSString stringWithFormat:@"%@_", nick];
        [[DataLayer sharedInstance] initMuc:presenceNode.fromUser forAccountId:account.accountNo andMucNick:nick];
        
        //try to join again
        DDLogInfo(@"Retrying muc join of %@ with new nick (appended underscore): %@", presenceNode.fromUser, nick);
        @synchronized(_stateLockObject) {
            [_joining removeObject:presenceNode.fromUser];
        }
        [self sendDiscoQueryFor:presenceNode.fromUser onAccount:account withJoin:YES];
        return;
    }
    
    //check for all other errors
    if([presenceNode findFirst:@"/<type=error>"])
    {
        DDLogError(@"got muc error presence!");
        @synchronized(_stateLockObject) {
            [_joining removeObject:presenceNode.fromUser];
        }
        [self handleError:NSLocalizedString(@"Groupchat error", @"") forMuc:presenceNode.fromUser withNode:presenceNode andAccount:account andIsSevere:YES];
        return;
    }
    
    //handle muc status codes in self-presences
    if([presenceNode check:@"/{jabber:client}presence/{http://jabber.org/protocol/muc#user}x/status@code"])
        [self handleStatusCodes:presenceNode forAccount:account];
    
    //extract info if present (use an empty dict if no info is present)
    NSMutableDictionary* item = [[presenceNode findFirst:@"{http://jabber.org/protocol/muc#user}x/item@@"] mutableCopy];
    if(!item)
        item = [[NSMutableDictionary alloc] init];
    
    //update jid to be a bare jid and add muc nick to our dict
    if(item[@"jid"])
        item[@"jid"] = [HelperTools splitJid:item[@"jid"]][@"user"];
    item[@"nick"] = presenceNode.fromResource;
    
    //handle presences
    if([presenceNode check:@"/<type=unavailable>"])
        [[DataLayer sharedInstance] removeParticipant:item fromMuc:presenceNode.fromUser forAccountId:account.accountNo];
    else
        [[DataLayer sharedInstance] addParticipant:item toMuc:presenceNode.fromUser forAccountId:account.accountNo];
}

+(BOOL) processMessage:(XMPPMessage*) messageNode forAccount:(xmpp*) account
{
    //handle muc status codes
    [self handleStatusCodes:messageNode forAccount:account];
    
    //handle mediated invites
    if([messageNode check:@"{http://jabber.org/protocol/muc#user}x/invite"])
    {
        DDLogInfo(@"Got mediated muc invite from %@ for %@ --> joining...", [messageNode findFirst:@"{http://jabber.org/protocol/muc#user}x/invite@from"], messageNode.fromUser);
        [self sendDiscoQueryFor:messageNode.fromUser onAccount:account withJoin:YES];
        return YES;     //stop processing in MLMessageProcessor
    }
    
    //handle direct invites
    if([messageNode check:@"{jabber:x:conference}x@jid"] && [[messageNode findFirst:@"{jabber:x:conference}x@jid"] length] > 0)
    {
        DDLogInfo(@"Got direct muc invite from %@ for %@ --> joining...", messageNode.fromUser, [messageNode findFirst:@"{jabber:x:conference}x@jid"]);
        [self sendDiscoQueryFor:[messageNode findFirst:@"{jabber:x:conference}x@jid"] onAccount:account withJoin:YES];
        return YES;     //stop processing in MLMessageProcessor
    }
    
    //continue processing in MLMessageProcessor
    return NO;
}

+(void) handleStatusCodes:(XMPPStanza*) node forAccount:(xmpp*) account
{
    NSSet* presenceCodes = [[NSSet alloc] initWithArray:[node find:@"/{jabber:client}presence/{http://jabber.org/protocol/muc#user}x/status@code|int"]];
    NSSet* messageCodes = [[NSSet alloc] initWithArray:[node find:@"/{jabber:client}message/{http://jabber.org/protocol/muc#user}x/status@code|int"]];
    
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
                    DDLogInfo(@"Creating instant muc room %@...", node.fromUser);
                    XMPPIQ* configNode = [[XMPPIQ alloc] initWithType:kiqSetType];
                    [configNode setiqTo:node.fromUser];
                    [configNode setInstantRoom];
                    [account send:configNode];
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
                        [[DataLayer sharedInstance] updateOwnNickName:node.fromResource forMuc:node.fromUser forAccount:account.accountNo];
                    }
                    break;
                }
                //this is a self-presence (marking the end of the presence flood if we are in joining state)
                case 110:
                {
                    //check if we have joined already (we handle only non-joining self-presences here)
                    //joining self-presences are handled below
                    if(![self isJoining:node.fromUser])
                        ;           //ignore non-joining self-presences for now
                    break;
                }
                //banned from room
                case 301:
                {
                    @synchronized(_stateLockObject) {
                        [_joining removeObject:node.fromUser];
                    }
                    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got banned from: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andAccount:account andIsSevere:YES];
                }
                //kicked from room
                case 307:
                {
                    @synchronized(_stateLockObject) {
                        [_joining removeObject:node.fromUser];
                    }
                    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got kicked from: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andAccount:account andIsSevere:YES];
                }
                //removed because of affiliation change --> reenter room
                case 321:
                {
                    @synchronized(_stateLockObject) {
                        [_joining removeObject:node.fromUser];
                    }
                    [self sendDiscoQueryFor:node.fromUser onAccount:account withJoin:YES];
                }
                //removed because room is now members only (an we are not a member)
                case 322:
                {
                    @synchronized(_stateLockObject) {
                        [_joining removeObject:node.fromUser];
                    }
                    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Kicked, because muc is now members-only: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andAccount:account andIsSevere:YES];
                }
                //removed because of system shutdown
                case 332:
                {
                    @synchronized(_stateLockObject) {
                        [_joining removeObject:node.fromUser];
                    }
                    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Kicked, because of system shutdown: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andAccount:account andIsSevere:YES];
                }
                default:
                    DDLogInfo(@"Got unhandled muc status code in presence from %@: %@", node.from, code);
            }
        
        //this is a self-presence marking the end of the presence flood, handle this code last because it resets _joining
        if([presenceCodes containsObject:@110] && [self isJoining:node.fromUser])
        {
            DDLogInfo(@"Successfully joined muc %@...", node.fromUser);
            
            //we are joined now, remove from joining list
            @synchronized(_stateLockObject) {
                [_joining removeObject:node.fromUser];
            }
            
            //we joined successfully --> add muc to our favorites (this will use the already up to date nick from buddylist db table)
            //and update bookmarks if this was the first timewe joined this muc
            [[DataLayer sharedInstance] addMucFavorite:node.fromUser forAccountId:account.accountNo andMucNick:nil];
            @synchronized(_stateLockObject) {
                if([_firstJoin containsObject:node.fromUser])
                    [self updateBookmarksForAccount:account];
                [_firstJoin removeObject:node.fromUser];
            }
            
            monal_id_block_t uiHandler = [self getUIHandlerForMuc:node.fromUser];
            if(uiHandler)
            {
                DDLogInfo(@"Calling UI handler for muc %@...", node.fromUser);
                dispatch_async(dispatch_get_main_queue(), ^{
                    uiHandler(@{
                        @"success": @YES,
                        @"muc": node.fromUser
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
                NSString* lastStanzaId = [[DataLayer sharedInstance] lastStanzaIdForMuc:node.fromUser andAccount:account.accountNo];
                XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
                [mamQuery setiqTo:node.fromUser];
                if(lastStanzaId)
                {
                    DDLogInfo(@"Querying muc mam:2 archive after stanzaid '%@' for catchup", lastStanzaId);
                    [mamQuery setMAMQueryAfter:lastStanzaId];
                    [account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup)];
                }
                else
                {
                    DDLogInfo(@"Querying muc mam:2 archive for latest stanzaid to prime database");
                    [mamQuery setMAMQueryForLatestId];
                    [account sendIq:mamQuery withHandler:$newHandler(self, handleMamResponseWithLatestId)];
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
                    [self sendDiscoQueryFor:node.from onAccount:account withJoin:NO];
                    break;
                }
                default:
                    DDLogInfo(@"Got unhandled muc status code in message from %@: %@", node.from, code);
            }
    }
}

+(void) leave:(NSString*) room onAccount:(xmpp*) account withBookmarksUpdate:(BOOL) updateBookmarks
{
    room = [room lowercaseString];
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
    if(nick == nil)
    {
        DDLogError(@"Cannot leave room '%@' on account %@ because nick is nil!", room, account.accountNo);
        return;
    }
    @synchronized(_stateLockObject) {
        if([_joining containsObject:room])
        {
            DDLogInfo(@"Aborting join of room '%@' on account %@", room, account.accountNo);
            [_joining removeObject:room];
        }
    }
    DDLogInfo(@"Leaving room '%@' on account %@ using nick '%@'...", room, account.accountNo, nick);
    //send unsubscribe even if we are not fully joined (join aborted), just to make sure we *really* leave ths muc
    XMPPPresence* presence = [[XMPPPresence alloc] init];
    [presence leaveRoom:room withNick:nick];
    [account send:presence];
    
    //delete muc from favorites table
    [[DataLayer sharedInstance] deleteMuc:room forAccountId:account.accountNo];
    
    //update bookmarks if requested
    if(updateBookmarks)
        [self updateBookmarksForAccount:account];
}

+(void) sendDiscoQueryFor:(NSString*) roomJid onAccount:(xmpp*) account withJoin:(BOOL) join
{
    if(roomJid == nil || account == nil)
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Room jid or account must not be nil!" userInfo:nil];
    roomJid = [roomJid lowercaseString];
    DDLogInfo(@"Querying disco for muc %@...", roomJid);
    //mark room as "joining" as soon as possible to make sure we can handle join "aborts" (e.g. when processing bookmark pdates while a joining disco queryis alead in flight)
    //this will fix race condition that makes us join a muc directly after it got removed from our favorites table and leaved through a bookmark update
    if(join)
    {
        @synchronized(_stateLockObject) {
            //don't join twice
            if([_joining containsObject:roomJid])
            {
                DDLogInfo(@"Already joining muc %@, not doing it twice", roomJid);
                return;
            }
            [_joining addObject:roomJid];       //add room to "currently joining" list
            //we don't need to force saving of our new state because once this outgoing iq query gets handled by smacks the whole state will be saved
        }
    }
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:roomJid];
    [discoInfo setDiscoInfoNode];
    [account sendIq:discoInfo withHandler:$newHandler(self, handleDiscoResponse, $ID(roomJid), $BOOL(join))];
}

+(void) pingAllMucsOnAccount:(xmpp*) account
{
    if([[NSDate date] timeIntervalSinceDate:_lastPing] < 3600)
    {
        DDLogInfo(@"Not pinging all mucs, last ping was less than an hour ago: %@",_lastPing);
        return;
    }
    _lastPing = [NSDate date];
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:account.accountNo])
        [self ping:entry[@"room"] onAccount:account];
}

+(void) ping:(NSString*) roomJid onAccount:(xmpp*) account
{
    if(![[DataLayer sharedInstance] isBuddyMuc:roomJid forAccount:account.accountNo])
    {
        DDLogWarn(@"Tried to muc-ping non-muc jid '%@', trying to join regularily with disco...", roomJid);
        @synchronized(_stateLockObject) {
            [_joining removeObject:roomJid];
        }
        //this will check if this jid really is not a muc and delete it fom favorites and bookmarks, if not (and join normally if it turns out is a muc after all)
        [self sendDiscoQueryFor:roomJid onAccount:account withJoin:YES];
        return;
    }
    
    XMPPIQ* ping = [[XMPPIQ alloc] initWithType:kiqGetType];
    [ping setiqTo:roomJid];
    ping.toResource = [[DataLayer sharedInstance] ownNickNameforMuc:roomJid forAccount:account.accountNo];
    [ping setPing];
    //we don't need to handle this across smacks resumes or reconnects, because a new ping will be issued on the next smacks resume
    //(and full reconnets will rejoin all mucs anyways)
    [account sendIq:ping withResponseHandler:^(XMPPIQ* result) {
        DDLogInfo(@"Muc ping returned: we are still connected, everything is fine");
    } andErrorHandler:^(XMPPIQ* error) {
        if(error == nil)
        {
            DDLogWarn(@"Ping handler for %@ got invalidated, aborting ping...", roomJid);
            return;
        }
        DDLogWarn([HelperTools extractXMPPError:error withDescription:@"Muc ping returned error"]);
        if([error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}not-acceptable"])
        {
            DDLogWarn(@"Ping failed with 'not-acceptable' --> we have to re-join");
            @synchronized(_stateLockObject) {
                [_joining removeObject:roomJid];
            }
            //check if muc is still in our favorites table before we try to join it (could be deleted by a bookmarks updae just after we sent out our ping)
            //this has to be done to avoid such a race condition that would otherwise re-add the muc back
            if([self checkIfStillBookmarked:roomJid onAccount:account])
                [self sendDiscoQueryFor:roomJid onAccount:account withJoin:YES];
            else
                DDLogWarn(@"Not re-joining because this muc got removed from favorites table in the meantime");
        }
        else if(
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}service-unavailable"] ||
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}feature-not-implemented"]
        )
        {
            DDLogInfo(@"The client is joined, but the pinged client does not implement XMPP Ping (XEP-0199) --> do nothing");
        }
        else if([error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            DDLogInfo(@"The client is joined, but the occupant just changed their name (e.g. initiated by a different client) --> do nothing");
        }
        else if(
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}remote-server-not-found"] ||
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}remote-server-timeout"]
        )
        {
            DDLogError(@"The remote server is unreachable for unspecified reasons; this can be a temporary network failure or a server outage. No decision can be made based on this; Treat like a timeout --> do nothing");
        }
        else
        {
            DDLogWarn(@"Any other error happened: The client is probably not joined any more. It should perform a re-join. --> we have to re-join");
            @synchronized(_stateLockObject) {
                [_joining removeObject:roomJid];
            }
            //check if muc is still in our favorites table before we try to join it (could be deleted by a bookmarks updae just after we sent out our ping)
            //this has to be done to avoid such a race condition that would otherwise re-add the muc back
            if([self checkIfStillBookmarked:roomJid onAccount:account])
                [self sendDiscoQueryFor:roomJid onAccount:account withJoin:YES];
            else
                DDLogWarn(@"Not re-joining because this muc got removed from favorites table in the meantime");
        }
    }];
}

$$handler(handleDiscoResponse, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(NSString*, roomJid), $_BOOL(join))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Querying muc info returned an error: %@", [iqNode findFirst:@"error"]);
        @synchronized(_stateLockObject) {
            [_joining removeObject:iqNode.fromUser];
        }
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter groupchat %@", @""), roomJid] forMuc:roomJid withNode:iqNode andAccount:account andIsSevere:YES];
        return;
    }
    NSAssert([iqNode.fromUser isEqualToString:roomJid], @"Disco response jid not matching query jid!");
    
    //extract features
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    
    //check if this is a muc
    if(![features containsObject:@"http://jabber.org/protocol/muc"])
    {
        DDLogError(@"muc disco returned that this jid is not a muc!");
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        [[DataLayer sharedInstance] deleteMuc:iqNode.fromUser forAccountId:account.accountNo];
        [self updateBookmarksForAccount:account];
    
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter groupchat %@: This is not a groupchat!", @""), iqNode.fromUser] forMuc:iqNode.fromUser withNode:nil andAccount:account andIsSevere:YES];
        return;
    }
    
    //the join was aborted by a call to leave
    if(![self isJoining:iqNode.fromUser])
    {
        DDLogWarn(@"Ignoring muc disco result for '%@' on account %@: not joining anymore...", iqNode.fromUser, account.accountNo);
        return;
    }
    
    //extract further muc infos
    XMPPDataForm* dataForm = [iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/{jabber:x:data}x"];
    NSString* mucName = dataForm[@"muc#roomconfig_roomname"];
    NSString* mucType = @"channel";
    //both are needed for omemo, see discussion with holger 2021-01-02/03 -- tmolitor
    if([features containsObject:@"muc_nonanonymous"] && [features containsObject:@"muc_membersonly"])
        mucType = @"group";
    
    //update db with new infos
    if(![[DataLayer sharedInstance] isBuddyMuc:iqNode.fromUser forAccount:account.accountNo])
    {
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:iqNode.fromUser forAccount:account.accountNo];
        //use the account display name as nick, if nothing can be found in buddylist and muc_favorites db tables
        if(!nick)
        {
            nick = [MLContact ownDisplayNameForAccount:account];
            DDLogInfo(@"Using default nick '%@' for room %@", nick, iqNode.fromUser);
        }
        //add new muc buddy (potentially deleting a non-muc buddy having the same jid)
        DDLogInfo(@"Adding new muc %@ using nick '%@' to buddylist...", iqNode.fromUser, nick);
        [[DataLayer sharedInstance] initMuc:iqNode.fromUser forAccountId:account.accountNo andMucNick:nick];
        //add this room to firstJoin list
        @synchronized(_stateLockObject) {
            [_firstJoin addObject:iqNode.fromUser];
        }
    }
    else
    {
        DDLogInfo(@"Clearing muc participants and members tables for %@", iqNode.fromUser);
        [[DataLayer sharedInstance] cleanupMembersAndParticipantsListFor:iqNode.fromUser forAccountId:account.accountNo];
    }
    if(![mucType isEqualToString:[[DataLayer sharedInstance] getMucTypeOfRoom:iqNode.fromUser andAccount:account.accountNo]])
    {
        DDLogInfo(@"Configuring muc %@ to type '%@'...", iqNode.fromUser, mucType);
        [[DataLayer sharedInstance] updateMucTypeTo:mucType forRoom:iqNode.fromUser andAccount:account.accountNo];
    }
    if(mucName && [mucName length])
    {
        MLContact* mucContact = [MLContact createContactFromJid:iqNode.fromUser andAccountNo:account.accountNo];
        if(![mucName isEqualToString:mucContact.fullName])
        {
            DDLogInfo(@"Configuring muc %@ to use name '%@'...", iqNode.fromUser, mucName);
            [[DataLayer sharedInstance] setFullName:mucName forContact:iqNode.fromUser andAccount:account.accountNo];
        }
    }
    
    DDLogDebug(@"Updating muc contact...");
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
        @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountNo:account.accountNo]
    }];
    
    @synchronized(_stateLockObject) {
        _roomFeatures[iqNode.fromUser] = features;
        //we don't need to force saving of our new state because once this incoming iq gets counted by smacks the whole state will be saved
    }
    
    //load members/admins/owners list (even if not joining, because initMuc: above will delee the old list and we always have to refill it)
    DDLogInfo(@"Querying members/admin/owner lists for muc %@...", iqNode.fromUser);
    for(NSString* type in @[@"member", @"admin", @"owner"])
    {
        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
        [discoInfo setiqTo:iqNode.fromUser];
        [discoInfo setMucListQueryFor:type];
        [account sendIq:discoInfo withHandler:$newHandler(self, handleMembersList, $ID(type))];
    }
    
    // now try to join this room if requested
    if(join)
        [self sendJoinPresenceFor:iqNode.fromUser onAccount:account];
$$

+(void) sendJoinPresenceFor:(NSString*) room onAccount:(xmpp*) account
{
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
    DDLogInfo(@"Trying to join muc '%@' with nick '%@' on account %@...", room, nick, account.accountNo);
    @synchronized(_stateLockObject) {
        [_joining addObject:room];       //add room to "currently joining" list
        //we don't need to force saving of our new state because once this outgoing join presence gets handled by smacks the whole state will be saved
    }
    
    XMPPPresence* presence = [[XMPPPresence alloc] init];
    [presence joinRoom:room withNick:nick];
    [account send:presence];
}

$$handler(handleMembersList, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(NSString*, type))
    DDLogInfo(@"Got %@s list from %@...", type, iqNode.fromUser);
    for(NSDictionary* entry in [iqNode find:@"{http://jabber.org/protocol/muc#admin}query/item@@"])
    {
        NSMutableDictionary* item = [entry mutableCopy];
        if(!item)
            continue;
        //update jid to be a bare jid and add muc nick to our dict
        if(item[@"jid"])
            item[@"jid"] = [HelperTools splitJid:item[@"jid"]][@"user"];
        [[DataLayer sharedInstance] addMember:item toMuc:iqNode.fromUser forAccountId:account.accountNo];
    }
$$

$$handler(handleMamResponseWithLatestId, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Muc mam latest stanzaid query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query newest stanzaid for groupchat %@", @""), iqNode.fromUser] withNode:iqNode andAccount:account andIsSevere:YES];
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
        [[DataLayer sharedInstance] setLastStanzaId:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"] forMuc:iqNode.fromUser andAccount:account.accountNo];
$$

$$handler(handleCatchup, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_BOOL(secondTry))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Muc mam catchup query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        
        //handle weird XEP-0313 monkey-patching XEP-0059 behaviour (WHY THE HELL??)
        if(!secondTry && [iqNode check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
            [mamQuery setiqTo:iqNode.fromUser];
            DDLogInfo(@"Querying COMPLETE muc mam:2 archive for catchup");
            [mamQuery setCompleteMAMQuery];
            [account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, YES))];
        }
        else
            [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query new messages for groupchat %@", @""), iqNode.fromUser] withNode:iqNode andAccount:account andIsSevere:YES];
        return;
    }
    if(![[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue] && [iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
    {
        DDLogVerbose(@"Paging through muc mam catchup results with after: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
        [pageQuery setMAMQueryAfter:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]];
        [pageQuery setiqTo:iqNode.fromUser];
        [account sendIq:pageQuery withHandler:$newHandler(self, handleCatchup)];
    }
    else if([[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue])
        DDLogVerbose(@"Muc mam catchup finished");
$$

+(void) handleError:(NSString*) description forMuc:(NSString*) room withNode:(XMPPStanza*) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere
{
    monal_id_block_t uiHandler = [self getUIHandlerForMuc:room];
    //call ui handler if registered for this room
    if(uiHandler)
    {
        //remove handler (it will only be called once)
        [self removeUIHandlerForMuc:room];
        
        //prepare data
        NSString* message = [HelperTools extractXMPPError:node withDescription:description];
        NSDictionary* data = @{
            @"success": @NO,
            @"muc": room,
            @"errorMessage": message
        };
        
        DDLogInfo(@"Calling UI error handler with %@", data);
        dispatch_async(dispatch_get_main_queue(), ^{
            uiHandler(data);
        });
    }
    //otherwise call the general error handler
    else
        [HelperTools postError:description withNode:node andAccount:account andIsSevere:isSevere];
}

+(void) updateBookmarksForAccount:(xmpp*) account
{
#ifdef IS_ALPHA
    [account.pubsub fetchNode:@"storage:bookmarks" from:account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, handleBookarksFetchResult)];
#endif
}

+(BOOL) checkIfStillBookmarked:(NSString*) room onAccount:(xmpp*) account
{
    room = [room lowercaseString];
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:account.accountNo])
        if([room isEqualToString:[entry[@"room"] lowercaseString]])
            return YES;
    return NO;
}

@end
