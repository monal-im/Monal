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


@interface MLIQProcessor()

@property (nonatomic, strong) SignalContext *signalContext;
@property (nonatomic, strong) MLSignalStore *monalSignalStore;
@property (nonatomic, strong) MLXMPPConnection *connection;
@property (nonatomic, strong) NSString *accountNo;

@end

/**
 Validate and process an iq elements.
 @link https://xmpp.org/rfcs/rfc6120.html#stanzas-semantics-iq
 */
@implementation MLIQProcessor

-(MLIQProcessor *) initWithAccount:(NSString *) accountNo connection:(MLXMPPConnection *) connection signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore
{
    self = [super init];
    self.accountNo = accountNo;
    self.connection= connection;
    self.signalContext=signalContext;
    self.monalSignalStore= monalSignalStore;
    return self;
}

-(MLIQProcessor *) initWithAccount:(NSString *) accountNo connection:(MLXMPPConnection *) connection
{
    self = [super init];
    self.accountNo = accountNo;
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
        if(self.sendIq)
            self.sendIq(pong, nil, nil);
    }
    
    if(iqNode.version)
    {
        XMPPIQ* versioniq = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        [versioniq setiqTo:iqNode.from];
        [versioniq setVersion];
        if(self.sendIq)
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
        if(self.sendIq)
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
    if(iqNode.mam2Last && !iqNode.mam2fin)
    {
        //do RSM paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
        [pageQuery setMAMQueryFromStart:nil after:iqNode.mam2Last withMax:nil andJid:nil];
        if(self.sendIq)
            self.sendIq(pageQuery, nil, nil);
        return;
    }
    
    if(iqNode.mam2fin)
    {
        if(self.mamFinished)
            self.mamFinished();
        return;
    }
    
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
            if(self.sendIq)
                self.sendIq(enableNode, nil, nil);
        }
        else
        {
            //init session and query disco, roster etc.
            if(self.initSession)
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
        [[DataLayer sharedInstance] setFullName:fullname forContact:iqNode.user andAccount:self.accountNo];
        
        if(iqNode.photoBinValue)
        {
            [[MLImageManager sharedInstance] setIconForContact:iqNode.user andAccount:self.accountNo WithData:[iqNode.photoBinValue copy]];
        }
        
        if(!fullname) fullname=iqNode.user;
        
        MLContact *contact = [MLContact alloc];
        contact.contactJid=iqNode.user;
        contact.fullName= fullname;
        contact.accountId=self.accountNo;
        
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
                    if(self.sendIq)
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
            [iqNode.features.allObjects enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString *feature = (NSString *)obj;
                if([feature isEqualToString:@"http://jabber.org/protocol/pubsub#publish"]) {
                    self.connection.supportsPubSub=YES;
                    *stop=YES;
#ifndef DISABLE_OMEMO
                    if(self.sendSignalInitialStanzas) self.sendSignalInitialStanzas();
#endif
                }
            }];
            
            if([iqNode.features containsObject:@"urn:xmpp:push:0"])
            {
                self.connection.supportsPush=YES;
                if(self.enablePush) self.enablePush();
            }
            
            if([iqNode.features containsObject:@"urn:xmpp:mam:2"])
            {
                if(!self.connection.supportsMam2)
                {
                    self.connection.supportsMam2 = YES;
                    DDLogInfo(@"supports mam:2");
                    
                    //query mam since last received message because we could not resume the smacks session
                    //(we would not have landed here if we were able to resume the smacks session)
                    //this will do a catchup of everything we might have missed since our last connection
                    [[DataLayer sharedInstance] lastStanzaIdForAccount:self.accountNo withCompletion:^(NSString* lastStanzaId, NSDate* lastStanzaDate) {
                        DDLogInfo(@"Querying mam archive after stanzaid %@ and date %@ for catchup", lastStanzaId, lastStanzaDate);
                        XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
                        [mamQuery setMAMQueryFromStart:nil after:lastStanzaId withMax:nil andJid:nil];
                        if(self.sendIq)
                            self.sendIq(mamQuery, nil, nil);
                    }];
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
                if(self.sendIq)
                    self.sendIq([self discoverService:[item objectForKey:@"jid"]], nil, nil);
        }
        
        // send to bare jid for push etc.
        if(self.sendIq)
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
        [[DataLayer sharedInstance] setRosterVersion:iqNode.rosterVersion forAccount:self.accountNo];
    }
    for(NSDictionary* contact in iqNode.items)
    {
        if([[contact objectForKey:@"subscription"] isEqualToString:kSubRemove])
        {
            [[DataLayer sharedInstance] removeBuddy:[contact objectForKey:@"jid"] forAccount:self.accountNo];
        }
        else
        {
            if([[contact objectForKey:@"subscription"] isEqualToString:kSubTo])
            {
                MLContact *contactObj = [[MLContact alloc] init];
                contactObj.contactJid = [contact objectForKey:@"jid"];
                contactObj.accountId=self.accountNo;
                [[DataLayer sharedInstance] addContactRequest:contactObj];
            }
            
            if([[contact objectForKey:@"subscription"] isEqualToString:kSubFrom]) //already subscribed
            {
                MLContact *contactObj = [[MLContact alloc] init];
                contactObj.contactJid = [contact objectForKey:@"jid"];
                contactObj.accountId=self.accountNo;
                [[DataLayer sharedInstance] deleteContactRequest:contactObj];
            }
            
            DDLogVerbose(@"Adding contact %@ (%@) to database", [contact objectForKey:@"jid"], [contact objectForKey:@"name"]);
            [[DataLayer sharedInstance] addContact:[contact objectForKey:@"jid"]
                                        forAccount:self.accountNo
                                          fullname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                          nickname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                        andMucNick:nil
                                    withCompletion:^(BOOL success) {
                
                [[DataLayer sharedInstance] setSubscription:[contact objectForKey:@"subscription"]
                                                     andAsk:[contact objectForKey:@"ask"] forContact:[contact objectForKey:@"jid"] andAccount:self.accountNo];
                
                if(!success && ((NSString *)[contact objectForKey:@"name"]).length>0)
                {
                    [[DataLayer sharedInstance] setFullName:[contact objectForKey:@"name"] forContact:[contact objectForKey:@"jid"] andAccount:self.accountNo ] ;
                }
            }];
            
        }
    }
    
    if(self.getVcards) self.getVcards();
    
}

-(void) sendOMEMODevices:(NSArray *) devices {
    if(!self.connection.supportsPubSub) return;
    
    XMPPIQ *signalDevice = [[XMPPIQ alloc] initWithType:kiqSetType];
    [signalDevice publishDevices:devices];
    if(self.sendIq)
        self.sendIq(signalDevice, nil, nil);
}


-(void) queryOMEMOBundleFrom:(NSString *) jid andDevice:(NSString *) deviceid
{
    if(!self.connection.supportsPubSub) return;
    XMPPIQ* query2 = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [query2 setiqTo:jid];
    [query2 requestBundles:deviceid];
    if(self.sendIq)
        self.sendIq(query2, nil, nil);
}

-(void) omemoResult:(ParseIq *) iqNode {
#ifndef DISABLE_OMEMO
    [self processOMEMODevices:iqNode];
    [self processOMEMOKeys:iqNode];
#endif
}


-(void) processOMEMODevices:(ParseIq *) iqNode{
    NSString *source= iqNode.from;
    if(iqNode.omemoDevices)
    {
        
        if(!source || [source isEqualToString:self.connection.identity.jid])
        {
            source=self.connection.identity.jid;
            NSMutableArray *devices= [iqNode.omemoDevices mutableCopy];
            NSSet *deviceSet = [NSSet setWithArray:iqNode.omemoDevices];
            
            NSString * deviceString = [NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
            if(![deviceSet containsObject:deviceString])
            {
                [devices addObject:deviceString];
            }
            
            [self sendOMEMODevices:devices];
        }
        
        
        NSArray *existingDevices = [self.monalSignalStore knownDevicesForAddressName:source];
        NSSet *deviceSet = [NSSet setWithArray:existingDevices];
        //only query if the device doesnt exist
        [iqNode.omemoDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *deviceString  =(NSString *)obj;
            NSNumber *deviceNumber = [NSNumber numberWithInt:deviceString.intValue];
            if(![deviceSet containsObject:deviceNumber]) {
                [self queryOMEMOBundleFrom:source andDevice:deviceString];
            } else  {
               
            }
        }];
        
        //if not in device list remove from  knowndevices
        NSSet *iqSet = [NSSet setWithArray:iqNode.omemoDevices];
        [existingDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSNumber *device  =(NSNumber *)obj;
            NSString *deviceString = [NSString stringWithFormat:@"%@", device];
            if(![iqSet containsObject:deviceString]) {
                //device was removed
                SignalAddress *address = [[SignalAddress alloc] initWithName:source deviceId:(int) device.integerValue];
                [self.monalSignalStore deleteDeviceforAddress:address];
            }
        }];
        
    }
    
}

-(void) processOMEMOKeys:(ParseIq *) iqNode{
    
    if(iqNode.signedPreKeyPublic && self.signalContext )
    {
        NSString *source= iqNode.from;
        if(!source)
        {
            source=self.connection.identity.jid;
        }
        
        uint32_t device =(uint32_t)[iqNode.deviceid intValue];
        if(!iqNode.deviceid) return;
        
        SignalAddress *address = [[SignalAddress alloc] initWithName:source deviceId:device];
        SignalSessionBuilder *builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self.signalContext];
        
        [iqNode.preKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            NSDictionary *row = (NSDictionary *) obj;
            NSString *keyid = (NSString *)[row objectForKey:@"preKeyId"];
            NSData *preKeyData = [HelperTools dataWithBase64EncodedString:[row objectForKey:@"preKey"]];
            if(preKeyData) {
                SignalPreKeyBundle *bundle = [[SignalPreKeyBundle alloc] initWithRegistrationId:0
                                                                                       deviceId:device
                                                                                       preKeyId:[keyid intValue]
                                                                                   preKeyPublic:preKeyData
                                                                                 signedPreKeyId:iqNode.signedPreKeyId.intValue
                                                                             signedPreKeyPublic:[HelperTools dataWithBase64EncodedString:iqNode.signedPreKeyPublic]
                                                                                      signature:[HelperTools dataWithBase64EncodedString:iqNode.signedPreKeySignature]
                                                                                    identityKey:[HelperTools dataWithBase64EncodedString:iqNode.identityKey]
                                                                                          error:nil];
                
                [builder processPreKeyBundle:bundle error:nil];
            } else  {
                DDLogError(@"Could not decode base64 prekey %@", row);
            }
        }];
        
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
