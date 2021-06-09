//
//  MLPubSubProcessor.m
//  monalxmpp
//
//  Created by Thilo Molitor on 31.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MLConstants.h"
#import "MLPubSubProcessor.h"
#import "MLPubSub.h"
#import "MLHandler.h"
#import "xmpp.h"
#import "DataLayer.h"
#import "MLImageManager.h"
#import "MLNotificationQueue.h"
#import "MLMucProcessor.h"
#import "XMPPIQ.h"

@interface MLPubSubProcessor()

@end

@interface MLMucProcessor ()
+(void) sendDiscoQueryFor:(NSString*) roomJid onAccount:(xmpp*) account withJoin:(BOOL) join andBookmarksUpdate:(BOOL) updateBookmarks;
+(void) sendJoinPresenceFor:(NSString*) room onAccount:(xmpp*) account;
+(NSString*) calculateNickForMuc:(NSString*) room onAccount:(xmpp*) account;
@end

@implementation MLPubSubProcessor

$$handler(avatarHandler, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(NSString*, type), $_ID(NSDictionary*, data))
    DDLogDebug(@"Got new avatar metadata from '%@'", jid);
    if([type isEqualToString:@"publish"])
    {
        for(NSString* entry in data)
        {
            NSString* avatarHash = [data[entry] findFirst:@"{urn:xmpp:avatar:metadata}metadata/info@id"];
            if(!avatarHash)     //the user disabled his avatar
            {
                DDLogInfo(@"User %@ disabled his avatar", jid);
                [[MLImageManager sharedInstance] setIconForContact:jid andAccount:account.accountNo WithData:nil];
                [[DataLayer sharedInstance] setAvatarHash:@"" forContact:jid andAccount:account.accountNo];
            }
            else
            {
                NSString* currentHash = [[DataLayer sharedInstance] getAvatarHashForContact:jid andAccount:account.accountNo];
                if(currentHash && [avatarHash isEqualToString:currentHash])
                {
                    DDLogInfo(@"Avatar hash is the same, we don't need to update our avatar image data");
                    break;
                }
                [account.pubsub fetchNode:@"urn:xmpp:avatar:data" from:jid withItemsList:@[avatarHash] andHandler:$newHandler(self, handleAvatarFetchResult)];
            }
            break;      //we only want to process the first item (this should also be the only item)
        }
        if([data count] > 1)
            DDLogWarn(@"Got more than one avatar metadata item!");
    }
    else
    {
        DDLogInfo(@"User %@ disabled his avatar", jid);
        [[MLImageManager sharedInstance] setIconForContact:jid andAccount:account.accountNo WithData:nil];
        [[DataLayer sharedInstance] setAvatarHash:@"" forContact:jid andAccount:account.accountNo];
    }
$$

$$handler(handleAvatarFetchResult, $_ID(xmpp*, account), $_BOOL(success), $_ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(XMPPIQ*, errorReason), $_ID(NSDictionary*, data))
    //ignore errors here (e.g. simply don't update the avatar image)
    //(this should never happen if other clients and servers behave properly)
    if(!success)
    {
        DDLogWarn(@"Got avatar image fetch error from jid %@: errorIq=%@, errorReason=%@", jid, errorIq, errorReason);
        return;
    }
    
    for(NSString* avatarHash in data)
    {
        [[MLImageManager sharedInstance] setIconForContact:jid andAccount:account.accountNo WithData:[data[avatarHash] findFirst:@"{urn:xmpp:avatar:data}data#|base64"]];
        [[DataLayer sharedInstance] setAvatarHash:avatarHash forContact:jid andAccount:account.accountNo];
        [account accountStatusChanged];     //inform ui of this change (accountStatusChanged will force a ui reload which will also reload the avatars)
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
            @"contact": [MLContact createContactFromJid:jid andAccountNo:account.accountNo]
        }];
        DDLogInfo(@"Avatar of '%@' fetched and updated successfully", jid);
    }
$$

$$handler(rosterNameHandler, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(NSString*, type), $_ID(NSDictionary*, data))
    //new/updated nickname
    if([type isEqualToString:@"publish"])
    {
        for(NSString* itemId in data)
        {
            if([jid isEqualToString:account.connectionProperties.identity.jid])        //own roster name
            {
                DDLogInfo(@"Got own nickname: %@", [data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"]);
                NSMutableDictionary* accountDic = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountNo] copyItems:YES];
                accountDic[kRosterName] = [data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"];
                [[DataLayer sharedInstance] updateAccounWithDictionary:accountDic];
            }
            else                                                                    //roster name of contact
            {
                DDLogInfo(@"Got nickname of %@: %@", jid, [data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"]);
                [[DataLayer sharedInstance] setFullName:[data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"] forContact:jid andAccount:account.accountNo];
                MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
                if(contact)     //ignore updates for jids not in our roster
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                        @"contact": contact
                    }];
            }
            break;      //we only need the first item (there should be only one item in the first place)
        }
    }
    //deleted/purged node or retracted item
    else
    {
        if([jid isEqualToString:account.connectionProperties.identity.jid])        //own roster name
        {
            DDLogInfo(@"Own nickname got retracted");
            NSMutableDictionary* accountDic = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountNo] copyItems:NO];
            accountDic[kRosterName] = @"";
            [[DataLayer sharedInstance] updateAccounWithDictionary:accountDic];
        }
        else
        {
            DDLogInfo(@"Nickname of %@ got retracted", jid);
            [[DataLayer sharedInstance] setFullName:@"" forContact:jid andAccount:account.accountNo];
            MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
            if(contact)     //ignore updates for jids not in our roster
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                    @"contact": contact
                }];
        }
    }
$$

$$handler(bookmarksHandler, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(NSString*, type), $_ID(NSDictionary*, data))
    if(![jid isEqualToString:account.connectionProperties.identity.jid])
    {
        DDLogWarn(@"Ignoring bookmarks update not coming from our own jid");
        return;
    }
    
    NSMutableDictionary* ownFavorites = [[NSMutableDictionary alloc] init];
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:account.accountNo])
        ownFavorites[entry[@"room"]] = entry;
    
    //new/updated bookmarks
    if([type isEqualToString:@"publish"])
    {
        for(NSString* itemId in data)
        {
            //iterate through all conference elements provided
            NSMutableSet* bookmarkedMucs = [[NSMutableSet alloc] init];
            for(MLXMLNode* conference in [data[itemId] find:@"{storage:bookmarks}storage/conference"])
            {
                //we ignore the conference name (the name will be taken from the muc itself)
                //NSString* name = [conference findFirst:@"/@name"];
                NSString* room = [[conference findFirst:@"/@jid"] lowercaseString];
                //ignore non-xep-compliant entries
                if(!room)
                {
                    DDLogError(@"Received non-xep-compliant bookmarks entry, ignoring: %@", conference);
                    continue;
                }
                [bookmarkedMucs addObject:room];
                NSString* nick = [conference findFirst:@"nick#"];
                NSNumber* autojoin = [conference findFirst:@"/@autojoin|bool"];
                if(autojoin == nil)
                    autojoin = @NO;     //default value specified in xep
                
                //check if this is a new entry with autojoin=true
                if(ownFavorites[room] == nil && [autojoin boolValue])
                {
                    DDLogInfo(@"Entering muc '%@' on account %@ because it got added to bookmarks...", room, account.accountNo);
                    //make sure we update our favorites table right away, to counter any race conditions when joining multiple mucs with one bookmarks update
                    if(nick == nil)
                        nick = [MLMucProcessor calculateNickForMuc:room onAccount:account];
                    [[DataLayer sharedInstance] addMucFavorite:room forAccountId:account.accountNo andMucNick:nick];
                    //try to join muc, but don't perform a bookmarks update (this muc came in through a bookmark already)
                    [MLMucProcessor sendDiscoQueryFor:room onAccount:account withJoin:YES andBookmarksUpdate:NO];
                }
                //check if it is a known entry that changed autojoin to false
                else if(ownFavorites[room] != nil && ![autojoin boolValue])
                {
                    DDLogInfo(@"Leaving muc '%@' on account %@ because not listed as autojoin=true in bookmarks...", room, account.accountNo);
                    //delete local favorites entry and leave room afterwards
                    [[DataLayer sharedInstance] deleteMuc:room forAccountId:account.accountNo];
                    [MLMucProcessor leave:room onAccount:account withBookmarksUpdate:NO];
                }
                //check for nickname changes
                else if(ownFavorites[room] != nil && nick != nil)
                {
                    NSString* oldNick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
                    if(![nick isEqualToString:oldNick])
                    {
                        DDLogInfo(@"Updating muc '%@' nick on account %@ in database to nick provided by bookmarks: '%@'...", room, account.accountNo, nick);
                        
                        //update muc nickname in database
                        [[DataLayer sharedInstance] updateOwnNickName:nick forMuc:room forAccount:account.accountNo];
                        [[DataLayer sharedInstance] addMucFavorite:room forAccountId:account.accountNo andMucNick:nick];        //this will upate the already existing favorites entry
                        
                        //rejoin the muc (e.g. change nick)
                        //we don't have to do a full disco because we are sure this is a real muc and we are joined already
                        //(only real mucs are part of our local favorites list and this list is joined automatically)
                        [MLMucProcessor sendJoinPresenceFor:room onAccount:account];
                    }
                }
            }
            
            //remove and leave all mucs removed from bookmarks
            NSMutableSet* toLeave = [NSMutableSet setWithArray:[ownFavorites allKeys]];
            [toLeave  minusSet:bookmarkedMucs];
            for(NSString* room in toLeave)
            {
                DDLogInfo(@"Leaving muc '%@' on account %@ because not listed in bookmarks anymore...", room, account.accountNo);
                //delete local favorites entry and leave room afterwards
                [[DataLayer sharedInstance] deleteMuc:room forAccountId:account.accountNo];
                [MLMucProcessor leave:room onAccount:account withBookmarksUpdate:NO];
            }
            
            return;      //we only need the first pep item (there should be only one item in the first place)
        }
        //FALLTHROUGH to "delete all" if no item was found
    }
    //deleted/purged node or retracted item (e.g. all bookmarks deleted)
    //--> remove and leave all mucs
    for(NSString* room in ownFavorites)
    {
        DDLogInfo(@"Leaving muc '%@' on account %@ because all bookmarks got deleted...", room, account.accountNo);
        //delete local favorites entry and leave room afterwards
        [[DataLayer sharedInstance] deleteMuc:room forAccountId:account.accountNo];
        [MLMucProcessor leave:room onAccount:account withBookmarksUpdate:NO];
    }
$$

$$handler(handleBookarksFetchResult, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID(NSDictionary*, data))
    if(!success)
    {
        //item-not-found means: no bookmarks in storage --> use an empty data dict
        if([errorIq check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
            data = @{};
        else
        {
            DDLogWarn(@"Could not fetch bookmarks from pep prior to publishing!");
            [self handleErrorWithDescription:NSLocalizedString(@"Failed to save groupchat bookmarks", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
            return;
        }
    }
    
    BOOL changed = NO;
    NSMutableDictionary* ownFavorites = [[NSMutableDictionary alloc] init];
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:account.accountNo])
        ownFavorites[entry[@"room"]] = entry;
    
    for(NSString* itemId in data)
    {
        //ignore non-xep-compliant data and continue as if no data was received at all
        if(![data[itemId] check:@"{storage:bookmarks}storage"])
        {
            DDLogError(@"Received non-xep-compliant bookmarks data: %@", data);
            break;
        }
        
        NSMutableSet* bookmarkedMucs = [[NSMutableSet alloc] init];
        for(MLXMLNode* conference in [data[itemId] find:@"{storage:bookmarks}storage/conference"])
        {
            //we ignore the conference name (the name will be taken from the muc itself)
            //NSString* name = [conference findFirst:@"/@name"];
            NSString* room = [[conference findFirst:@"/@jid"] lowercaseString];
            //ignore non-xep-compliant entries
            if(!room)
            {
                DDLogError(@"Received non-xep-compliant bookmarks entry, ignoring: %@", conference);
                continue;
            }
            [bookmarkedMucs addObject:room];
            NSNumber* autojoin = [conference findFirst:@"/@autojoin|bool"];
            if(autojoin == nil)
                autojoin = @NO;     //default value specified in xep
            
            //check if the bookmark exists with autojoin==false and only update the autojoin and nick values, if true
            if(ownFavorites[room] && ![autojoin boolValue])
            {
                DDLogInfo(@"Updating autojoin of bookmarked muc '%@' on account %@ to 'true'...", room, account.accountNo);
                
                //add or update nickname
                if(![conference check:@"nick"])
                    [conference addChild:[[MLXMLNode alloc] initWithElement:@"nick"]];
                ((MLXMLNode*)[conference findFirst:@"nick"]).data = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
                
                //update autojoin value to true
                conference.attributes[@"autojoin"] = @"true";
                changed = YES;
            }
        }
        
        //add all mucs not yet listed in bookmarks
        NSMutableSet* toAdd = [NSMutableSet setWithArray:[ownFavorites allKeys]];
        [toAdd  minusSet:bookmarkedMucs];
        for(NSString* room in toAdd)
        {
            DDLogInfo(@"Adding muc '%@' on account %@ to bookmarks...", room, account.accountNo);
            [[data[itemId] findFirst:@"{storage:bookmarks}storage"] addChild:[[MLXMLNode alloc] initWithElement:@"conference" withAttributes:@{
                @"jid": room,
                @"name": [[MLContact createContactFromJid:room andAccountNo:account.accountNo] contactDisplayName],
                @"autojoin": @"true",
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"nick" withAttributes:@{} andChildren:@[] andData:[[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo]]
            ] andData:nil]];
            changed = YES;
        }
        
        //remove all mucs not listed in local favorites table
        NSMutableSet* toRemove = [bookmarkedMucs mutableCopy];
        [toRemove  minusSet:[NSMutableSet setWithArray:[ownFavorites allKeys]]];
        for(NSString* room in toRemove)
        {
            DDLogInfo(@"Removing muc '%@' on account %@ from bookmarks...", room, account.accountNo);
            [[data[itemId] findFirst:@"{storage:bookmarks}storage"] removeChild:[data[itemId] findFirst:[NSString stringWithFormat:@"{storage:bookmarks}storage/conference<jid=%@>", room]]];
            changed = YES;
        }
        
        //publish new bookmarks if something was changed
        if(changed)
            [account.pubsub publishItem:data[itemId] onNode:@"storage:bookmarks" withConfigOptions:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": @"whitelist"
            } andHandler:$newHandler(self, bookmarksPublished)];
        
        //we only need the first pep item (there should be only one item in the first place)
        return;
    }
    
    //don't publish an empty bookmarks node if there is nothing to publish at all
    if([ownFavorites count] == 0)
    {
        DDLogInfo(@"neither a pep item was found, nor do we have any local mu favorites: don't publish anything");
        return;
    }
    
    DDLogInfo(@"no pep item was found: publish our bookmarks the first time");
    NSMutableArray* conferences = [[NSMutableArray alloc] init];
    for(NSString* room in ownFavorites)
    {
        DDLogInfo(@"Adding muc '%@' on account %@ to bookmarks...", room, account.accountNo);
        [conferences addObject:[[MLXMLNode alloc] initWithElement:@"conference" withAttributes:@{
            @"jid": room,
            @"name": [[MLContact createContactFromJid:room andAccountNo:account.accountNo] contactDisplayName],
            @"autojoin": @"true",
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"nick" withAttributes:@{} andChildren:@[] andData:[[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo]]
        ] andData:nil]];
    }
    [account.pubsub publishItem:
        [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": @"current"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"storage" andNamespace:@"storage:bookmarks" withAttributes:@{} andChildren:conferences andData:nil]
        ] andData:nil]
    onNode:@"storage:bookmarks" withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"whitelist"
    } andHandler:$newHandler(self, bookmarksPublished)];
$$

$$handler(bookmarksPublished, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        DDLogWarn(@"Could not publish bookmarks to pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to save groupchat bookmarks", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
        return;
    }
$$

$$handler(rosterNamePublished, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        DDLogWarn(@"Could not publish roster name to pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to publish own nickname on account %@", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
$$

$$handler(avatarDeleted, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        DDLogWarn(@"Could not delete avatar image from pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to delete own avatar on account %@", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
$$

$$handler(avatarMetadataPublished, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        DDLogWarn(@"Could not publish avatar metadata to pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to publish own avatar on account %@", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
$$

$$handler(avatarDataPublished, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID(NSString*, imageHash), $_ID(NSData*, imageData))
    if(!success)
    {
        DDLogWarn(@"Could not publish avatar image data for hash %@!", imageHash);
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to publish own avatar on account %@", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
    
    DDLogInfo(@"Avatar image data for hash %@ published successfully, now publishing metadata", imageHash);
    
    //publish metadata node (must be done *after* publishing the new data node)
    [account.pubsub publishItem:
        [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": imageHash} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"metadata" andNamespace:@"urn:xmpp:avatar:metadata" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"info" withAttributes:@{
                    @"id": imageHash,
                    @"type": @"image/jpeg",
                    @"bytes": [NSString stringWithFormat:@"%lu", (unsigned long)imageData.length]
                } andChildren:@[] andData:nil]
            ] andData:nil]
        ] andData:nil]
    onNode:@"urn:xmpp:avatar:metadata" withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"presence"
    } andHandler:$newHandler(self, avatarMetadataPublished)];
$$

+(void) handleErrorWithDescription:(NSString*) description andAccount:(xmpp*) account andErrorIq:(XMPPIQ*) errorIq andErrorReason:(NSString*) errorReason andIsSevere:(BOOL) isSevere
{
    NSAssert(errorIq || errorReason, @"at least one of errorIq or errorReason must be set when calling error handler!");
    if(errorIq)
        [HelperTools postError:description withNode:errorIq andAccount:account andIsSevere:isSevere];
    else if(errorReason)
        [HelperTools postError:[NSString stringWithFormat:@"%@: %@", description, errorReason] withNode:nil andAccount:account andIsSevere:isSevere];
}

@end
