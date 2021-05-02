//
//  MLPubSubProcessor.m
//  monalxmpp
//
//  Created by Thilo Molitor on 31.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MLPubSubProcessor.h"
#import "MLPubSub.h"
#import "MLHandler.h"
#import "xmpp.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import "MLImageManager.h"
#import "MLNotificationQueue.h"

@interface MLPubSubProcessor()

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

$$handler(handleAvatarFetchResult, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(NSDictionary*, data))
    //ignore errors here (e.g. simply don't update the avatar image)
    //(this should never happen if other clients and servers behave properly)
    if(errorIq)
    {
        DDLogError(@"Got avatar image fetch error from jid %@: %@", jid, errorIq);
        return;
    }
    
    for(NSString* avatarHash in data)
    {
        [[MLImageManager sharedInstance] setIconForContact:jid andAccount:account.accountNo WithData:[data[avatarHash] findFirst:@"{urn:xmpp:avatar:data}data#|base64"]];
        [[DataLayer sharedInstance] setAvatarHash:avatarHash forContact:jid andAccount:account.accountNo];
        [account accountStatusChanged];     //inform ui of this change (accountStatusChanged will force a ui reload which will also reload the avatars)
        MLContact* contact = [MLContact contactFromJid:jid andAccountNo:account.accountNo];
        if(contact)     //ignore updates for jids not in our roster
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": contact
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
                MLContact* contact = [MLContact contactFromJid:jid andAccountNo:account.accountNo];
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
            MLContact* contact = [MLContact contactFromJid:jid andAccountNo:account.accountNo];
            if(contact)     //ignore updates for jids not in our roster
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                    @"contact": contact
                }];
        }
    }
$$

$$handler(avatarDataPublished, $_ID(xmpp*, account), $_BOOL(success), $_ID(NSString*, imageHash), $_ID(NSData*, imageData))
    if(!success)
    {
        DDLogWarn(@"Could not publish avatar image data for hash %@!", imageHash);
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
    }];
$$

@end
