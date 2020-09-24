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

+(void) handleCatchupFor:(xmpp*) account withIqNode:(ParseIq*) iqNode
{
    if(iqNode.mam2Last && !iqNode.mam2fin)
    {
        DDLogVerbose(@"Paging through mam catchup results with after: %@", iqNode.mam2Last);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
        [pageQuery setMAMQueryAfter:iqNode.mam2Last];
        [account sendIq:pageQuery withDelegate:self andMethod:@selector(handleCatchupFor:withIqNode:) andAdditionalArguments:nil];
    }
    else if(iqNode.mam2fin)
    {
        DDLogVerbose(@"Mam catchup finished");
        [account mamFinished];
    }
}

+(void) handleMamResponseWithLatestIdFor:(xmpp*) account withIqNode:(ParseIq*) iqNode
{
    DDLogVerbose(@"Got latest stanza id to prime database with: %@", iqNode.mam2Last);
    //only do this if we got a valid stanza id (not null)
    //if we did not get one we will get one when receiving the next message in this smacks session
    //if the smacks session times out before we get a message and someone sends us one or more messages before we had a chance to establish
    //a new smacks session, this messages will get lost because we don't know how to query the archive for this message yet
    //once we successfully receive the first mam-archived message stanza (could even be an XEP-184 ack for a sent message),
    //no more messages will get lost
    //we ignore this single message loss here, because it should be super rare and solving it would be really complicated
    if(iqNode.mam2Last)
        [[DataLayer sharedInstance] setLastStanzaId:iqNode.mam2Last forAccount:account.accountNo];
    [account mamFinished];
}

-(MLIQProcessor *) initWithAccount:(xmpp*) account connection:(MLXMPPConnection *) connection omemo:(MLOMEMO *)omemo
{
    self = [super init];
    self.account = account;
    self.connection= connection;
    self.omemo = omemo;
    return self;
}

-(MLIQProcessor *) initWithAccount:(xmpp*) account connection:(MLXMPPConnection *) connection
{
    self = [super init];
    self.account = account;
    self.connection= connection;
    return self;
}

-(void) processIq:(ParseIq *) iqNode
{
    
    if(!iqNode.idval) {
        DDLogError(@"iq node missing id");
        return;
    }
    
    if(!iqNode.type) {
        DDLogError(@"iq node missing type");
        return;
    }
    
    if([iqNode.type isEqualToString:kiqGetType])
    {
        //TODO make sure at least 1 child
        [self processGetIq:iqNode];
    }
    else  if([iqNode.type isEqualToString:kiqSetType]) {
        //TODO make sure at least 1 child
        [self processSetIq:iqNode];
    }
    else  if([iqNode.type isEqualToString:kiqResultType]) {
        [self processResultIq:iqNode];
    }
    else  if([iqNode.type isEqualToString:kiqErrorType]) {
        [self processErrorIq:iqNode];
    }
    else {
        DDLogError(@"invalid iq type %@", iqNode.type);
    }
    
}

-(void) processGetIq:(ParseIq *) iqNode
{
    if(iqNode.ping)
    {
        XMPPIQ* pong = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        [pong setiqTo:self.connection.identity.domain];
        self.sendIq(pong, nil, nil);
    }
    
    if(iqNode.version)
    {
        XMPPIQ* versioniq = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        [versioniq setiqTo:iqNode.from];
        [versioniq setVersion];
        self.sendIq(versioniq, nil, nil);
    }
    
    if((iqNode.discoInfo))
    {
        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        if(iqNode.resource && iqNode.resource.length>0)
            [discoInfo setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user, iqNode.resource]];
        else
            [discoInfo setiqTo:iqNode.user];
        [discoInfo setDiscoInfoWithFeaturesAndNode:iqNode.queryNode];
        self.sendIq(discoInfo, nil, nil);
        
    }
}

-(void) processErrorIq:(ParseIq *) iqNode
{
    DDLogError(@"IQ got Error : %@", iqNode.errorMessage);
}

-(void) processSetIq:(ParseIq *) iqNode
{
    //its  a roster push
    if(iqNode.roster==YES)
        [self rosterResult:iqNode];
}

-(void) processResultIq:(ParseIq *) iqNode
{
    // default MAM settings
    if(iqNode.mam2default)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMLMAMPref object:@{@"mamPref":iqNode.mam2default}];
        return;
    }
    
    if(iqNode.shouldSetBind)
    {
        [self.connection bindJid: iqNode.jid];
        DDLogInfo(@"Bind jid %@", iqNode.jid);
        
        if(self.connection.supportsSM3)
        {
            MLXMLNode *enableNode = [[MLXMLNode alloc] initWithElement:@"enable"];
            NSDictionary *dic=@{kXMLNS:@"urn:xmpp:sm:3",@"resume":@"true" };
            enableNode.attributes = [dic mutableCopy];
            self.sendIq(enableNode, nil, nil);
        }
        else
        {
            //init session and query disco, roster etc.
            self.initSession();
        }
    }
    
    if([iqNode.idval isEqualToString:@"enableCarbons"])
    {
		DDLogInfo(@"incoming enableCarbons result");
        self.connection.usingCarbons2=YES;
    }
    
    if(iqNode.discoItems==YES || iqNode.discoInfo==YES)
    {
        [self discoResult:iqNode];
    }
    
    if (iqNode.roster==YES)
    {
        [self rosterResult:iqNode];
    }
    
    if(iqNode.omemoDevices || iqNode.deviceid)
    {
        [self omemoResult:iqNode];
    }
    
    if(iqNode.vCard)
    {
        [self vCardResult:iqNode];
    }
        
    if(iqNode.entitySoftwareVersion)
    {
        [self iqVersionResult:iqNode];
    }
}

#pragma mark - result

-(void) vCardResult:(ParseIq *) iqNode {
    if(!iqNode.user)  {
        DDLogError(@"iq with vcard but not user");
        return;
    }
    
    NSString* fullname=iqNode.fullName;
    if(!fullname) fullname= iqNode.user;
    
    if([fullname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length>0 ) {
        [[DataLayer sharedInstance] setFullName:fullname forContact:iqNode.user andAccount:self.account.accountNo];
        
        if(iqNode.photoBinValue)
        {
            [[MLImageManager sharedInstance] setIconForContact:iqNode.user andAccount:self.account.accountNo WithData:[iqNode.photoBinValue copy]];
        }
        
        if(!fullname) fullname=iqNode.user;
        
        MLContact *contact = [MLContact alloc];
        contact.contactJid=iqNode.user;
        contact.fullName= fullname;
        contact.accountId=self.account.accountNo;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:@{@"contact":contact}];
    }
}

-(void) discoResult:(ParseIq *) iqNode {
    if(iqNode.discoInfo && iqNode.features)
    {
        //features advertised on the home server
        if([iqNode.from isEqualToString:self.connection.identity.domain])
        {
            self.connection.serverFeatures = iqNode.features;
            
            if([iqNode.features containsObject:@"urn:xmpp:carbons:2"])
            {
                DDLogInfo(@"got disco result with carbons ns");
                if(!self.connection.usingCarbons2)
                {
                    DDLogInfo(@"sending enableCarbons iq");
                    self.sendIq([self enableCarbons], nil, nil);
                }
            }
            
            if([iqNode.features containsObject:@"urn:xmpp:ping"])
            {
                self.connection.supportsPing=YES;
            }
            
            if([iqNode.features containsObject:@"urn:xmpp:blocking"])
            {
                self.connection.supportsBlocking=YES;
            }
        }
        
        //features advertised on our own jid/account
        if([iqNode.from isEqualToString:self.connection.identity.jid])
        {
            if([iqNode.features containsObject:@"http://jabber.org/protocol/pubsub#publish"]) {
                self.connection.supportsPubSub = YES;
            }
            
            if([iqNode.features containsObject:@"urn:xmpp:push:0"])
            {
                self.connection.supportsPush = YES;
                self.enablePush();
            }
            
            if([iqNode.features containsObject:@"urn:xmpp:mam:2"])
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

        if(!self.connection.supportsHTTPUpload && [iqNode.features containsObject:@"urn:xmpp:http:upload:0"])
        {
            DDLogInfo(@"supports http upload with server: %@", iqNode.from);
            self.connection.supportsHTTPUpload = YES;
            self.connection.uploadServer = iqNode.from;
        }
        
        if(!self.connection.conferenceServer && [iqNode.features containsObject:@"http://jabber.org/protocol/muc"])
        {
            self.connection.conferenceServer = iqNode.from;
        }
    }
    
    if(iqNode.discoItems && [iqNode.from isEqualToString:self.connection.identity.domain] && !self.connection.discoveredServices)
    {
        self.connection.discoveredServices = [[NSMutableArray alloc] init];
        for(NSDictionary* item in iqNode.items)
        {
            [self.connection.discoveredServices addObject:item];
            if(![[item objectForKey:@"jid"] isEqualToString:self.connection.identity.domain])
                self.sendIq([self discoverService:[item objectForKey:@"jid"]], nil, nil);
        }
        
        // send to bare jid for push etc.
        self.sendIq([self discoverService:self.connection.identity.jid], nil, nil);
    }
    
    //entity caps of some contact
    if(iqNode.discoInfo && iqNode.identities && iqNode.features && ![iqNode.from isEqualToString:self.connection.identity.domain])
    {
        NSString* ver = [HelperTools getEntityCapsHashForIdentities:iqNode.identities andFeatures:iqNode.features];
        [[DataLayer sharedInstance] setCaps:iqNode.features forVer:ver];
    }
}

-(void) rosterResult:(ParseIq *) iqNode {
    if(iqNode.from != nil && ![iqNode.from isEqualToString:self.connection.identity.jid]
       && ![iqNode.from isEqualToString:self.connection.identity.domain]) {
        DDLogError(@"invalid sender for roster. Rejecting.");
        return;
    }
    
    if(iqNode.rosterVersion) {
        [[DataLayer sharedInstance] setRosterVersion:iqNode.rosterVersion forAccount:self.account.accountNo];
    }
    for(NSDictionary* contact in iqNode.items)
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
    
    self.getVcards();
    
}

-(void) omemoResult:(ParseIq *) iqNode {
#ifndef DISABLE_OMEMO
    BOOL __block isBackgrounded = NO;
#ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
    dispatch_sync(dispatch_get_main_queue(), ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        {
            isBackgrounded = YES;
        }
    });
#endif
#endif
    if(!isBackgrounded)
    {
        if(iqNode.omemoDevices) {
            [self.omemo processOMEMODevices:iqNode.omemoDevices from:iqNode.from];
        }
        [self.omemo processOMEMOKeys:iqNode];
    }
#endif
}

-(void) iqVersionResult:(ParseIq *) iqNode
{
    NSString *iqAppName = iqNode.entityName == nil ? @"":iqNode.entityName;
    NSString *iqAppVersion = iqNode.entityVersion == nil ? @"":iqNode.entityVersion;
    NSString *iqPlatformOS = iqNode.entityOs == nil ? @"":iqNode.entityOs;
    
    NSArray *versionDBInfoArr = [[DataLayer sharedInstance] softwareVersionInfoForAccount:self.account.accountNo andContact:iqNode.user];
    
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
                                                             andContact:iqNode.user];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalXmppUserSoftWareVersionRefresh
                                                                object:self
                                                              userInfo:@{@"platform_App_Name":iqAppName,
                                                                      @"platform_App_Version":iqAppVersion,
                                                                               @"platform_OS":iqPlatformOS}];
        }
    }
}

#pragma mark - features

-(XMPPIQ *) discoverService:(NSString *) node
{
    XMPPIQ *discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:node];
    [discoInfo setDiscoInfoNode];
    return discoInfo;
}

-(XMPPIQ*) enableCarbons
{
	DDLogInfo(@"building enableCarbons iq");
    XMPPIQ *carbons = [[XMPPIQ alloc] initWithId:@"enableCarbons" andType:kiqSetType];
    MLXMLNode *enable = [[MLXMLNode alloc] initWithElement:@"enable" andNamespace:@"urn:xmpp:carbons:2"];
    [carbons.children addObject:enable];
    return carbons;
}

@end
