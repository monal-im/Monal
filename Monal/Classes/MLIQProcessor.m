//
//  MLIQProcessor.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLIQProcessor.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import "MLImageManager.h"
#import "HelperTools.h"
#import "MLOMEMO.h"

@class MLOMEMO;

@interface MLIQProcessor()

@property (nonatomic, strong) MLOMEMO* omemo;
@property (nonatomic, strong) MLXMPPConnection *connection;
@property (nonatomic, strong) xmpp* account;

@end

/**
 Validate and process any iq elements.
 @link https://xmpp.org/rfcs/rfc6120.html#stanzas-semantics-iq
 */
@implementation MLIQProcessor

+(void) handleCatchupFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode
{
    if([[iqNode findFirst:@"/@type"] isEqualToString:@"error"])
    {
        DDLogWarn(@"Mam catchup query returned error: %@", [iqNode findFirst:@"error"]);
        [account mamFinished];
        return;
    }
    if(![iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] && [iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
    {
        DDLogVerbose(@"Paging through mam catchup results with after: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
        [pageQuery setMAMQueryAfter:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]];
        [account sendIq:pageQuery withDelegate:self andMethod:@selector(handleCatchupFor:withIqNode:) andAdditionalArguments:nil];
    }
    else if([iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"])
    {
        DDLogVerbose(@"Mam catchup finished");
        [account mamFinished];
    }
}

+(void) handleMamResponseWithLatestIdFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode
{
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
    [account mamFinished];
}

-(MLIQProcessor *) initWithAccount:(xmpp*) account connection:(MLXMPPConnection*) connection omemo:(MLOMEMO*) omemo
{
    self = [super init];
    self.account = account;
    self.connection= connection;
    self.omemo = omemo;
    return self;
}

-(MLIQProcessor *) initWithAccount:(xmpp*) account connection:(MLXMPPConnection*) connection
{
    self = [super init];
    self.account = account;
    self.connection = connection;
    return self;
}

-(void) processIq:(XMPPIQ*) iqNode
{
    if([[iqNode findFirst:@"/@type"] isEqualToString:kiqGetType])
        [self processGetIq:iqNode];
    else if([[iqNode findFirst:@"/@type"] isEqualToString:kiqSetType])
        [self processSetIq:iqNode];
    else if([[iqNode findFirst:@"/@type"] isEqualToString:kiqResultType])
        [self processResultIq:iqNode];
    else if([[iqNode findFirst:@"/@type"] isEqualToString:kiqErrorType])
        [self processErrorIq:iqNode];
    else
        DDLogError(@"invalid iq type %@", [iqNode findFirst:@"/@type"]);
}

-(void) processGetIq:(XMPPIQ*) iqNode
{
    if([iqNode check:@"{urn:xmpp:ping}ping"])
    {
        XMPPIQ* pong = [[XMPPIQ alloc] initWithId:[iqNode findFirst:@"/@id"] andType:kiqResultType];
        [pong setiqTo:self.connection.identity.domain];
        self.sendIq(pong, nil, nil);
    }
    
    if([iqNode check:@"{jabber:iq:version}query"])
    {
        XMPPIQ* versioniq = [[XMPPIQ alloc] initWithId:[iqNode findFirst:@"/@id"] andType:kiqResultType];
        [versioniq setiqTo:iqNode.from];
        [versioniq setVersion];
        self.sendIq(versioniq, nil, nil);
    }
    
    if([iqNode check:@"{http://jabber.org/protocol/disco#info}query"])
    {
        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithId:[iqNode findFirst:@"/@id"] andType:kiqResultType];
        [discoInfo setiqTo:iqNode.from];
        [discoInfo setDiscoInfoWithFeaturesAndNode:[iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query@node"]];
        self.sendIq(discoInfo, nil, nil);
    }
}

-(void) processErrorIq:(XMPPIQ*) iqNode
{
    DDLogError(@"Got (probably unhandled) IQ error: %@", iqNode);
}

-(void) processSetIq:(XMPPIQ *) iqNode
{
    //its  a roster push
    if([iqNode check:@"{jabber:iq:roster}query"])
    {
        [self rosterResult:iqNode];
        
        //send empty result iq as per XMPP CORE requirements
        XMPPIQ* reply = [[XMPPIQ alloc] initWithId:[iqNode findFirst:@"/@id"] andType:kiqResultType];
        [reply setiqTo:iqNode.from];
        self.sendIq(reply, nil, nil);
    }
}

-(void) processResultIq:(XMPPIQ*) iqNode
{
    // default MAM settings
    if([iqNode check:@"{urn:xmpp:mam:2}prefs@default"])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMLMAMPref object:@{@"mamPref": [iqNode findFirst:@"{urn:xmpp:mam:2}prefs@default"]}];
        return;
    }
    
    if([iqNode check:@"{urn:ietf:params:xml:ns:xmpp-bind}bind"])
    {
        [self.connection bindJid:[iqNode findFirst:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/jid#"]];
        DDLogInfo(@"Bind jid %@", [iqNode findFirst:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/jid#"]);
        
        if(self.connection.supportsSM3)
        {
            MLXMLNode *enableNode = [[MLXMLNode alloc]
                initWithElement:@"enable"
                andNamespace:@"urn:xmpp:sm:3"
                withAttributes:@{@"resume": @"true"}
                andChildren:@[]
                andData:nil
            ];
            self.sendIq(enableNode, nil, nil);
        }
        else
        {
            //init session and query disco, roster etc.
            self.initSession();
        }
    }
    
    if([[iqNode findFirst:@"/@id"] isEqualToString:@"enableCarbons"])
    {
		DDLogInfo(@"incoming enableCarbons result");
        self.connection.usingCarbons2 = YES;
    }
    
    if([iqNode check:@"{http://jabber.org/protocol/disco#items}query"] || [iqNode check:@"{http://jabber.org/protocol/disco#info}query"])
        [self discoResult:iqNode];
    
    if([iqNode check:@"{jabber:iq:roster}query"])
        [self rosterResult:iqNode];
    
    if([iqNode check:@"{http://jabber.org/protocol/pubsub}pubsub/items<node=eu\\.siacs\\.conversations\\.axolotl\\.bundles:[0-9]+>"] ||
       [iqNode check:@"{http://jabber.org/protocol/pubsub}pubsub/items<node=eu\\.siacs\\.conversations\\.axolotl\\.devicelist>"]) {
        [self omemoResult:iqNode];
    }
    
    if([iqNode check:@"{vcard-temp}vCard"])
        [self vCardResult:iqNode];
        
    if([iqNode check:@"{jabber:iq:version}query"])
        [self iqVersionResult:iqNode];
}

#pragma mark - result

-(void) vCardResult:(XMPPIQ*) iqNode
{
    if(!iqNode.fromUser)
    {
        DDLogError(@"iq with vcard but not user");
        return;
    }
    
    NSString* fullname = [iqNode findFirst:@"{vcard-temp}vCard/FN#"];
    if(!fullname)
        fullname = iqNode.fromUser;
    
    if([fullname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0)
    {
        [[DataLayer sharedInstance] setFullName:fullname forContact:iqNode.fromUser andAccount:self.account.accountNo];
        
        if([iqNode check:@"{vcard-temp}vCard/PHOTO/BINVAL#"])
            [[MLImageManager sharedInstance] setIconForContact:iqNode.fromUser andAccount:self.account.accountNo WithData:[iqNode findFirst:@"{vcard-temp}vCard/PHOTO/BINVAL#"]];
        
        MLContact *contact = [MLContact alloc];
        contact.contactJid = iqNode.fromUser;
        contact.fullName = fullname;
        contact.accountId = self.account.accountNo;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:@{@"contact": contact}];
    }
}

-(void) discoResult:(XMPPIQ*) iqNode
{
    if([iqNode check:@"{http://jabber.org/protocol/disco#info}query"])
    {
        NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
        
        //features advertised on the home server
        if([iqNode.from isEqualToString:self.connection.identity.domain])
        {
            self.connection.serverFeatures = features;
            
            if([features containsObject:@"urn:xmpp:carbons:2"])
            {
                DDLogInfo(@"got disco result with carbons ns");
                if(!self.connection.usingCarbons2)
                {
                    DDLogInfo(@"sending enableCarbons iq");
                    self.sendIq([self enableCarbons], nil, nil);
                }
            }
            
            if([features containsObject:@"urn:xmpp:ping"])
                self.connection.supportsPing = YES;
            
            if([features containsObject:@"urn:xmpp:blocking"])
                self.connection.supportsBlocking=YES;
        }
        
        //features advertised on our own jid/account
        if([iqNode.from isEqualToString:self.connection.identity.jid])
        {
            if([features containsObject:@"http://jabber.org/protocol/pubsub#publish"])
                self.connection.supportsPubSub = YES;
            
            if([features containsObject:@"urn:xmpp:push:0"])
            {
                self.connection.supportsPush = YES;
                self.enablePush();
            }
            
            if([features containsObject:@"urn:xmpp:mam:2"])
            {
                if(!self.connection.supportsMam2)
                {
                    self.connection.supportsMam2 = YES;
                    DDLogInfo(@"supports mam:2");
                    
                    //query mam since last received stanza ID because we could not resume the smacks session
                    //(we would not have landed here if we were able to resume the smacks session)
                    //this will do a catchup of everything we might have missed since our last connection
                    //we possibly receive sent messages, too (this will update the stanzaid in database and gets deduplicate by messageid,
                    //which is guaranteed to be unique (because monal uses uuids for outgoing messages)
                    NSString* lastStanzaId = [[DataLayer sharedInstance] lastStanzaIdForAccount:self.account.accountNo];
                    XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
                    if(lastStanzaId)
                    {
                        DDLogInfo(@"Querying mam:2 archive after stanzaid '%@' for catchup", lastStanzaId);
                        [mamQuery setMAMQueryAfter:lastStanzaId];
                        self.sendIqWithDelegate(mamQuery, [self class], @selector(handleCatchupFor:withIqNode:), nil);
                    }
                    else
                    {
                        DDLogInfo(@"Querying mam:2 archive for latest stanzaid to prime database");
                        [mamQuery setMAMQueryForLatestId];
                        self.sendIqWithDelegate(mamQuery, [self class], @selector(handleMamResponseWithLatestIdFor:withIqNode:), nil);
                    }
                }
            }
        }

        if(!self.connection.supportsHTTPUpload && [features containsObject:@"urn:xmpp:http:upload:0"])
        {
            DDLogInfo(@"supports http upload with server: %@", iqNode.from);
            self.connection.supportsHTTPUpload = YES;
            self.connection.uploadServer = iqNode.from;
        }
        
        if(!self.connection.conferenceServer && [features containsObject:@"http://jabber.org/protocol/muc"])
            self.connection.conferenceServer = iqNode.from;
    }
    
    if(
        [iqNode check:@"{http://jabber.org/protocol/disco#items}query"] &&
        [iqNode.from isEqualToString:self.connection.identity.domain] &&
        !self.connection.discoveredServices
    )
    {
        // send to bare jid for push etc.
        self.sendIq([self discoverService:self.connection.identity.jid], nil, nil);
        
        self.connection.discoveredServices = [[NSMutableArray alloc] init];
        for(NSDictionary* item in [iqNode find:@"{http://jabber.org/protocol/disco#items}query/item@@"])
        {
            [self.connection.discoveredServices addObject:item];
            if(![[item objectForKey:@"jid"] isEqualToString:self.connection.identity.domain])
                self.sendIq([self discoverService:[item objectForKey:@"jid"]], nil, nil);
        }
    }
    
    //entity caps of some contact
    if([iqNode check:@"http://jabber.org/protocol/disco#info"] && ![iqNode.from isEqualToString:self.connection.identity.domain])
    {
        NSMutableArray* identities = [[NSMutableArray alloc] init];
        for(NSDictionary* attrs in [iqNode find:@"http://jabber.org/protocol/disco#info/identity@@"])
            [identities addObject:[NSString stringWithFormat:@"%@/%@/%@/%@",
                attrs[@"category"] ? attrs[@"category"] : @"",
                attrs[@"type"] ? attrs[@"type"] : @"",
                //TODO: check if the xml parser parses this to 'xml:lang' or 'lang' and change accordingly
                attrs[@"lang"] ? attrs[@"lang"] : @"",
                attrs[@"name"] ? attrs[@"name"] : @""
            ]];
        NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
        NSString* ver = [HelperTools getEntityCapsHashForIdentities:identities andFeatures:features];
        [[DataLayer sharedInstance] setCaps:features forVer:ver];
    }
}

-(void) rosterResult:(XMPPIQ*) iqNode
{
    if(
        iqNode.from != nil &&
        ![iqNode.from isEqualToString:self.connection.identity.jid] &&
        ![iqNode.from isEqualToString:self.connection.identity.domain]
    )
    {
        DDLogError(@"invalid sender for roster. Rejecting.");
        return;
    }
    
    for(NSDictionary* contact in [iqNode find:@"{jabber:iq:roster}query/item@@"])
    {
        if([[contact objectForKey:@"subscription"] isEqualToString:kSubRemove])
        {
            [[DataLayer sharedInstance] removeBuddy:[contact objectForKey:@"jid"] forAccount:self.account.accountNo];
        }
        else
        {
            if([[contact objectForKey:@"subscription"] isEqualToString:kSubTo])
            {
                MLContact *contactObj = [[MLContact alloc] init];
                contactObj.contactJid = [contact objectForKey:@"jid"];
                contactObj.accountId=self.account.accountNo;
                [[DataLayer sharedInstance] addContactRequest:contactObj];
            }
            
            if([[contact objectForKey:@"subscription"] isEqualToString:kSubFrom]) //already subscribed
            {
                MLContact *contactObj = [[MLContact alloc] init];
                contactObj.contactJid = [contact objectForKey:@"jid"];
                contactObj.accountId=self.account.accountNo;
                [[DataLayer sharedInstance] deleteContactRequest:contactObj];
            }
            
            DDLogVerbose(@"Adding contact %@ (%@) to database", [contact objectForKey:@"jid"], [contact objectForKey:@"name"]);
            BOOL success = [[DataLayer sharedInstance] addContact:[contact objectForKey:@"jid"]
                                        forAccount:self.account.accountNo
                                          fullname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                          nickname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                                       andMucNick:nil];
                
            [[DataLayer sharedInstance] setSubscription:[contact objectForKey:@"subscription"]
                                                 andAsk:[contact objectForKey:@"ask"] forContact:[contact objectForKey:@"jid"] andAccount:self.account.accountNo];
            
            if(!success && ((NSString *)[contact objectForKey:@"name"]).length>0)
            {
                [[DataLayer sharedInstance] setFullName:[contact objectForKey:@"name"] forContact:[contact objectForKey:@"jid"] andAccount:self.account.accountNo ] ;
            }
        }
    }
    
    if([iqNode check:@"{jabber:iq:roster}query@ver"])
        [[DataLayer sharedInstance] setRosterVersion:[iqNode findFirst:@"{jabber:iq:roster}query@ver"] forAccount:self.account.accountNo];
    
    self.getVcards();
}

-(void) omemoResult:(XMPPIQ *) iqNode {
#ifndef DISABLE_OMEMO
    if([iqNode check:@"{http://jabber.org/protocol/pubsub}pubsub/items<node=eu\\.siacs\\.conversations\\.axolotl\\.devicelist>"]) {
        NSArray<NSNumber*>* deviceIds =  [iqNode find:@"{http://jabber.org/protocol/pubsub}pubsub/items<node=eu\\.siacs\\.conversations\\.axolotl\\.devicelist>/item/{eu.siacs.conversations.axolotl}list/device@id|int"];
        NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];
        [self.omemo processOMEMODevices:deviceSet from:iqNode.from];
    } else if([iqNode check:@"{http://jabber.org/protocol/pubsub}pubsub/items<node=eu\\.siacs\\.conversations\\.axolotl\\.bundles:[0-9]+>"]) {
        [self.omemo processOMEMOKeys:iqNode];
    }
#endif
}

-(void) iqVersionResult:(XMPPIQ *) iqNode
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
    
    NSArray *versionDBInfoArr = [[DataLayer sharedInstance] softwareVersionInfoForAccount:self.account.accountNo andContact:iqNode.fromUser];
    
    if ((versionDBInfoArr != nil) && ([versionDBInfoArr count] > 0)) {
        NSDictionary *versionInfoDBDic = versionDBInfoArr[0];
        
        if (!([[versionInfoDBDic objectForKey:@"platform_App_Name"] isEqualToString:iqAppName] &&
            [[versionInfoDBDic objectForKey:@"platform_App_Version"] isEqualToString:iqAppVersion] &&
            [[versionInfoDBDic objectForKey:@"platform_OS"] isEqualToString:iqPlatformOS]))
        {
            [[DataLayer sharedInstance] setSoftwareVersionInfoForAppName:iqAppName
                                                             appVersion:iqAppVersion
                                                             platformOS:iqPlatformOS
                                                            withAccount:self.account.accountNo
                                                             andContact:iqNode.fromUser];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalXmppUserSoftWareVersionRefresh
                                                                object:self
                                                              userInfo:@{@"platform_App_Name":iqAppName,
                                                                      @"platform_App_Version":iqAppVersion,
                                                                               @"platform_OS":iqPlatformOS}];
        }
    }
}

#pragma mark - features

-(XMPPIQ*) discoverService:(NSString*) node
{
    XMPPIQ *discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:node];
    [discoInfo setDiscoInfoNode];
    return discoInfo;
}

-(XMPPIQ*) enableCarbons
{
	DDLogInfo(@"building enableCarbons iq");
    XMPPIQ* carbons = [[XMPPIQ alloc] initWithId:@"enableCarbons" andType:kiqSetType];
    MLXMLNode* enable = [[MLXMLNode alloc] initWithElement:@"enable" andNamespace:@"urn:xmpp:carbons:2"];
    [carbons addChild:enable];
    return carbons;
}

@end
