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


static const int ddLogLevel = LOG_LEVEL_DEBUG;

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
    self=[super init];
    self.accountNo = accountNo;
    self.connection= connection;
    self.signalContext=signalContext;
    self.monalSignalStore= monalSignalStore;
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

-(void) processGetIq:(ParseIq *) iqNode {
    
    if(iqNode.ping)
    {
        XMPPIQ* pong =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        [pong setiqTo:self.connection.identity.domain];
        if(self.sendIq) self.sendIq(pong);
    }
    
    if (iqNode.version)
    {
        XMPPIQ* versioniq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        [versioniq setiqTo:iqNode.from];
        [versioniq setVersion];
        if(self.sendIq) self.sendIq(versioniq);
    }
    
    if (iqNode.last)
    {
        XMPPIQ* lastiq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        [lastiq setiqTo:iqNode.from];
        [lastiq setLast];
        if(self.sendIq) self.sendIq(lastiq);
    }
    
    
    if((iqNode.discoInfo))
    {
        XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        if(iqNode.resource) {
            [discoInfo setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user, iqNode.resource]];
        } else  {
            [discoInfo setiqTo:iqNode.user];
        }
        [discoInfo setDiscoInfoWithFeaturesAndNode:iqNode.queryNode];
        if(self.sendIq) self.sendIq(discoInfo);
        
    }
}

-(void) processErrorIq:(ParseIq *) iqNode {
    DDLogError(@"IQ got Error : %@", iqNode.errorMessage);
}

-(void) processSetIq:(ParseIq *) iqNode {
    
    
}

-(void) processResultIq:(ParseIq *) iqNode {
    
    //TODO maybe remove this.
    if(iqNode.mam2Last && !iqNode.mam2fin)
    {
        //RSM seems broken on servers. Indicate  there is more to fetch
        [[NSNotificationCenter defaultCenter] postNotificationName:kMLMAMMore object:nil];
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
            MLXMLNode *enableNode =[[MLXMLNode alloc] initWithElement:@"enable"];
            NSDictionary *dic=@{kXMLNS:@"urn:xmpp:sm:3",@"resume":@"true" };
            enableNode.attributes =[dic mutableCopy];
            if(self.sendIq) self.sendIq(enableNode);
        }
        else
        {
            //init session and query disco, roster etc.
            if(self.initSession) self.initSession();
        }
    }
    
    if([iqNode.idval isEqualToString:@"enableCarbons"])
    {
        self.connection.usingCarbons2=YES;
        //  [self cleanEnableCarbons];
    }
    
    if(iqNode.discoItems==YES || iqNode.discoInfo==YES)
    {
        [self discoResult:iqNode];
    }
    
    if (iqNode.roster==YES)
    {
        [self rosterResult:iqNode];
    }
    
    if(iqNode.omemoDevices)
    {
        [self omemoResult];
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
        
        MLContact *contact =[MLContact alloc];
        contact.contactJid=iqNode.user;
        contact.fullName= fullname;
        contact.accountId=self.accountNo;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:@{@"contact":contact}];
    }
}

-(void) discoResult:(ParseIq *) iqNode {
    
    //        if(iqNode.discoInfo) {
    //            [self cleanDisco];
    //        }
    
    if(iqNode.features && iqNode.discoInfo) {
        if([iqNode.from isEqualToString:self.connection.server.host] ||
           [iqNode.from isEqualToString:self.connection.identity.domain]) {
            self.connection.serverFeatures=iqNode.features;
            [self parseFeatures];
            
#ifndef DISABLE_OMEMO
            if(self.sendSignalInitialStanzas) self.sendSignalInitialStanzas();
#endif
        }
        
        if([iqNode.features containsObject:@"urn:xmpp:http:upload"])
        {
            self.connection.supportsHTTPUpload=YES;
            self.connection.uploadServer = iqNode.from;
        }
        
        if([iqNode.features containsObject:@"http://jabber.org/protocol/muc"])
        {
            self.connection.conferenceServer=iqNode.from;
        }
        
        if([iqNode.features containsObject:@"urn:xmpp:push:0"])
        {
            self.connection.supportsPush=YES;
            if(self.enablePush) self.enablePush();
        }
        
        if([iqNode.features containsObject:@"urn:xmpp:mam:2"])
        {
            self.connection.supportsMam2=YES;
            DDLogInfo(@" supports mam:2");
        }
    }
    
    if(iqNode.legacyAuth)
    {
        XMPPIQ* auth =[[XMPPIQ alloc] initWithId:@"auth2" andType:kiqSetType];
        [auth setAuthWithUserName:self.connection.identity.jid resource:self.connection.identity.resource andPassword:self.connection.identity.password];
        self.sendIq(auth);
        return;
    }
    

    if(([iqNode.from isEqualToString:self.connection.server.host] ||
        [iqNode.from isEqualToString:self.connection.identity.domain]) &&
       !self.connection.discoveredServices)
    {
        self.connection.discoveredServices=[[NSMutableArray alloc] init];
        for (NSDictionary* item in iqNode.items)
        {
            [self.connection.discoveredServices addObject:item];
            
            if((![[item objectForKey:@"jid"] isEqualToString:self.connection.server.host]  &&
                ![[item objectForKey:@"jid"] isEqualToString:self.connection.identity.domain])) {
                if(self.sendIq) self.sendIq([self discoverService:[item objectForKey:@"jid"]]);
            }
        }
        
        // send to bare jid for push etc.
        if(self.sendIq) self.sendIq([self discoverService:self.connection.identity.jid]);
    }
}

-(void) rosterResult:(ParseIq *) iqNode {
    
    for(NSDictionary* contact in iqNode.items)
    {
        if(iqNode.rosterVersion) {
            [[DataLayer sharedInstance] setRosterVersion:iqNode.rosterVersion forAccount:self.accountNo];
        }
        
        if([[contact objectForKey:@"subscription"] isEqualToString:@"both"])
        {
            if([contact objectForKey:@"jid"]) {
                [[DataLayer sharedInstance] addContact:[contact objectForKey:@"jid"]
                                            forAccount:self.accountNo
                                              fullname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                              nickname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                        withCompletion:^(BOOL success) {
                    
                    if(!success && ((NSString *)[contact objectForKey:@"name"]).length>0)
                    {
                        [[DataLayer sharedInstance] setFullName:[contact objectForKey:@"name"] forContact:[contact objectForKey:@"jid"] andAccount:self.accountNo ] ;
                    }
                }];
            }
        }
    }
    
    if(self.getVcards) self.getVcards();
    
}

-(void) omemoResult {
    //    if ([iqNode.type isEqualToString:kiqResultType])
    //    {
    //
    //        //OMEMO
    //#ifndef DISABLE_OMEMO
    //#ifndef TARGET_IS_EXTENSION
    //#if TARGET_OS_IPHONE
    //        dispatch_async(dispatch_get_main_queue(), ^{
    //            if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground)
    //            {
    //#endif
    //#endif
    //                [self.processQueue addOperationWithBlock:^{
    //                    NSString *source= iqNode.from;
    //                    if(iqNode.omemoDevices)
    //                    {
    //
    //                        if(!source || [source isEqualToString:self.fulluser])
    //                        {
    //                            source=self.fulluser;
    //                            NSMutableArray *devices= [iqNode.omemoDevices mutableCopy];
    //                            NSSet *deviceSet = [NSSet setWithArray:iqNode.omemoDevices];
    //
    //                            NSString * deviceString=[NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
    //                            if(![deviceSet containsObject:deviceString])
    //                            {
    //                                [devices addObject:deviceString];
    //                            }
    //
    //                            [self sendOMEMODevices:devices];
    //                        }
    //
    //
    //                        NSArray *existingDevices=[self.monalSignalStore knownDevicesForAddressName:source];
    //                        NSSet *deviceSet = [NSSet setWithArray:existingDevices];
    //                        //only query if the device doesnt exist
    //                        [iqNode.omemoDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    //                            NSString *device  =(NSString *)obj;
    //                            if(![deviceSet containsObject:[NSNumber numberWithInt: device.integerValue]]) {
    //                                [self queryOMEMOBundleFrom:source andDevice:device];
    //                            }
    //                        }];
    //
    //                    }
    //
    //
    //                    if(iqNode.signedPreKeyPublic && self.signalContext )
    //                    {
    //                        if(!source)
    //                        {
    //                            source=self.fulluser;
    //                        }
    //
    //
    //                        uint32_t device =(uint32_t)[iqNode.deviceid intValue];
    //                        if(!iqNode.deviceid) return;
    //
    //                        SignalAddress *address = [[SignalAddress alloc] initWithName:source deviceId:device];
    //                        SignalSessionBuilder *builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self.signalContext];
    //                        NSError *error;
    //
    //                        [iqNode.preKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    //
    //                            NSDictionary *row = (NSDictionary *) obj;
    //                            NSString *keyid = (NSString *)[row objectForKey:@"preKeyId"];
    //
    //                            SignalPreKeyBundle *bundle = [[SignalPreKeyBundle alloc] initWithRegistrationId:0
    //                                                                                                   deviceId:device
    //                                                                                                   preKeyId:[keyid integerValue]
    //                                                                                               preKeyPublic:[EncodingTools dataWithBase64EncodedString:[row objectForKey:@"preKey"]]
    //                                                                                             signedPreKeyId:iqNode.signedPreKeyId.integerValue
    //                                                                                         signedPreKeyPublic:[EncodingTools dataWithBase64EncodedString:iqNode.signedPreKeyPublic]
    //                                                                                                  signature:[EncodingTools dataWithBase64EncodedString:iqNode.signedPreKeySignature]
    //                                                                                                identityKey:[EncodingTools dataWithBase64EncodedString:iqNode.identityKey]
    //                                                                                                      error:nil];
    //
    //                            [builder processPreKeyBundle:bundle error:nil];
    //                        }];
    //
    //                    }
    //                }];
    //#ifndef TARGET_IS_EXTENSION
    //#if TARGET_OS_IPHONE
    //            }
    //        });
    //#endif
    //#endif
    //#endif
    //
    //
    
    //
    
    //
    //
}

#pragma mark - features

-(XMPPIQ *) discoverService:(NSString *) node
{
    XMPPIQ *discoInfo =[[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:node];
    [discoInfo setDiscoInfoNode];
    return discoInfo;
}

-(XMPPIQ *) enableCarbons
{
    XMPPIQ *carbons =[[XMPPIQ alloc] initWithId:@"enableCarbons" andType:kiqSetType];
    MLXMLNode *enable =[[MLXMLNode alloc] initWithElement:@"enable"];
    [enable setXMLNS:@"urn:xmpp:carbons:2"];
    [carbons.children addObject:enable];
    return carbons;
}

-(void) parseFeatures
{
    if([self.connection.serverFeatures containsObject:@"urn:xmpp:carbons:2"])
    {
        if(!self.connection.usingCarbons2){
            if(self.sendIq) self.sendIq([self enableCarbons]);
        }
    }
    
    if([self.connection.serverFeatures containsObject:@"urn:xmpp:ping"])
    {
        self.connection.supportsPing=YES;
    }
    
    [self.connection.serverFeatures.allObjects enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *feature = (NSString *)obj;
        if([feature hasPrefix:@"http://jabber.org/protocol/pubsub"]) {
            self.connection.supportsPubSub=YES;
            *stop=YES;
        }
    }];
}

@end
