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
#import "HelperTools.h"

@interface MLPubSubProcessor()

@end

@interface MLMucProcessor ()
-(void) sendDiscoQueryFor:(NSString*) roomJid withJoin:(BOOL) join andBookmarksUpdate:(BOOL) updateBookmarks;
-(void) sendJoinPresenceFor:(NSString*) room;
-(NSString*) calculateNickForMuc:(NSString*) room;
@end

@implementation MLPubSubProcessor

$$class_handler(mdsHandler, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    DDLogDebug(@"Got new mds displayed status from '%@' (should be own jid)...", jid);
    if(![jid isEqualToString:account.connectionProperties.identity.jid])
    {
        DDLogWarn(@"Ignoring mds update not coming from our own jid");
        return;
    }
    
    if([type isEqualToString:@"publish"])
        [account updateMdsData:data];
$$

$$class_handler(handleMdsFetchResult, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    if(!success)
    {
        //item-not-found means: no mds items in storage --> use an empty data dict
        if([errorIq check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
            data = @{};
        else
        {
            DDLogWarn(@"Could not fetch mds from pep, doing nothing!");
            return;
        }
    }
    
    //call +notify handler to process our data dictionary containing all mds items
    [account updateMdsData:data];
$$

$$class_handler(avatarHandler, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    DDLogDebug(@"Got new avatar metadata from '%@'", jid);
    if([type isEqualToString:@"publish"])
    {
        for(NSString* entry in data)
        {
            MLXMLNode* metadata = [data[entry] findFirst:@"{urn:xmpp:avatar:metadata}metadata/info"];
            NSString* avatarHash = [metadata findFirst:@"/@id"];
            if(!avatarHash)     //the user disabled his avatar
            {
                DDLogInfo(@"User '%@' disabled his avatar", jid);
                [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:jid andAccountNo:account.accountNo] WithData:nil];
                [[DataLayer sharedInstance] setAvatarHash:@"" forContact:jid andAccount:account.accountNo];
                //delete cache to make sure the image will be regenerated
                [[MLImageManager sharedInstance] purgeCacheForContact:jid andAccount:account.accountNo];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                    @"contact": [MLContact createContactFromJid:jid andAccountNo:account.accountNo]
                }];
            }
            else
            {
                NSString* currentHash = [[DataLayer sharedInstance] getAvatarHashForContact:jid andAccount:account.accountNo];
                if(currentHash && [avatarHash isEqualToString:currentHash])
                {
                    DDLogInfo(@"Avatar hash of '%@' is the same, we don't need to update our avatar image data", jid);
                    break;
                }
                //only allow a maximum of 72KiB of image data when in appex due to appex memory limits
                //--> ignore metadata elements bigger than this size and only hande them once not in appex anymore
                NSUInteger avatarByteSize = [[metadata findFirst:@"/@bytes|int"] unsignedIntegerValue];
                if(![HelperTools isAppExtension] || avatarByteSize < 128 * 1024)
                    [account.pubsub fetchNode:@"urn:xmpp:avatar:data" from:jid withItemsList:@[avatarHash] andHandler:$newHandler(self, handleAvatarFetchResult, $ID(metadata))];
                else
                {
                    DDLogWarn(@"Not loading avatar image of '%@' because it is too big to be handled in appex (%lu bytes), rescheduling it to be fetched in mainapp", jid, (unsigned long)avatarByteSize);
                    [account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid), $ID(avatarHash), $ID(metadata))];
                }
            }
            break;      //we only want to process the first item (this should also be the only item)
        }
        if([data count] > 1)
            DDLogWarn(@"Got more than one avatar metadata item!");
    }
    else
    {
        DDLogInfo(@"User %@ disabled his avatar", jid);
        [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:jid andAccountNo:account.accountNo] WithData:nil];
        [[DataLayer sharedInstance] setAvatarHash:@"" forContact:jid andAccount:account.accountNo];
        //delete cache to make sure the image will be regenerated
        [[MLImageManager sharedInstance] purgeCacheForContact:jid andAccount:account.accountNo];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
            @"contact": [MLContact createContactFromJid:jid andAccountNo:account.accountNo]
        }];
    }
$$

//this handler will simply retry the fetchNode for urn:xmpp:avatar:data if in mainapp
$$class_handler(fetchAvatarAgain, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSString*, avatarHash), $$ID(MLXMLNode*, metadata))
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"Not loading avatar image of '%@' because we are still in appex, rescheduling it again!", jid);
        [account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid), $ID(avatarHash), $ID(metadata))];
    }
    else
        [account.pubsub fetchNode:@"urn:xmpp:avatar:data" from:jid withItemsList:@[avatarHash] andHandler:$newHandler(self, handleAvatarFetchResult, $ID(metadata))];
$$

$$class_handler(handleAvatarFetchResult, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(XMPPIQ*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data), $$ID(MLXMLNode*, metadata))
    //ignore errors here (e.g. simply don't update the avatar image)
    //(this should never happen if other clients and servers behave properly)
    if(!success)
    {
        DDLogWarn(@"Got avatar image fetch error from jid %@: errorIq=%@, errorReason=%@", jid, errorIq, errorReason);
        return;
    }
    
    for(NSString* avatarHash in data)
    {
        //this should be small enough to not crash the appex when loading the image from file later on but large enough to have excellent quality
        NSData* avatarData = [data[avatarHash] findFirst:@"{urn:xmpp:avatar:data}data#|base64"];
        UIImage* image = nil;
        if([[metadata findFirst:@"/@type"] hasPrefix:@"image/svg"])
        {
            if(@available(iOS 16.0, macCatalyst 16.0, *))
            {
                image = [HelperTools renderUIImageFromSVGData:avatarData];
                //the uiimage is somehow mirrored at the X-axis when received by appex --> mirror it back
                if([HelperTools isAppExtension])
                {
                    DDLogDebug(@"We are in appex: mirroring UNNotificationAttachment image on Y axis...");
                    image = [HelperTools mirrorImageOnXAxis:image];
                }
            }
        }
        else
            image = [UIImage imageWithData:avatarData];
        if(image == nil)
        {
            DDLogWarn(@"Failed to load avatar of %@", jid);
            return;
        }
        //this upper limit is roughly 1.4MiB memory (600x600 with 4 byte per pixel)
        if(![HelperTools isAppExtension] || image.size.width * image.size.height < 600 * 600)
        {
            NSData* imageData = [HelperTools resizeAvatarImage:image withCircularMask:YES toMaxBase64Size:256000];
            [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:jid andAccountNo:account.accountNo] WithData:imageData];
            [[DataLayer sharedInstance] setAvatarHash:avatarHash forContact:jid andAccount:account.accountNo];
            //delete cache to make sure the image will be regenerated
            [[MLImageManager sharedInstance] purgeCacheForContact:jid andAccount:account.accountNo];
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": [MLContact createContactFromJid:jid andAccountNo:account.accountNo]
            }];
            DDLogInfo(@"Avatar of '%@' fetched and updated successfully", jid);
        }
        else
        {
            DDLogWarn(@"Not loading avatar image of '%@' because it is too big to be processed in appex (%lux%lu pixels), rescheduling it to be fetched in mainapp", jid, (unsigned long)image.size.width, (unsigned long)image.size.height);
            [account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid), $ID(avatarHash), $ID(metadata))];
        }
    }
$$

$$class_handler(rosterNameHandler, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
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
                {
                    //delete cache to make sure the image will be regenerated
                    [[MLImageManager sharedInstance] purgeCacheForContact:jid andAccount:account.accountNo];
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                        @"contact": contact
                    }];
                }
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
            {
                //delete cache to make sure the image will be regenerated
                [[MLImageManager sharedInstance] purgeCacheForContact:jid andAccount:account.accountNo];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                    @"contact": contact
                }];
            }
        }
    }
$$

$$class_handler(bookmarks2Handler, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    if(!account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogWarn(@"Ignoring new XEP-0402 bookmarks, server does not support syncing between XEP-0048 and XEP-0402!");
        return;
    }
    
    //type will be "publish", "retract", "purge" or "delete". "publish" and "retract" will have the data dictionary filled with id --> data pairs
    //the data for "publish" is the item node with the given id, the data for "retract" is always @YES
    if(![jid isEqualToString:account.connectionProperties.identity.jid])
    {
        DDLogWarn(@"Ignoring bookmarks update not coming from our own jid");
        return;
    }
    
    NSSet* ownFavorites = [[DataLayer sharedInstance] listMucsForAccount:account.accountNo];
    
    //new/updated bookmarks
    if([type isEqualToString:@"publish"])
    {
        //iterate through all conference elements provided
        for(NSString* itemId in data)
        {
            //we ignore the conference name (the name will be taken from the muc itself)
            //NSString* name = [data[itemId] findFirst:@"{urn:xmpp:bookmarks:1}conference@name"];
            NSString* room = [itemId lowercaseString];
            NSString* nick = [data[itemId] findFirst:@"{urn:xmpp:bookmarks:1}conference/nick#"];
            //ignore password protected mucs
            if([data[itemId] check:@"{urn:xmpp:bookmarks:1}conference/password"])
                continue;
            NSNumber* autojoin = [data[itemId] findFirst:@"{urn:xmpp:bookmarks:1}conference@autojoin|bool"];
            if(autojoin == nil)
                autojoin = @NO;     //default value specified in xep
            
            //check if this is a new entry with autojoin=true
            if(![ownFavorites containsObject:room] && [autojoin boolValue])
            {
                DDLogInfo(@"Entering muc '%@' on account %@ because it got added to bookmarks...", room, account.accountNo);
                //make sure we update our favorites table right away, to counter any race conditions when joining multiple mucs with one bookmarks update
                if(nick == nil)
                    nick = [account.mucProcessor calculateNickForMuc:room];
                //this will record the desired nickname: the mucProcessor will pick that up and use it to join the muc
                [[DataLayer sharedInstance] addMucFavorite:room forAccountId:account.accountNo andMucNick:nick];
                //try to join muc, but don't perform a bookmarks update (this muc came in through a bookmark already)
                [account.mucProcessor sendDiscoQueryFor:room withJoin:YES andBookmarksUpdate:NO];
            }
            //check if it is a known entry that changed autojoin to false
            else if([ownFavorites containsObject:room] && ![autojoin boolValue])
            {
                DDLogInfo(@"Leaving muc '%@' on account %@ because not listed as autojoin=true in bookmarks...", room, account.accountNo);
                //delete local favorites entry and leave room afterwards, but keep buddylist entry because only the autojoin flag changed
                [account.mucProcessor leave:room withBookmarksUpdate:NO keepBuddylistEntry:YES];
            }
            //check for nickname changes
            else if([ownFavorites containsObject:room] && nick != nil)
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
                    [account.mucProcessor sendJoinPresenceFor:room];
                }
            }
        }
    }
    else if([type isEqualToString:@"retract"])
    {
        for(NSString* itemId in data)
        {
            NSString* room = [itemId lowercaseString];
            if([ownFavorites containsObject:room])
            {
                DDLogInfo(@"Leaving muc '%@' on account %@ because not listed in bookmarks anymore...", room, account.accountNo);
                //delete local favorites entry and leave room afterwards
                [account.mucProcessor leave:room withBookmarksUpdate:NO keepBuddylistEntry:NO];
            }
            else
                DDLogVerbose(@"Ignoring retracted bookmark because not listed in muc_favorites already...");
        }
    }
    else
    {
        //deleted/purged node (e.g. all bookmarks deleted)
        //--> remove and leave all mucs
        for(NSString* room in ownFavorites)
        {
            DDLogInfo(@"Leaving muc '%@' on account %@ because all bookmarks got deleted...", room, account.accountNo);
            //delete local favorites entry and leave room afterwards
            [account.mucProcessor leave:room withBookmarksUpdate:NO keepBuddylistEntry:NO];
        }
    }
$$

$$class_handler(handleBookmarks2FetchResult, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    if(!account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogWarn(@"Ignoring new XEP-0402 bookmarks, server does not support syncing between XEP-0048 and XEP-0402!");
        return;
    }
    
    if(!success)
    {
        //item-not-found means: no bookmarks in storage --> use an empty data dict
        if([errorIq check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
            data = @{};
        else
        {
            DDLogWarn(@"Could not fetch bookmarks from pep prior to publishing!");
            [self handleErrorWithDescription:NSLocalizedString(@"Failed to save groupchat bookmarks", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
            return;
        }
    }
    
    NSString* max_items = @"255";       //fallback for servers not supporting "max"
    if(account.connectionProperties.supportsPubSubMax)
        max_items = @"max";
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    
    NSSet* ownFavorites = [[DataLayer sharedInstance] listMucsForAccount:account.accountNo];
    DDLogVerbose(@"Own favorites: %@", ownFavorites);
    
    //filter passwort protected mucs and make sure jids (the item ids) are always lowercase
    NSMutableDictionary* _data = [NSMutableDictionary new];
    for(NSString* itemId in data)
    {
        if([data[itemId] check:@"{urn:xmpp:bookmarks:1}conference/password"])
        {
            DDLogVerbose(@"Not copying muc %@ to bookmark data: password protected", itemId);
            continue;
        }
        _data[[itemId lowercaseString]] = data[itemId];
    }
    DDLogVerbose(@"Mucs listed in bookmarks2: %@", [_data allKeys]);
    
    //handle all changes of existing bookmarks
    for(NSString* room in _data)
    {
        MLXMLNode* item = _data[room];
        
        //we ignore the conference name (the name will be taken from the muc itself)
        //NSString* name = [_data[room] findFirst:@"{urn:xmpp:bookmarks:1}conference@name"];
        //NSString* nick = [_data[room] findFirst:@"{urn:xmpp:bookmarks:1}conference/nick#"];
        NSNumber* autojoin = [item findFirst:@"{urn:xmpp:bookmarks:1}conference@autojoin|bool"];
        if(autojoin == nil)
            autojoin = @NO;     //default value specified in xep
        
        //check if the bookmark exists with autojoin==false and only update the autojoin and nick values, if true
        if([ownFavorites containsObject:room] && ![autojoin boolValue])
        {
            DDLogInfo(@"Updating autojoin of bookmarked muc '%@' on account %@ to 'true'...", room, account.accountNo);
            
            //add or update nickname
            NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
            if(nick != nil)
            {
                if(![item check:@"{urn:xmpp:bookmarks:1}conference/nick"])
                    [[item findFirst:@"{urn:xmpp:bookmarks:1}conference"] addChildNode:[[MLXMLNode alloc] initWithElement:@"nick"]];
                ((MLXMLNode*)[item findFirst:@"{urn:xmpp:bookmarks:1}conference/nick"]).data = nick;
            }
            
            //update autojoin value to true
            ((MLXMLNode*)[item findFirst:@"{urn:xmpp:bookmarks:1}conference"]).attributes[@"autojoin"] = @"true";
            
            //publish this bookmark item again
            [account.pubsub publishItem:item onNode:@"urn:xmpp:bookmarks:1" withConfigOptions:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": @"whitelist",
                @"pubsub#max_items": max_items,
            } andHandler:$newHandler(self, bookmarks2Published, $ID(room))];
        }
    }
        
    //add all mucs not yet listed in bookmarks
    NSMutableSet* toAdd = [ownFavorites mutableCopy];
    [toAdd  minusSet:[NSSet setWithArray:[_data allKeys]]];
    for(NSString* room in toAdd)
    {
        DDLogInfo(@"Adding muc '%@' on account %@ to bookmarks...", room, account.accountNo);
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
        [account.pubsub publishItem:
            [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": room} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"conference" andNamespace:@"urn:xmpp:bookmarks:1" withAttributes:@{
                    @"autojoin": @"true",
                } andChildren:@[
                    nilWrapper(nick != nil ? [[MLXMLNode alloc] initWithElement:@"nick" withAttributes:@{} andChildren:@[] andData:nick] : nil),
                    [[MLXMLNode alloc] initWithElement:@"extensions" withAttributes:@{} andChildren:@[
                        [[MLXMLNode alloc] initWithElement:@"added-by" andNamespace:@"urn:monal.im:bookmarks:info" withAttributes:@{
                            @"name": @"Monal",
                            @"version": infoDict[@"CFBundleShortVersionString"],
                            @"build": infoDict[@"CFBundleVersion"],
                        } andChildren:@[] andData:nil]
                    ] andData:nil]
                ]andData:nil]
            ] andData:nil]
        onNode:@"urn:xmpp:bookmarks:1" withConfigOptions:@{
            @"pubsub#persist_items": @"true",
            @"pubsub#access_model": @"whitelist",
            @"pubsub#max_items": max_items,
        } andHandler:$newHandler(self, bookmarks2Published, $ID(room))];
    }
    
    //remove all mucs not listed in local favorites table
    NSMutableSet* toRemove = [NSMutableSet setWithArray:[_data allKeys]];
    [toRemove  minusSet:ownFavorites];
    for(NSString* room in toRemove)
    {
        DDLogInfo(@"Removing muc '%@' on account %@ from bookmarks...", room, account.accountNo);
        [account.pubsub retractItemWithId:room onNode:@"urn:xmpp:bookmarks:1" andHandler:$newHandler(self, bookmarks2Retracted, $ID(room))];
    }
$$

$$class_handler(bookmarks2Published, $$ID(xmpp*, account), $$ID(NSString*, room), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogWarn(@"Ignoring new XEP-0402 bookmarks, server does not support syncing between XEP-0048 and XEP-0402!");
        return;
    }
    
    if(!success)
    {
        DDLogWarn(@"Could not publish bookmark for muc '%@' to pep!", room);
        [self handleErrorWithDescription:[NSString stringWithFormat:NSLocalizedString(@"Failed to save bookmark for Group/Channel: %@", @""), room] andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
        return;
    }
    DDLogDebug(@"Published bookmark for muc '%@' to pep", room);
$$

$$class_handler(bookmarks2Retracted, $$ID(xmpp*, account), $$ID(NSString*, room), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogWarn(@"Ignoring new XEP-0402 bookmarks, server does not support syncing between XEP-0048 and XEP-0402!");
        return;
    }
    
    if(!success)
    {
        DDLogWarn(@"Could not retract bookmark for muc '%@' from pep!", room);
        [self handleErrorWithDescription:[NSString stringWithFormat:NSLocalizedString(@"Failed to remove bookmark for Group/Channel: %@", @""), room] andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
        return;
    }
    DDLogDebug(@"Retracted bookmark for muc '%@' from pep", room);
$$

$$class_handler(bookmarksHandler, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    if(account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogInfo(@"Ignoring old XEP-0048 bookmarks, server supports syncing between XEP-0048 and XEP-0402...");
        return;
    }
    
    if(![jid isEqualToString:account.connectionProperties.identity.jid])
    {
        DDLogWarn(@"Ignoring bookmarks update not coming from our own jid");
        return;
    }
    
    NSSet* ownFavorites = [[DataLayer sharedInstance] listMucsForAccount:account.accountNo];
    
    //new/updated bookmarks
    if([type isEqualToString:@"publish"])
    {
        for(NSString* itemId in data)
        {
            //iterate through all conference elements provided
            NSMutableSet* bookmarkedMucs = [NSMutableSet new];
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
                
                //ignore password protected mucs
                if([conference check:@"password"])
                    continue;
                
                [bookmarkedMucs addObject:room];
                NSString* nick = [conference findFirst:@"nick#"];
                NSNumber* autojoin = [conference findFirst:@"/@autojoin|bool"];
                if(autojoin == nil)
                    autojoin = @NO;     //default value specified in xep
                
                //check if this is a new entry with autojoin=true
                if(![ownFavorites containsObject:room] && [autojoin boolValue])
                {
                    DDLogInfo(@"Entering muc '%@' on account %@ because it got added to bookmarks...", room, account.accountNo);
                    //make sure we update our favorites table right away, to counter any race conditions when joining multiple mucs with one bookmarks update
                    if(nick == nil)
                        nick = [account.mucProcessor calculateNickForMuc:room];
                    //this will record the desired nickname: the mucProcessor will pick that up and use it to join the muc
                    [[DataLayer sharedInstance] addMucFavorite:room forAccountId:account.accountNo andMucNick:nick];
                    //try to join muc, but don't perform a bookmarks update (this muc came in through a bookmark already)
                    [account.mucProcessor sendDiscoQueryFor:room withJoin:YES andBookmarksUpdate:NO];
                }
                //check if it is a known entry that changed autojoin to false
                else if([ownFavorites containsObject:room] && ![autojoin boolValue])
                {
                    DDLogInfo(@"Leaving muc '%@' on account %@ because not listed as autojoin=true in bookmarks...", room, account.accountNo);
                    //delete local favorites entry and leave room afterwards, but keep buddylist entry because only the autojoin flag changed
                    [account.mucProcessor leave:room withBookmarksUpdate:NO keepBuddylistEntry:YES];
                }
                //check for nickname changes
                else if([ownFavorites containsObject:room] && nick != nil)
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
                        [account.mucProcessor sendJoinPresenceFor:room];
                    }
                }
            }
            
            //remove and leave all mucs removed from bookmarks
            NSMutableSet* toLeave = [ownFavorites mutableCopy];
            [toLeave  minusSet:bookmarkedMucs];
            for(NSString* room in toLeave)
            {
                DDLogInfo(@"Leaving muc '%@' on account %@ because not listed in bookmarks anymore...", room, account.accountNo);
                //delete local favorites entry and leave room afterwards
                [account.mucProcessor leave:room withBookmarksUpdate:NO keepBuddylistEntry:NO];
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
        [account.mucProcessor leave:room withBookmarksUpdate:NO keepBuddylistEntry:NO];
    }
$$

$$class_handler(handleBookarksFetchResult, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    if(account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogInfo(@"Ignoring old XEP-0048 bookmarks, server supports syncing between XEP-0048 and XEP-0402...");
        return;
    }
    
    if(!success)
    {
        //item-not-found means: no bookmarks in storage --> use an empty data dict
        if([errorIq check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
            data = @{};
        else
        {
            DDLogWarn(@"Could not fetch bookmarks from pep prior to publishing!");
            [self handleErrorWithDescription:NSLocalizedString(@"Failed to save groupchat bookmarks", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
            return;
        }
    }
    
    BOOL changed = NO;
    NSSet* ownFavorites = [[DataLayer sharedInstance] listMucsForAccount:account.accountNo];
    
    for(NSString* itemId in data)
    {
        //ignore non-xep-compliant data and continue as if no data was received at all
        if(![data[itemId] check:@"{storage:bookmarks}storage"])
        {
            DDLogError(@"Received non-xep-compliant bookmarks data: %@", data);
            break;
        }
        
        NSMutableSet* bookmarkedMucs = [NSMutableSet new];
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
            if([ownFavorites containsObject:room] && ![autojoin boolValue])
            {
                DDLogInfo(@"Updating autojoin of bookmarked muc '%@' on account %@ to 'true'...", room, account.accountNo);
                
                //add or update nickname
                NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
                if(nick != nil)
                {
                    if(![conference check:@"nick"])
                        [conference addChildNode:[[MLXMLNode alloc] initWithElement:@"nick"]];
                    ((MLXMLNode*)[conference findFirst:@"nick"]).data = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
                }
                
                //update autojoin value to true
                conference.attributes[@"autojoin"] = @"true";
                changed = YES;
            }
        }
        
        //add all mucs not yet listed in bookmarks
        NSMutableSet* toAdd = [ownFavorites mutableCopy];
        [toAdd  minusSet:bookmarkedMucs];
        for(NSString* room in toAdd)
        {
            DDLogInfo(@"Adding muc '%@' on account %@ to bookmarks...", room, account.accountNo);
            NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
            [[data[itemId] findFirst:@"{storage:bookmarks}storage"] addChildNode:[[MLXMLNode alloc] initWithElement:@"conference" withAttributes:@{
                @"jid": room,
                @"name": [[MLContact createContactFromJid:room andAccountNo:account.accountNo] contactDisplayName],
                @"autojoin": @"true",
            } andChildren:(nick != nil ? @[[[MLXMLNode alloc] initWithElement:@"nick" withAttributes:@{} andChildren:@[] andData:nick]] : @[]) andData:nil]];
            changed = YES;
        }
        
        //remove all mucs not listed in local favorites table
        NSMutableSet* toRemove = [bookmarkedMucs mutableCopy];
        [toRemove  minusSet:ownFavorites];
        for(NSString* room in toRemove)
        {
            DDLogInfo(@"Removing muc '%@' on account %@ from bookmarks...", room, account.accountNo);
            [[data[itemId] findFirst:@"{storage:bookmarks}storage"] removeChildNode:[data[itemId] findFirst:@"{storage:bookmarks}storage/conference<jid=%@>", room]];
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
        DDLogInfo(@"neither a pep item was found, nor do we have any local muc favorites: don't publish anything");
        return;
    }
    
    DDLogInfo(@"no pep item was found: publish our bookmarks the first time");
    NSMutableArray* conferences = [NSMutableArray new];
    for(NSString* room in ownFavorites)
    {
        DDLogInfo(@"Adding muc '%@' on account %@ to bookmarks...", room, account.accountNo);
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:account.accountNo];
        [conferences addObject:[[MLXMLNode alloc] initWithElement:@"conference" withAttributes:@{
            @"jid": room,
            @"name": [[MLContact createContactFromJid:room andAccountNo:account.accountNo] contactDisplayName],
            @"autojoin": @"true",
        } andChildren:(nick != nil ? @[[[MLXMLNode alloc] initWithElement:@"nick" withAttributes:@{} andChildren:@[] andData:nick]] : @[]) andData:nil]];
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

$$class_handler(bookmarksPublished, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(account.connectionProperties.supportsBookmarksCompat)
    {
        DDLogInfo(@"Ignoring old XEP-0048 bookmarks, server supports syncing between XEP-0048 and XEP-0402...");
        return;
    }
    
    if(!success)
    {
        DDLogWarn(@"Could not publish bookmarks to pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to save groupchat bookmarks", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:YES];
        return;
    }
    DDLogDebug(@"Published bookmarks to pep");
$$

$$class_handler(rosterNamePublished, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        DDLogWarn(@"Could not publish roster name to pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to publish own nickname", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
    DDLogDebug(@"Published roster name to pep");
$$

$$class_handler(rosterNameDeleted, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        //item-not-found means: nick already deleted --> ignore this error
        if([errorIq check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            DDLogWarn(@"Roster name was already deleted from pep, ignoring error!");
            return;
        }
        DDLogWarn(@"Could not remove roster name from pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to delete own nickname", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
    DDLogDebug(@"Removed roster name from pep");
$$

$$class_handler(avatarDeleted, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        //item-not-found means: avatar already deleted --> ignore this error
        if([errorIq check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            DDLogWarn(@"Avatar image was already deleted from pep, ignoring error!");
            return;
        }
        DDLogWarn(@"Could not delete avatar image from pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to delete own avatar", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
    DDLogDebug(@"Removed avatar from pep");
$$

$$class_handler(avatarMetadataPublished, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(!success)
    {
        DDLogWarn(@"Could not publish avatar metadata to pep!");
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to publish own avatar", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
        return;
    }
    DDLogDebug(@"Published avatar metadata to pep");
$$

$$class_handler(avatarDataPublished, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $$ID(NSString*, imageHash), $$UINTEGER(imageBytesLen))
    if(!success)
    {
        DDLogWarn(@"Could not publish avatar image data for hash %@!", imageHash);
        [self handleErrorWithDescription:NSLocalizedString(@"Failed to publish own avatar", @"") andAccount:account andErrorIq:errorIq andErrorReason:errorReason andIsSevere:NO];
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
                    @"bytes": [NSString stringWithFormat:@"%lu", (unsigned long)imageBytesLen]
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
    MLAssert(errorIq || errorReason, @"at least one of errorIq or errorReason must be set when calling error handler!");
    if(errorIq)
        [HelperTools postError:description withNode:errorIq andAccount:account andIsSevere:isSevere];
    else if(errorReason)
        [HelperTools postError:[NSString stringWithFormat:@"%@: %@", description, errorReason] withNode:nil andAccount:account andIsSevere:isSevere];
}

@end
