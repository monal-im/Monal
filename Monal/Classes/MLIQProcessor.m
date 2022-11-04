//
//  MLIQProcessor.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLIQProcessor.h"
#import "MLConstants.h"
#import "MLHandler.h"
#import "DataLayer.h"
#import "MLImageManager.h"
#import "HelperTools.h"
#import "MLNotificationQueue.h"
#import "MLContactSoftwareVersionInfo.h"
#import "MLOMEMO.h"

@import WebRTC;
@import CallKit;

@interface MLIQProcessor()

@end

/**
 Validate and process any iq elements.
 @link https://xmpp.org/rfcs/rfc6120.html#stanzas-semantics-iq
 */
@implementation MLIQProcessor

+(void) processIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    if([iqNode check:@"/<type=get>"])
        [self processGetIq:iqNode forAccount:account];
    else if([iqNode check:@"/<type=set>"])
        [self processSetIq:iqNode forAccount:account];
    else if([iqNode check:@"/<type=result>"])
        [self processResultIq:iqNode forAccount:account];
    else if([iqNode check:@"/<type=error>"])
        [self processErrorIq:iqNode forAccount:account];
    else
        DDLogWarn(@"Ignoring invalid iq type: %@", [iqNode findFirst:@"/@type"]);
}

+(void) processGetIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    if([iqNode check:@"{urn:xmpp:ping}ping"])
    {
        XMPPIQ* pong = [[XMPPIQ alloc] initAsResponseTo:iqNode];
        [pong setiqTo:iqNode.from];
        [account send:pong];
        return;
    }
    
    if([iqNode check:@"{jabber:iq:version}query"])
    {
        XMPPIQ* versioniq = [[XMPPIQ alloc] initAsResponseTo:iqNode];
        [versioniq setiqTo:iqNode.from];
        [versioniq setVersion];
        [account send:versioniq];
        return;
    }
    
    if([iqNode check:@"{http://jabber.org/protocol/disco#info}query"])
    {
        XMPPIQ* discoInfoResponse = [[XMPPIQ alloc] initAsResponseTo:iqNode];
        [discoInfoResponse setDiscoInfoWithFeatures:account.capsFeatures identity:account.capsIdentity andNode:[iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query@node"]];
        [account send:discoInfoResponse];
        return;
    }
    
    DDLogWarn(@"Got unhandled get IQ: %@", iqNode);
    [self respondWithErrorTo:iqNode onAccount:account];
}

+(void) processSetIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    if([iqNode check:@"{urn:tmp:monal:webrtc:sdp:1}sdp"])
    {
        DDLogDebug(@"Received Monal SDP offer: %@", iqNode);
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalIncomingSDP object:account userInfo:@{@"iqNode": iqNode}];
        return;
    }
    
    if([iqNode check:@"{urn:tmp:monal:webrtc:candidate:1}candidate"])
    {
        DDLogDebug(@"Received ICE candidate: %@", iqNode);
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalIncomingICECandidate object:account userInfo:@{@"iqNode": iqNode}];
        return;
    }
    
    //its a roster push (sanity check will be done in processRosterWithAccount:andIqNode:)
    if([iqNode check:@"{jabber:iq:roster}query"])
    {
        [self processRosterWithAccount:account andIqNode:iqNode];
        
        //send empty result iq as per RFC 6121 requirements
        XMPPIQ* reply = [[XMPPIQ alloc] initAsResponseTo:iqNode];
        [reply setiqTo:iqNode.from];
        [account send:reply];
        return;
    }

    if(account.connectionProperties.supportsBlocking)
    {
        BOOL blockingUpdated = NO;
        // mark jid as unblocked
        if([iqNode check:@"{urn:xmpp:blocking}unblock"])
        {
            NSArray* unBlockItems = [iqNode find:@"{urn:xmpp:blocking}unblock/item@@"];
            for(NSDictionary* item in unBlockItems)
            {
                if(item && item[@"jid"])
                    [[DataLayer sharedInstance] unBlockJid:item[@"jid"] withAccountNo:account.accountNo];
            }
            if(unBlockItems && unBlockItems.count == 0)
            {
                // remove all blocks
                [account updateLocalBlocklistCache:[[NSSet<NSString*> alloc] init]];
            }
            blockingUpdated = YES;
        }
        // mark jid as blocked
        if([iqNode check:@"{urn:xmpp:blocking}block"])
        {
            for(NSDictionary* item in [iqNode find:@"{urn:xmpp:blocking}block/item@@"])
            {
                if(item && item[@"jid"])
                    [[DataLayer sharedInstance] blockJid:item[@"jid"] withAccountNo:account.accountNo];
            }
            blockingUpdated = YES;
        }
        if(blockingUpdated)
        {
            // notify the views
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalBlockListRefresh object:account userInfo:@{@"accountNo": account.accountNo}];
            return;
        }
    }
    
    DDLogWarn(@"Got unhandled set IQ: %@", iqNode);
    [self respondWithErrorTo:iqNode onAccount:account];
}

+(void) processResultIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    //this is the only iq result that does not need any state
    //WARNING: be careful adding other stateless result handlers (those can impose security risks!)
    if([iqNode check:@"{jabber:iq:version}query"])
    {
        [self iqVersionResult:iqNode forAccount:account];
        return;
    }
    
    DDLogWarn(@"Got unhandled result IQ: %@", iqNode);
    [self respondWithErrorTo:iqNode onAccount:account];
}

+(void) processErrorIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    DDLogWarn(@"Got unhandled error IQ: %@", iqNode);
}

$$class_handler(handleCatchup, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$BOOL(secondTry))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Mam catchup query returned error: %@", [iqNode findFirst:@"error"]);
        
        //handle weird XEP-0313 monkey-patching XEP-0059 behaviour (WHY THE HELL??)
        if(!secondTry && [iqNode check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType];
            DDLogInfo(@"Querying COMPLETE muc mam:2 archive for catchup");
            [mamQuery setCompleteMAMQuery];
            [account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, YES))];
        }
        else
        {
            [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query for new messages on account %@", @""), account.connectionProperties.identity.jid] withNode:iqNode andAccount:account andIsSevere:YES];
            [account mamFinishedFor:account.connectionProperties.identity.jid];
        }
        return;
    }
    if(![[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue] && [iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
    {
        DDLogVerbose(@"Paging through mam catchup results with after: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithType:kiqSetType];
        [pageQuery setMAMQueryAfter:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]];
        [account sendIq:pageQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
    }
    else if([[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue])
    {
        DDLogVerbose(@"Mam catchup finished");
        [account mamFinishedFor:account.connectionProperties.identity.jid];
    }
$$

$$class_handler(handleMamResponseWithLatestId, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Mam latest stanzaid query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query newest stanzaid for account %@", @""), account.connectionProperties.identity.jid] withNode:iqNode andAccount:account andIsSevere:YES];
        return;
    }
    DDLogVerbose(@"Got latest stanza id to prime database with: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
    //only do this if we got a valid stanza id (not null)
    //if we did not get one we will get one when receiving the next message in this smacks session
    //if the smacks session times out before we get a message and someone sends us one or more messages before we had a chance to establish
    //a new smacks session, this messages will get lost because we don't know how to query the archive for this message yet
    //once we successfully receive the first mam-archived message stanza (could even be an XEP-184 ack for a sent message),
    //no more messages will get lost
    //we ignore this single message loss here, because it should be super rare and solving it would be really complicated
    if([iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
        [[DataLayer sharedInstance] setLastStanzaId:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"] forAccount:account.accountNo];
    [account mamFinishedFor:account.connectionProperties.identity.jid];
$$

$$class_handler(handleCarbonsEnabled, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"carbon enable iq returned error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enable carbons for account %@", @""), account.connectionProperties.identity.jid] withNode:iqNode andAccount:account andIsSevere:YES];
        return;
    }
    account.connectionProperties.usingCarbons2 = YES;
$$

$$class_handler(handleBind, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Binding our resource returned an error: %@", [iqNode findFirst:@"error"]);
        if([iqNode check:@"error<type=cancel>"])
        {
            [HelperTools postError:NSLocalizedString(@"XMPP Bind Error", @"") withNode:iqNode andAccount:account andIsSevere:YES];
            [account disconnect];
        }
        else if([iqNode check:@"error<type=modify>"])
            [account bindResource:[HelperTools encodeRandomResource]];      //try to bind a new resource
        else
            [account reconnect];        //just try to reconnect (wait error type and all other error types not expected for bind)
        return;
    }
    
    DDLogInfo(@"Now bound to fullJid: %@", [iqNode findFirst:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/jid#"]);
    [account.connectionProperties.identity bindJid:[iqNode findFirst:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/jid#"]];
    DDLogDebug(@"bareJid=%@, resource=%@, fullJid=%@", account.connectionProperties.identity.jid, account.connectionProperties.identity.resource, account.connectionProperties.identity.fullJid);
    
    //update resource in db (could be changed by server)
    NSMutableDictionary* accountDict = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountNo]];
    accountDict[kResource] = account.connectionProperties.identity.resource;
    [[DataLayer sharedInstance] updateAccounWithDictionary:accountDict];
    
    if(account.connectionProperties.supportsSM3)
    {
        MLXMLNode *enableNode = [[MLXMLNode alloc]
            initWithElement:@"enable"
            andNamespace:@"urn:xmpp:sm:3"
            withAttributes:@{@"resume": @"true"}
            andChildren:@[]
            andData:nil
        ];
        [account send:enableNode];
    }
    else
    {
        //init session and query disco, roster etc.
        [account initSession];
    }
$$

//proxy handler
$$class_handler(handleRoster, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    [self processRosterWithAccount:account andIqNode:iqNode];
$$

+(void) processRosterWithAccount:(xmpp*) account andIqNode:(XMPPIQ*) iqNode
{
    //check sanity of from according to RFC 6121:
    //  https://tools.ietf.org/html/rfc6121#section-2.1.3 (roster get)
    //  https://tools.ietf.org/html/rfc6121#section-2.1.6 (roster push)
    if(
        iqNode.from != nil &&
        ![iqNode.from isEqualToString:account.connectionProperties.identity.jid] &&
        ![iqNode.from isEqualToString:account.connectionProperties.identity.domain]
    )
    {
        DDLogWarn(@"Invalid sender for roster, ignoring iq: %@", iqNode);
        return;
    }
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Roster query returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"XMPP Roster Error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    
    for(NSMutableDictionary* contact in [iqNode find:@"{jabber:iq:roster}query/item@@"])
    {
        if(!contact[@"jid"])
            continue;
        contact[@"jid"] = [[NSString stringWithFormat:@"%@", contact[@"jid"]] lowercaseString];
        MLContact* contactObj = [MLContact createContactFromJid:contact[@"jid"] andAccountNo:account.accountNo];
        if([[contact objectForKey:@"subscription"] isEqualToString:kSubRemove])
        {
            if(contactObj.isGroup)
                DDLogWarn(@"Got roster remove request for MUC, ignoring it (possibly even triggered by us).");
            else
            {
                [[DataLayer sharedInstance] removeBuddy:contact[@"jid"] forAccount:account.accountNo];
                [contactObj removeShareInteractions];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRemoved object:account userInfo:@{@"contact": contactObj}];
            }
        }
        else
        {
            if([[contact objectForKey:@"subscription"] isEqualToString:kSubFrom]) //already subscribed
            {
                [[DataLayer sharedInstance] deleteContactRequest:contactObj];
            }
            else if([[contact objectForKey:@"subscription"] isEqualToString:kSubBoth])
            {
                // We and the contact are interested
                [[DataLayer sharedInstance] deleteContactRequest:contactObj];
            }
            
            if(contactObj.isGroup)
            {
                DDLogWarn(@"Removing muc '%@' from contactlist, got 'normal' roster entry!", contact[@"jid"]);
                [[DataLayer sharedInstance] removeBuddy:contact[@"jid"] forAccount:account.accountNo];
                [contactObj removeShareInteractions];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRemoved object:account userInfo:@{@"contact": contactObj}];
                contactObj = [MLContact createContactFromJid:contact[@"jid"] andAccountNo:account.accountNo];
            }
            
            DDLogVerbose(@"Adding contact %@ (%@) to database", contact[@"jid"], [contact objectForKey:@"name"]);
            [[DataLayer sharedInstance] addContact:contact[@"jid"]
                                        forAccount:account.accountNo
                                          nickname:[contact objectForKey:@"name"] ? [contact objectForKey:@"name"] : @""];
#ifndef DISABLE_OMEMO
            if(contactObj.isGroup == NO)
            {
                // Request omemo devicelist
                [account.omemo queryOMEMODevices:contactObj.contactJid];
            }
#endif// DISABLE_OMEMO
            
            DDLogVerbose(@"Setting subscription status '%@' (ask=%@) for contact %@", contact[@"subscription"], contact[@"ask"], contact[@"jid"]);
            [[DataLayer sharedInstance] setSubscription:[contact objectForKey:@"subscription"]
                                                 andAsk:[contact objectForKey:@"ask"]
                                             forContact:contact[@"jid"]
                                             andAccount:account.accountNo];
            
            //regenerate avatar if the nickame has changed
            if(![contactObj.nickName isEqualToString:[contact objectForKey:@"name"]])
                [[MLImageManager sharedInstance] purgeCacheForContact:contact[@"jid"] andAccount:account.accountNo];
            
            //TODO: save roster groups to new db table
            
            //send out kMonalContactRefresh notification
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": [MLContact createContactFromJid:contact[@"jid"] andAccountNo:account.accountNo]
            }];
        }
    }
    
    if([iqNode check:@"{jabber:iq:roster}query@ver"])
        [[DataLayer sharedInstance] setRosterVersion:[iqNode findFirst:@"{jabber:iq:roster}query@ver"] forAccount:account.accountNo];
}

//features advertised on our own jid/account
$$class_handler(handleAccountDiscoInfo, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Disco info query to our account returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"XMPP Account Info Error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    
    if(
        [iqNode check:@"{http://jabber.org/protocol/disco#info}query/identity<category=pubsub><type=pep>"] &&       //xep-0163 support
        [features containsObject:@"http://jabber.org/protocol/pubsub#filtered-notifications"] &&                    //needed for xep-0163 support
        [features containsObject:@"http://jabber.org/protocol/pubsub#publish-options"] &&                           //needed for xep-0223 support
        //important xep-0060 support (aka basic support)
        // [features containsObject:@"http://jabber.org/protocol/pubsub#last-published"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#publish"] &&
        // [features containsObject:@"http://jabber.org/protocol/pubsub#item-ids"] &&
        // [features containsObject:@"http://jabber.org/protocol/pubsub#create-and-configure"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#create-nodes"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#delete-items"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#delete-nodes"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#persistent-items"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#retrieve-items"] &&
        // [features containsObject:@"http://jabber.org/protocol/pubsub#config-node"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#auto-create"]
        //needed for xep-0402 later
        //[features containsObject:@"http://jabber.org/protocol/pubsub#multi-items"]
    )
    {
        DDLogInfo(@"Supports pubsub (pep)");
        account.connectionProperties.supportsPubSub = YES;
    }
    
    if([features containsObject:@"urn:xmpp:push:0"])
    {
        DDLogInfo(@"supports push");
        account.connectionProperties.supportsPush = YES;
        [account enablePush];
    }
    
    if([features containsObject:@"urn:xmpp:mam:2"])
    {
        DDLogInfo(@"supports mam:2");
        account.connectionProperties.supportsMam2 = YES;
        
        //query mam since last received stanza ID because we could not resume the smacks session
        //(we would not have landed here if we were able to resume the smacks session)
        //this will do a catchup of everything we might have missed since our last connection
        //we possibly receive sent messages, too (this will update the stanzaid in database and gets deduplicate by messageid,
        //which is guaranteed to be unique (because monal uses uuids for outgoing messages)
        NSString* lastStanzaId = [[DataLayer sharedInstance] lastStanzaIdForAccount:account.accountNo];
        [account delayIncomingMessageStanzasForArchiveJid:account.connectionProperties.identity.jid];
        XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType];
        if(lastStanzaId)
        {
            DDLogInfo(@"Querying mam:2 archive after stanzaid '%@' for catchup", lastStanzaId);
            [mamQuery setMAMQueryAfter:lastStanzaId];
            [account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
        }
        else
        {
            DDLogInfo(@"Querying mam:2 archive for latest stanzaid to prime database");
            [mamQuery setMAMQueryForLatestId];
            [account sendIq:mamQuery withHandler:$newHandler(self, handleMamResponseWithLatestId)];
        }
    }
    else
    {
        //we don't support MAM --> tell the system to finish the catchup without MAM
        DDLogError(@"Server does not support MAM, marking mam catchup as 'finished' for jid %@", account.connectionProperties.identity.jid);
        [account mamFinishedFor:account.connectionProperties.identity.jid];
    }
    
    account.connectionProperties.accountDiscoDone = YES;
$$

//features advertised on our server
$$class_handler(handleServerDiscoInfo, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Disco info query to our server returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"XMPP Disco Info Error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    account.connectionProperties.serverFeatures = features;
    
    if([features containsObject:@"urn:xmpp:carbons:2"])
    {
        DDLogInfo(@"got disco result with carbons ns");
        if(!account.connectionProperties.usingCarbons2)
        {
            DDLogInfo(@"enabling carbons");
            XMPPIQ* carbons = [[XMPPIQ alloc] initWithType:kiqSetType];
            [carbons addChildNode:[[MLXMLNode alloc] initWithElement:@"enable" andNamespace:@"urn:xmpp:carbons:2"]];
            [account sendIq:carbons withHandler:$newHandler(self, handleCarbonsEnabled)];
        }
    }
    
    if([features containsObject:@"urn:xmpp:ping"])
        account.connectionProperties.supportsPing = YES;
    
    if([features containsObject:@"urn:xmpp:blocking"])
    {
        account.connectionProperties.supportsBlocking = YES;
        [account fetchBlocklist];
    }
    
    if(!account.connectionProperties.supportsHTTPUpload && [features containsObject:@"urn:xmpp:http:upload:0"])
    {
        DDLogInfo(@"supports http upload with server: %@", iqNode.from);
        account.connectionProperties.supportsHTTPUpload = YES;
        account.connectionProperties.uploadServer = iqNode.from;
        account.connectionProperties.uploadSize = [[iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{urn:xmpp:http:upload}result@max-file-size\\|int"] integerValue];
        DDLogInfo(@"Upload max filesize: %lu", account.connectionProperties.uploadSize);
    }
$$

$$class_handler(handleServiceDiscoInfo, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    
    if(!account.connectionProperties.supportsHTTPUpload && [features containsObject:@"urn:xmpp:http:upload:0"])
    {
        DDLogInfo(@"supports http upload with server: %@", iqNode.from);
        account.connectionProperties.supportsHTTPUpload = YES;
        account.connectionProperties.uploadServer = iqNode.from;
        account.connectionProperties.uploadSize = [[iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{urn:xmpp:http:upload}result@max-file-size\\|int"] integerValue];
        DDLogInfo(@"Upload max filesize: %lu", account.connectionProperties.uploadSize);
    }
    
    if(!account.connectionProperties.conferenceServer && [features containsObject:@"http://jabber.org/protocol/muc"])
        account.connectionProperties.conferenceServer = iqNode.from;
$$

$$class_handler(handleServerDiscoItems, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    account.connectionProperties.discoveredServices = [[NSMutableArray alloc] init];
    for(NSDictionary* item in [iqNode find:@"{http://jabber.org/protocol/disco#items}query/item@@"])
    {
        [account.connectionProperties.discoveredServices addObject:item];
        if(![[item objectForKey:@"jid"] isEqualToString:account.connectionProperties.identity.domain])
        {
            XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
            [discoInfo setiqTo:[item objectForKey:@"jid"]];
            [discoInfo setDiscoInfoNode];
            [account sendIq:discoInfo withHandler:$newHandler(self, handleServiceDiscoInfo)];
            
            [account queryExternalServicesOn:[item objectForKey:@"jid"]];
        }
    }
$$

$$class_handler(handleExternalDisco, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"External service disco query to '%@' returned an error: %@", iqNode.from, [iqNode findFirst:@"error"]);
        //[HelperTools postError:NSLocalizedString(@"XMPP External Service Disco Error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    
    for(MLXMLNode* service in [iqNode find:@"{urn:xmpp:extdisco:2}services/service"])
    {
        if([service check:@"/<type=stun>"] || [service check:@"/<type=turn>"])
        {
            NSMutableDictionary* info = [NSMutableDictionary dictionaryWithDictionary:@{@"directoryJid": iqNode.from}];
            [info addEntriesFromDictionary:[service findFirst:@"/@@"]];
            [account.connectionProperties.discoveredStunTurnServers addObject:info];
        }
    }
$$

//entity caps of some contact
$$class_handler(handleEntityCapsDisco, $$ID(XMPPIQ*, iqNode))
    NSMutableArray* identities = [[NSMutableArray alloc] init];
    for(MLXMLNode* identity in [iqNode find:@"{http://jabber.org/protocol/disco#info}query/identity"])
        [identities addObject:[NSString stringWithFormat:@"%@/%@/%@/%@", [identity findFirst:@"/@category"], [identity findFirst:@"/@type"], ([identity check:@"/@xml:lang"] ? [identity findFirst:@"/@xml:lang"] : @""), [identity findFirst:@"/@name"]]];
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    NSArray* forms = [iqNode find:@"{http://jabber.org/protocol/disco#info}query/{jabber:x:data}x"];
    NSString* ver = [HelperTools getEntityCapsHashForIdentities:identities andFeatures:features andForms:forms];
    [[DataLayer sharedInstance] setCaps:features forVer:ver];
$$

$$class_handler(handleMamPrefs, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"MAM prefs query returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"XMPP mam preferences error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    if([iqNode check:@"{urn:xmpp:mam:2}prefs@default"])
        [[MLNotificationQueue currentQueue] postNotificationName:kMLMAMPref object:self userInfo:@{@"mamPref": [iqNode findFirst:@"{urn:xmpp:mam:2}prefs@default"]}];
    else
    {
        DDLogError(@"MAM prefs query returned unexpected result: %@", iqNode);
        [HelperTools postError:NSLocalizedString(@"Unexpected mam preferences result", @"") withNode:nil andAccount:account andIsSevere:NO];
    }
$$

$$class_handler(handleSetMamPrefs, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Setting MAM prefs returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"XMPP mam preferences error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
$$

$$class_handler(handlePushEnabled, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, selectedPushServer))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Enabling push returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"Error registering push", @"") withNode:iqNode andAccount:account andIsSevere:YES];
        account.connectionProperties.pushEnabled = NO;
        return;
    }
    // save used push server to db
    [[DataLayer sharedInstance] updateUsedPushServer:selectedPushServer forAccount:account.accountNo];
    DDLogInfo(@"Push is enabled now");
    account.connectionProperties.pushEnabled = YES;
$$

$$class_handler(handleBlocklist, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if(!account.connectionProperties.supportsBlocking)
        return;

    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Blocklist fetch returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"Failed to load blocklist", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    
    if([iqNode check:@"{urn:xmpp:blocking}blocklist"])
    {
        NSMutableSet<NSString*>* blockedJids = [[NSMutableSet<NSString*> alloc] init];
        for(NSDictionary* item in [iqNode find:@"{urn:xmpp:blocking}blocklist/item@@"])
            if(item && item[@"jid"])
                [blockedJids addObject:item[@"jid"]];
        [account updateLocalBlocklistCache:blockedJids];
        // notify the views
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalBlockListRefresh object:account userInfo:@{@"accountNo": account.accountNo}];
    }
$$

$$class_handler(handleBlocked, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, blockedJid))
    if(!account.connectionProperties.supportsBlocking)
        return;
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Blocking returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to block contact %@", @""), blockedJid] withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
$$

+(void) iqVersionResult:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    NSString* iqAppName = [iqNode findFirst:@"{jabber:iq:version}query/name#"];
    if(!iqAppName)
        iqAppName = @"";
    NSString* iqAppVersion = [iqNode findFirst:@"{jabber:iq:version}query/version#"];
    if(!iqAppVersion)
        iqAppVersion = @"";
    NSString* iqPlatformOS = [iqNode findFirst:@"{jabber:iq:version}query/os#"];
    if(!iqPlatformOS)
        iqPlatformOS = @"";
    
    MLContactSoftwareVersionInfo* versionDBInfo = [[DataLayer sharedInstance] getSoftwareVersionInfoForContact:iqNode.fromUser resource:iqNode.fromResource andAccount:account.accountNo];
    
    if(versionDBInfo == nil || !(
        [versionDBInfo.appName isEqualToString:iqAppName] &&
        [versionDBInfo.appVersion isEqualToString:iqAppVersion] &&
        [versionDBInfo.platformOs isEqualToString:iqPlatformOS]
    )) {
        DDLogVerbose(@"Updating software version info for %@", iqNode.from);
        MLContactSoftwareVersionInfo* newSoftwareVersionInfo = [[MLContactSoftwareVersionInfo alloc] initWithJid:iqNode.fromUser andRessource:iqNode.fromResource andAppName:iqAppName andAppVersion:iqAppVersion andPlatformOS:iqPlatformOS];

        [[DataLayer sharedInstance] setSoftwareVersionInfoForContact:iqNode.fromUser
                                                            resource:iqNode.fromResource
                                                            andAccount:account.accountNo
                                                    withSoftwareInfo:newSoftwareVersionInfo];
        
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalXmppUserSoftWareVersionRefresh            
                                                            object:account
                                                            userInfo:@{@"versionInfo": newSoftwareVersionInfo}];
    }
}

+(void) respondWithErrorTo:(XMPPIQ*) iqNode onAccount:(xmpp*) account
{
    XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
    [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"cancel"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"service-unavailable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
    ] andData:nil]];
    [account send:errorIq];
}

@end
