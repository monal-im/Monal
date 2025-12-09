//
//  MLIQProcessor.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <stdatomic.h>
#import "MLIQProcessor.h"
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLHandler.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLNotificationQueue.h>
#import <monalxmpp/MLContactSoftwareVersionInfo.h>
#import <monalxmpp/MLOMEMO.h>
#import <monalxmpp/MLContact.h>
#import "MLMessageProcessor.h"

@import SAMKeychain;

/**
 Validate and process any iq elements.
 @link https://xmpp.org/rfcs/rfc6120.html#stanzas-semantics-iq
 */
@implementation MLIQProcessor

+(void) processUnboundIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    //only handle these iqs if the remote user is on our roster,
    //if the are coming from our own domain,
    //or if they are from a muc group, not a channel
    MLContact* contact = [MLContact createContactFromJid:iqNode.fromUser andAccountID:account.accountID];
    if(!(
        //we have to check for .isMuc because mucs always set .isSubscribedFrom to YES
        (!contact.isMuc && contact.isSubscribedFrom) ||
        contact.isSelf ||
        [account.connectionProperties.identity.domain isEqualToString:iqNode.fromUser] ||
        (contact.isMuc && [kMucTypeGroup isEqualToString:contact.mucType])
    ))
        DDLogWarn(@"Invalid sender for iq (!subscribedFrom || isMuc), ignoring: %@", iqNode);
    
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
    
    if([iqNode check:@"{jabber:iq:version}query"] && [[HelperTools defaultsDB] boolForKey: @"allowVersionIQ"])
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
    //these iqs will be ignored if not matching an outgoing or incoming call
    //--> no presence leak if the call was not outgoing, because the jmi stanzas creating the call will
    //not be processed without isSubscribedFrom in the first place
    if(([iqNode check:@"{urn:xmpp:jingle:1}jingle"] && ![iqNode check:@"{urn:xmpp:jingle:1}jingle<action=transport-info>"]))
    {
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalIncomingSDP object:account userInfo:@{@"iqNode": iqNode}];
        return;
    }
    if([iqNode check:@"{urn:xmpp:jingle:1}jingle<action=transport-info>"])
    {
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalIncomingICECandidate object:account userInfo:@{@"iqNode": iqNode}];
        return;
    }
    
    //its a roster push (sanity check will be done in processRosterWithAccount:andIqNode:)
    if([iqNode check:@"{jabber:iq:roster}query"])
    {
        //this will only return YES, if the roster push was allowed and processed successfully
        if([self processRosterWithAccount:account andIqNode:iqNode])
        {
            //send empty result iq as per RFC 6121 requirements
            XMPPIQ* reply = [[XMPPIQ alloc] initAsResponseTo:iqNode];
            [reply setiqTo:iqNode.from];
            [account send:reply];
        }
        return;
    }

    if([iqNode check:@"{urn:xmpp:blocking}block"] || [iqNode check:@"{urn:xmpp:blocking}unblock"])
    {
        //make sure we don't process blocking updates not coming from our own account
        if([account.connectionProperties.serverDiscoFeatures containsObject:@"urn:xmpp:blocking"] && (iqNode.from == nil || [iqNode.fromUser isEqualToString:account.connectionProperties.identity.jid]))
        {
            BOOL blockingUpdated = NO;
            // mark jid as unblocked
            if([iqNode check:@"{urn:xmpp:blocking}unblock"])
            {
                NSArray* unBlockItems = [iqNode find:@"{urn:xmpp:blocking}unblock/item@@"];
                for(NSDictionary* item in unBlockItems)
                {
                    if(item && item[@"jid"])
                        [[DataLayer sharedInstance] unBlockJid:item[@"jid"] withAccountID:account.accountID];
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
                        [[DataLayer sharedInstance] blockJid:item[@"jid"] withAccountID:account.accountID];
                }
                blockingUpdated = YES;
            }
            if(blockingUpdated)
            {
                // notify the views
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalBlockListRefresh object:account userInfo:@{@"accountID": account.accountID}];
            }
        }
        else
            DDLogWarn(@"Invalid sender for blocklist, ignoring iq: %@", iqNode);
        return;
    }
    
    DDLogWarn(@"Got unhandled set IQ: %@", iqNode);
    [self respondWithErrorTo:iqNode onAccount:account];
}

+(void) processResultIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account
{
    //WARNING: be careful adding stateless result handlers here (those can impose security risks!)
    
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
            //latestMessage can be nil, thus [latestMessage timestamp] will return nil and setMAMQueryAfterTimestamp:nil
            //will query the whole archive since dawn of time
            MLMessage* latestMessage = [MLMessage createMessageFromHistoryID:[[DataLayer sharedInstance] getBiggestHistoryId]];
            DDLogInfo(@"Querying COMPLETE muc mam:2 archive at %@ after timestamp %@ for catchup", account.connectionProperties.identity.jid, [latestMessage timestamp]);
            XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType];
            [mamQuery setMAMQueryAfterTimestamp:[latestMessage timestamp]];
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
        DDLogVerbose(@"Paging through mam catchup results at %@ with after: %@", account.connectionProperties.identity.jid, [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithType:kiqSetType];
        [pageQuery setMAMQueryAfter:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]];
        [account sendIq:pageQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
    }
    else if([[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue])
    {
        DDLogVerbose(@"Mam catchup finished for %@", account.connectionProperties.identity.jid);
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
        [[DataLayer sharedInstance] setLastStanzaId:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"] forAccount:account.accountID];
    [account mamFinishedFor:account.connectionProperties.identity.jid];
$$

$$class_handler(handleMAMBackscrollingResultInvalidation, $$ID(xmpp*, account), $$ID(MLContact*, contact), $$PROMISE(promise))
    DDLogError(@"Got backscrolling mam error for %@", contact.contactJid);
    NSString* errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Could not fetch more old chat history for '%@' from the server archive. Please try again.", @""), contact.contactJid];
    NSError* error = [NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
    [promise reject:error];
$$

$$class_handler(handleMAMBackscrollingResult, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(MLContact*, contact), $_ID(NSArray*, historyIdsOfAlreadyRetreivedMessages), $$PROMISE(promise))
    //the promise will be rejected if an error prevented us to get any messages.
    //it will resolve an empty array, if the upper end of our archive was reached
    //and it will resolve an array of newly loaded mlmessages in all other cases

    //if we get less than half kMonalBackscrollingMsgCount message bodies,
    //recursively send another query, passing it the promise and the historyIds of processed messages,
    //and let the new query resolve the promise.
    NSUInteger retrievedBodiesOverall = 0;
    NSUInteger retrievedBodiesInThisQuery = 0;
    if(historyIdsOfAlreadyRetreivedMessages)
        retrievedBodiesOverall = historyIdsOfAlreadyRetreivedMessages.count;
    NSMutableArray* mamPage = [account getOrderedMamPageFor:[iqNode findFirst:@"/@id"]];

    //count new bodies
    for(NSDictionary* data in mamPage)
        if([data[@"messageNode"] check:@"body#"])
            retrievedBodiesInThisQuery++;

    retrievedBodiesOverall += retrievedBodiesInThisQuery;

    // If we had an error but we got some bodies, the promise will resolve the messages containing those bodies.
    // `item-not-found` means the stanzaId used in the query is unknown to the server, due to its retention policy.
    // => item-not-found indicates that the top of the mam archive was reached
    if([iqNode check:@"/<type=error>"] && retrievedBodiesOverall == 0
        && ![iqNode check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
    {
        NSString* errorMessage = [HelperTools extractXMPPError:iqNode withDescription:NSLocalizedString(@"Could not fetch more old history for this chat from the server archive. Please try again later.", @"")];
        NSError* error = [NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
        [promise reject:error];
    }
    else
    {
        if(retrievedBodiesOverall == 0)
        {
            //if we did not retrieve any body messages we don't need to process metadata sanzas (if any), but signal we reached the end of our archive
            DDLogDebug(@"Reached upper end of mam:2 archive");
            [promise fulfill:@[]];
            return;
        }

        NSMutableArray* historyIdList = [NSMutableArray new];

        //ignore all notifications generated while processing the queued stanzas
        [MLNotificationQueue queueNotificationsInBlock:^{
            //process received message stanzas and manipulate the db accordingly
            //if a new message got added to the history db, the message processor will return a MLMessage instance containing the history id of the newly created entry
            DDLogDebug(@"Handling %lu entries in mam page...", mamPage.count);
            //the handler is already called inside a db write transaction.
            //this means we're safe from mam holes if the app crashes while processing messages.
            //benchmarks reveal that processing 50 message stanzas takes ~58ms.
            //=> no risk of blocking the main thread for db write access for too long.
            NSNumber* historyId = @([[[DataLayer sharedInstance] getSmallestHistoryId] integerValue] - (NSInteger)retrievedBodiesInThisQuery);
            uint32_t entryNo = 0;
            for(NSDictionary* data in mamPage)
            {
                DDLogVerbose(@"Handling mam page entry[%u(%lu)]): %@", entryNo, mamPage.count, data);
                MLMessage* msg = [MLMessageProcessor processMessage:data[@"messageNode"] andOuterMessage:data[@"outerMessageNode"] forAccount:account withHistoryId:historyId];
                DDLogVerbose(@"Got message processor result: %@", msg);
                //add successfully added messages to our display list
                //stanzas not transporting a body will be processed, too, but the message processor will return nil for these
                if(msg != nil)
                {
                    [historyIdList addObject:msg.messageDBId];      //we only need the history id to fetch a fresh copy later
                    historyId = @([historyId intValue] + 1);      //calculate next history id
                }
                entryNo++;
            }

            //throw away all queued notifications before leaving this context
            [(MLNotificationQueue*)[MLNotificationQueue currentQueue] clear];
        } onQueue:@"MLhistoryIgnoreQueue"];

        DDLogDebug(@"collected mam:2 before-pages now contain %lu messages in summary not already in history", historyIdList.count);
        MLAssert(historyIdList.count <= retrievedBodiesInThisQuery, @"did add more messages to historydb table than bodies collected!", (@{
            @"historyIdList": historyIdList,
            @"retrievedBodies": @(retrievedBodiesInThisQuery),
        }));
        if(historyIdList.count < retrievedBodiesInThisQuery)
            DDLogWarn(@"Got %lu mam history messages already contained in history db, possibly ougoing messages that did not have a stanzaid yet!", retrievedBodiesInThisQuery - historyIdList.count);

        NSArray* overallHistoryIdList;
        if(historyIdsOfAlreadyRetreivedMessages)
            overallHistoryIdList = [historyIdList arrayByAddingObjectsFromArray:historyIdsOfAlreadyRetreivedMessages];
        else
            overallHistoryIdList = [historyIdList copy];

        //check if we need to load more messages
        if(retrievedBodiesOverall > kMonalBackscrollingMsgCount / 2)
        {
            //query db for the real MLMessage to account for changes in history table by non-body metadata messages received after the body-message
            [promise fulfill:[[DataLayer sharedInstance] messagesForHistoryIDs:overallHistoryIdList]];
        }
        else
        {
            if(
                ![[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue] &&
                [iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/first#"]
            )
            {
                //page through to get more messages, and pass the current promise and overallHistoryIdList
                //to the new query's handler
                DDLogVerbose(@"Going to send another mam backscrolling query because we didn't get enough message bodies. We got %lu bodies in this query and %lu bodies in all the queries since the user scrolled up to fetch more.", retrievedBodiesInThisQuery, retrievedBodiesOverall);
                NSString* earliestStanzaId = [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/first#"];
                XMPPIQ* newQuery = [account prepareIQForMAMQueryMostRecentForContact:contact before:earliestStanzaId];
                [account sendIq:newQuery withHandler:$newHandlerWithInvalidation(MLIQProcessor, handleMAMBackscrollingResult, handleMAMBackscrollingResultInvalidation, $ID(contact), $ID(historyIdsOfAlreadyRetreivedMessages, overallHistoryIdList), $PROMISE(promise))];
            }
            else
            {
                // Either the top of the mam archive was reached, or we got an error after receiving some bodies.

                //query db for the real MLMessages to account for changes in history table by non-body metadata messages received after the body-message
                [promise fulfill:[[DataLayer sharedInstance] messagesForHistoryIDs:overallHistoryIdList]];
            }
        }
    }
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
            [account disconnect];       //don't try again until next process start/unfreeze
        }
        else if([iqNode check:@"error<type=modify>"])
            [account bindResource:[HelperTools encodeRandomResource]];      //try to bind a new resource
        else
            [account reconnect];        //just try to reconnect (wait error type and all other error types not expected for bind)
        return;
    }
    
    DDLogInfo(@"Now bound to fullJid: %@", [iqNode findFirst:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/jid#"]);
    [account.connectionProperties.identity bindJid:[iqNode findFirst:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/jid#"] onAccount:account];
    DDLogDebug(@"bareJid=%@, resource=%@, fullJid=%@", account.connectionProperties.identity.jid, account.connectionProperties.identity.resource, account.connectionProperties.identity.fullJid);
    
    //update resource in db (could be changed by server)
    NSMutableDictionary* accountDict = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountID]];
    accountDict[kResource] = account.connectionProperties.identity.resource;
    [[DataLayer sharedInstance] updateAccounWithDictionary:accountDict];
    
    [account earlyInitSession];
    
    if(account.connectionProperties.supportsSM3)
    {
        MLXMLNode* enableNode = [[MLXMLNode alloc]
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

+(BOOL) processRosterWithAccount:(xmpp*) account andIqNode:(XMPPIQ*) iqNode
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
        return NO;
    }
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Roster query returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"XMPP Roster Error", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return NO;
    }
    
    NSArray* rosterList = [iqNode find:@"{jabber:iq:roster}query/item"];
    for(MLXMLNode* contactNode in rosterList)
    {
        NSMutableDictionary* contact = [contactNode findFirst:@"/@@"];

        //ignore roster entries without jid (is this even possible?)
        if(contact[@"jid"] == nil)
            continue;
        
        //ignore roster entries providing a full jid instead of bare jids (is that even legitimate?)
        NSDictionary* splitJid = [HelperTools splitJid:contact[@"jid"]];
        if(splitJid[@"resource"] != nil)
            continue;
        
        contact[@"jid"] = [[NSString stringWithFormat:@"%@", contact[@"jid"]] lowercaseString];
        MLContact* contactObj = [MLContact createContactFromJid:contact[@"jid"] andAccountID:account.accountID];
        BOOL isKnownUser = [[DataLayer sharedInstance] contactDictionaryForUsername:contact[@"jid"] forAccount:account.accountID] != nil;
        if([[contact objectForKey:@"subscription"] isEqualToString:kSubRemove])
        {
            if(contactObj.isMuc)
                DDLogWarn(@"Got roster remove request for MUC, ignoring it (possibly even triggered by us).");
            else
            {
                [[DataLayer sharedInstance] deleteContactRequest:contactObj];
                [[DataLayer sharedInstance] removeBuddy:contact[@"jid"] forAccount:account.accountID];
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
            
            if(contactObj.isMuc)
            {
                DDLogWarn(@"Removing muc '%@' from contactlist, got 'normal' roster entry!", contact[@"jid"]);
                [[DataLayer sharedInstance] removeBuddy:contact[@"jid"] forAccount:account.accountID];
                [contactObj removeShareInteractions];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRemoved object:account userInfo:@{@"contact": contactObj}];
                contactObj = [MLContact createContactFromJid:contact[@"jid"] andAccountID:account.accountID];
            }
            
            DDLogVerbose(@"Adding contact %@ (%@) to database", contact[@"jid"], [contact objectForKey:@"name"]);
            [[DataLayer sharedInstance] addContact:contact[@"jid"]
                                        forAccount:account.accountID
                                          nickname:[contact objectForKey:@"name"] ? [contact objectForKey:@"name"] : @""];
            
            DDLogVerbose(@"Setting subscription status '%@' (ask=%@) for contact %@", contact[@"subscription"], contact[@"ask"], contact[@"jid"]);
            [[DataLayer sharedInstance] setSubscription:[contact objectForKey:@"subscription"]
                                                 andAsk:[contact objectForKey:@"ask"]
                                             forContact:contact[@"jid"]
                                             andAccount:account.accountID];
            
            NSSet* groups = [NSSet setWithArray:[contactNode find:@"group#"]];
            DDLogVerbose(@"Setting roster groups for contact %@: %@", contact[@"jid"], groups);
            [[DataLayer sharedInstance] setGroups:groups
                                       forContact:contact[@"jid"]
                                        inAccount:account.accountID];

#ifndef DISABLE_OMEMO
            if(contactObj.isMuc == NO)
            {
                //request omemo devicelist, but only if this is a new user
                //(we could get a roster with already known users if roster version is not supported by the server)
                if(!isKnownUser && !([contact[@"subscription"] isEqualToString:kSubBoth] || [contact[@"subscription"] isEqualToString:kSubTo]))
                    [account.omemo subscribeAndFetchDevicelistIfNoSessionExistsForJid:contact[@"jid"]];
            }
#endif// DISABLE_OMEMO
            
            //regenerate avatar if the nickame has changed
            if(![contactObj.nickName isEqualToString:[contact objectForKey:@"name"]])
                [[MLImageManager sharedInstance] purgeCacheForContact:contact[@"jid"] andAccount:account.accountID];
            
            //send out kMonalContactRefresh notification
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": [MLContact createContactFromJid:contact[@"jid"] andAccountID:account.accountID]
            }];
        }
    }
    
    if([iqNode check:@"{jabber:iq:roster}query@ver"])
        [[DataLayer sharedInstance] setRosterVersion:[iqNode findFirst:@"{jabber:iq:roster}query@ver"] forAccount:account.accountID];
    
    return YES;
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
    account.connectionProperties.accountDiscoFeatures = features;
    
    if(
        [iqNode check:@"{http://jabber.org/protocol/disco#info}query/identity<category=pubsub><type=pep>"] &&       //xep-0163 support
        [features containsObject:@"http://jabber.org/protocol/pubsub#filtered-notifications"] &&                    //needed for xep-0163 support
        [features containsObject:@"http://jabber.org/protocol/pubsub#publish-options"] &&                           //needed for xep-0223 support
        //important xep-0060 support (aka basic support)
        [features containsObject:@"http://jabber.org/protocol/pubsub#publish"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#subscribe"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#create-nodes"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#delete-items"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#delete-nodes"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#persistent-items"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#retrieve-items"] &&
        //not advertised in ejabberd 22.05 but supported
        //[features containsObject:@"http://jabber.org/protocol/pubsub#config-node"] &&
        [features containsObject:@"http://jabber.org/protocol/pubsub#auto-create"] &&
        // [features containsObject:@"http://jabber.org/protocol/pubsub#last-published"] &&
        // [features containsObject:@"http://jabber.org/protocol/pubsub#create-and-configure"] &&
        YES
    ) {
        DDLogInfo(@"Supports pubsub (pep)");
        account.connectionProperties.supportsPubSub = YES;
        
        //modern pep support
        account.connectionProperties.supportsModernPubSub = NO;
        if(
            //needed for xep-0402
            [features containsObject:@"http://jabber.org/protocol/pubsub#item-ids"] &&
            [features containsObject:@"http://jabber.org/protocol/pubsub#multi-items"] &&
            YES
        ) {
            DDLogInfo(@"Supports modern pep multi-items");
            account.connectionProperties.supportsModernPubSub = YES;
        }
        
        account.connectionProperties.supportsPubSubMax = NO;
        if([features containsObject:@"http://jabber.org/protocol/pubsub#config-node-max"])
        {
            DDLogInfo(@"Supports pep 'max' item count");
            account.connectionProperties.supportsPubSubMax = YES;
        }
    }
        
    if([features containsObject:@"urn:xmpp:push:0"])
    {
        DDLogInfo(@"supports push");
        [account enablePush];
    }
    
    if([features containsObject:@"urn:xmpp:mam:2"])
    {
        DDLogInfo(@"supports mam:2");
        
        //query mam since last received stanza ID because we could not resume the smacks session
        //(we would not have landed here if we were able to resume the smacks session)
        //this will do a catchup of everything we might have missed since our last connection
        //we possibly receive sent messages, too (this will update the stanzaid in database and gets deduplicate by messageid,
        //which is guaranteed to be unique (because monal uses uuids for outgoing messages)
        NSString* lastStanzaId = [[DataLayer sharedInstance] lastStanzaIdForAccount:account.accountID];
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
    
    atomic_thread_fence(memory_order_seq_cst);  //make sure our connection properties are "visible" to other threads before marking them as such
    account.connectionProperties.accountDiscoDone = YES;
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalAccountDiscoDone object:account];
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
    account.connectionProperties.serverDiscoFeatures = features;
    
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
    
    if([features containsObject:@"urn:xmpp:blocking"])
        [account fetchBlocklist];
    
    if([features containsObject:@"urn:xmpp:http:upload:0"])
    {
        DDLogInfo(@"supports http upload with server: %@", iqNode.from);
        NSInteger maxFilesize = [[iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{urn:xmpp:http:upload:0}result@max-file-size\\|int"] integerValue];
        if(!account.connectionProperties.supportsHTTPUpload || maxFilesize > account.connectionProperties.uploadSize)
        {
            account.connectionProperties.supportsHTTPUpload = YES;
            account.connectionProperties.uploadServer = iqNode.from;
            account.connectionProperties.uploadSize = maxFilesize;
            DDLogInfo(@"Upload max filesize: %lu", account.connectionProperties.uploadSize);
        }
    }
    
    //query external services to learn stun/turn servers
    if([features containsObject:@"urn:xmpp:extdisco:2"])
        [account queryExternalServicesOn:iqNode.fromUser];

    //get the server's contact addresses (XEP-0157)
    XMPPDataForm* dataForm = [iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/network/serverinfo}result\\"];
    NSMutableDictionary<NSString*, NSArray*>* resultDictionary = [NSMutableDictionary dictionary];
    for(NSString* fieldName in dataForm.allKeys)
    {
        if([fieldName hasSuffix:@"-addresses"])
        {
            NSArray* addresses = [dataForm getField:fieldName][@"allValues"];
            if(addresses != nil && addresses.count > 0)
                resultDictionary[fieldName] = addresses;
        }
    }
    account.connectionProperties.serverContactAddresses = [resultDictionary copy];
$$

$$class_handler(handleServiceDiscoInfo, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    
    //don't use http upload on muc services as general upload server for 1:1 communication
    if([features containsObject:@"urn:xmpp:http:upload:0"] && ![features containsObject:@"http://jabber.org/protocol/muc"])
    {
        DDLogInfo(@"supports http upload with server: %@", iqNode.from);
        NSInteger maxFilesize = [[iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{urn:xmpp:http:upload:0}result@max-file-size\\|int"] integerValue];
        if(!account.connectionProperties.supportsHTTPUpload || maxFilesize > account.connectionProperties.uploadSize)
        {
            account.connectionProperties.supportsHTTPUpload = YES;
            account.connectionProperties.uploadServer = iqNode.from;
            account.connectionProperties.uploadSize = maxFilesize;
            DDLogInfo(@"Upload max filesize: %lu", account.connectionProperties.uploadSize);
        }
    }
    
    if([features containsObject:@"http://jabber.org/protocol/muc"])
        account.connectionProperties.conferenceServers[iqNode.fromUser] = [iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query"];
    
    //query external services to learn stun/turn servers
    if([features containsObject:@"urn:xmpp:extdisco:2"])
        [account queryExternalServicesOn:iqNode.fromUser];
$$

$$class_handler(handleServerDiscoItems, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    account.connectionProperties.discoveredServices = [NSMutableArray new];
    for(NSDictionary* item in [iqNode find:@"{http://jabber.org/protocol/disco#items}query/item@@"])
    {
        [account.connectionProperties.discoveredServices addObject:item];
        if(![[item objectForKey:@"jid"] isEqualToString:account.connectionProperties.identity.domain])
        {
            XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
            [discoInfo setiqTo:[item objectForKey:@"jid"]];
            [discoInfo setDiscoInfoNode];
            [account sendIq:discoInfo withHandler:$newHandler(self, handleServiceDiscoInfo)];
        }
    }
$$

$$class_handler(handleAdhocDisco, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Adhoc command disco query to '%@' returned an error: %@", iqNode.from, [iqNode findFirst:@"error"]);
        return;
    }
    
    account.connectionProperties.discoveredAdhocCommands = [NSMutableDictionary new];
    for(MLXMLNode* item in [iqNode find:@"{http://jabber.org/protocol/disco#items}query<node=http://jabber.org/protocol/commands>/item"])
    {
        if(![[item findFirst:@"/@jid"] isEqualToString:account.connectionProperties.identity.domain])
            continue;
        account.connectionProperties.discoveredAdhocCommands[[item findFirst:@"/@node"]] = nilWrapper([item findFirst:@"/@name"]);
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
$$class_handler(handleEntityCapsDisco, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    NSMutableArray* identities = [NSMutableArray new];
    for(MLXMLNode* identity in [iqNode find:@"{http://jabber.org/protocol/disco#info}query/identity"])
        [identities addObject:[NSString stringWithFormat:@"%@/%@/%@/%@", [identity findFirst:@"/@category"], [identity findFirst:@"/@type"], ([identity check:@"/@xml:lang"] ? [identity findFirst:@"/@xml:lang"] : @""), ([identity check:@"/@name"] ? [identity findFirst:@"/@name"] : @"")]];
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    NSArray* forms = [iqNode find:@"{http://jabber.org/protocol/disco#info}query/{jabber:x:data}x"];
    NSString* ver = [HelperTools getEntityCapsHashForIdentities:identities andFeatures:features andForms:forms];
    [[DataLayer sharedInstance] setCaps:features forVer:ver onAccountID:account.accountID];
    [account markCapsQueryCompleteFor:ver];
    
    //send out kMonalContactRefresh notification
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
        @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountID:account.accountID]
    }];
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
        DDLogError(@"Setting MAM prefs returned an error, ignoring: %@", [iqNode findFirst:@"error"]);
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
    [[DataLayer sharedInstance] updateUsedPushServer:selectedPushServer forAccount:account.accountID];
    DDLogInfo(@"Push is enabled now");
    account.connectionProperties.pushEnabled = YES;
$$

$$class_handler(handleBlocklist, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if(![account.connectionProperties.serverDiscoFeatures containsObject:@"urn:xmpp:blocking"])
    {
        DDLogWarn(@"Ignoring blocklist update, server does not announce support for blocking!");
        return;
    }

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
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalBlockListRefresh object:account userInfo:@{@"accountID": account.accountID}];
    }
$$

$$class_handler(handleBlocked, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, blockedJid))
    if(![account.connectionProperties.serverDiscoFeatures containsObject:@"urn:xmpp:blocking"])
    {
        DDLogWarn(@"Ignoring block result, server does not announce support for blocking!");
        return;
    }
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Blocking returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to block contact %@", @""), blockedJid] withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
$$

$$class_handler(handlePasswordChangeInvalidation, $$ID(xmpp*, account), $$ID(NSString*, uuid), $$PROMISE(promise))
    NSString* jid = account.connectionProperties.identity.jid;
    DDLogError(@"Could not change the password of '%@'", jid);
    [SAMKeychain deletePasswordForService:kMonalTmpKeychainName account:uuid];
    NSString* errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Could not change the password of '%@'. Please try again.", @""), jid];
    NSError* error = [NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
    [promise reject:error];
$$

$$class_handler(handlePasswordChange, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, uuid), $$PROMISE(promise))
    NSString* jid = account.connectionProperties.identity.jid;
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Changing the password of '%@' returned error: %@", jid, [iqNode findFirst:@"error"]);
        [SAMKeychain deletePasswordForService:kMonalTmpKeychainName account:uuid];
        NSString* errorMessage = [HelperTools extractXMPPError:iqNode withDescription:[NSString stringWithFormat:NSLocalizedString(@"Could not change the password of '%@'", @""), jid]];
        NSError* error = [NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
        [promise reject:error];
    }
    else
    {
        NSString* newPass = [SAMKeychain passwordForService:kMonalTmpKeychainName account:uuid];
        [[MLXMPPManager sharedInstance] updatePassword:newPass forAccount: account.accountID];
        [SAMKeychain deletePasswordForService:kMonalTmpKeychainName account:uuid];
        [[HelperTools defaultsDB] setBool:NO forKey:@"autogeneratedPassword"];
        DDLogInfo(@"Successfully changed the password of '%@'", jid);
        [promise fulfill:nil];
    }
    
$$

$$class_handler(handleVersionResponse, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    NSString* iqAppName = [iqNode findFirst:@"{jabber:iq:version}query/name#"];
    NSString* iqAppVersion = [iqNode findFirst:@"{jabber:iq:version}query/version#"];
    NSString* iqPlatformOS = [iqNode findFirst:@"{jabber:iq:version}query/os#"];
    
    //server version info is the only case where there will be no resource --> return here
    if([iqNode.fromUser isEqualToString:account.connectionProperties.identity.domain])
    {
        account.connectionProperties.serverVersion = [[MLContactSoftwareVersionInfo alloc] initWithJid:iqNode.fromUser andRessource:iqNode.fromResource andAppName:iqAppName andAppVersion:iqAppVersion andPlatformOS:iqPlatformOS andLastInteraction:[NSDate date]];
        return;
    }
    
    DDLogVerbose(@"Updating software version info for %@", iqNode.from);
    NSDate* lastInteraction = [[DataLayer sharedInstance] lastInteractionOfJid:iqNode.fromUser andResource:iqNode.fromResource forAccountID:account.accountID];
    MLContactSoftwareVersionInfo* newSoftwareVersionInfo = [[MLContactSoftwareVersionInfo alloc] initWithJid:iqNode.fromUser andRessource:iqNode.fromResource andAppName:iqAppName andAppVersion:iqAppVersion andPlatformOS:iqPlatformOS andLastInteraction:lastInteraction];

    [[DataLayer sharedInstance] setSoftwareVersionInfoForContact:iqNode.fromUser
                                                        resource:iqNode.fromResource
                                                        andAccount:account.accountID
                                                withSoftwareInfo:newSoftwareVersionInfo];
    
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalXmppUserSoftWareVersionRefresh            
                                                        object:account
                                                        userInfo:@{@"versionInfo": newSoftwareVersionInfo}];
$$

$$class_handler(handleModerationResponse, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(MLMessage*, msg))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Moderating message %@ returned an error: %@", msg, [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to moderate message in group/channel '%@'", @""), iqNode.fromUser] withNode:iqNode andAccount:account andIsSevere:YES];
        return;
    }
    
    DDLogInfo(@"Successfully moderated message in muc: %@", msg);
    [[DataLayer sharedInstance] retractMessageHistory:msg.messageDBId];
    
    //update ui
    DDLogInfo(@"Sending out kMonalDeletedMessageNotice notification for historyId %@", msg.messageDBId);
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalDeletedMessageNotice object:account userInfo:@{
        @"historyId": msg.messageDBId,
        @"contact": msg.chatContact,
    }];
$$

#ifdef IS_QUICKSY
$$class_handler(handleQuicksyPhoneBook, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSDictionary*, numbers))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Quicksy phonebook synchronize returned an error: %@", [iqNode findFirst:@"error"]);
        [HelperTools postError:NSLocalizedString(@"Failed to synchronize phonebook", @"") withNode:iqNode andAccount:account andIsSevere:NO];
        return;
    }
    
    for(MLXMLNode* entry in [iqNode find:@"{im.quicksy.synchronization:0}phone-book/entry"])
    {
        NSString* nick = numbers[[entry findFirst:@"/@number"]];
        for(NSString* jid in [entry find:@"jid#"])
        {
            DDLogDebug(@"Adding '%@' with nick '%@' to local roster...", jid, nick);
            [[DataLayer sharedInstance] addContact:jid forAccount:account.accountID nickname:nick];
#ifndef DISABLE_OMEMO
            // Request omemo devicelist
            [account.omemo subscribeAndFetchDevicelistIfNoSessionExistsForJid:jid];
#endif// DISABLE_OMEMO

        }
    }
$$
#endif

+(void) respondWithErrorTo:(XMPPIQ*) iqNode onAccount:(xmpp*) account
{
    XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
    [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"cancel"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"service-unavailable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
    ] andData:nil]];
    [account send:errorIq];
}

@end
