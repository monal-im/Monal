//
//  MLIQProcessor.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLIQProcessor.h"
#import "XMPPIQ.h"

static const int ddLogLevel = LOG_LEVEL_DEBUG;

@interface MLIQProcessor()

@property (nonatomic, strong) SignalContext *signalContext;
@property (nonatomic, strong) MLSignalStore *monalSignalStore;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *accountNo;

@end

/**
 Validate and process an iq elements.
 @link https://xmpp.org/rfcs/rfc6120.html#stanzas-semantics-iq
 */
@implementation MLIQProcessor

-(MLIQProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore
{
    self=[super init];
    self.accountNo = accountNo;
    self.jid= jid;
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
        // require 1 child
    }
    else  if([iqNode.type isEqualToString:kiqSetType]) {
             // require 1 child
         }
    else      if([iqNode.type isEqualToString:kiqResultType]) {
        
    }
    else     if([iqNode.type isEqualToString:kiqErrorType]) {
        
    }
    else {
        DDLogError(@"invalid iq type %@", iqNode.type);
    }
    
         if(iqNode.discoInfo) {
                            [self cleanDisco];
                        }

                        if(iqNode.features && iqNode.discoInfo) {
                            if([iqNode.from isEqualToString:self.server] || [iqNode.from isEqualToString:self.domain]) {
                                self.serverFeatures=[iqNode.features copy];
                                [self parseFeatures];

    #ifndef DISABLE_OMEMO
                                [self sendSignalInitialStanzas];
    #endif
                            }

                            if([iqNode.features containsObject:@"urn:xmpp:http:upload"])
                            {
                                self.supportsHTTPUpload=YES;
                                self.uploadServer = iqNode.from;
                            }

                            if([iqNode.features containsObject:@"http://jabber.org/protocol/muc"])
                            {
                                self.conferenceServer=iqNode.from;
                            }

                            if([iqNode.features containsObject:@"urn:xmpp:push:0"])
                            {
                                self.supportsPush=YES;
                                [self enablePush];
                            }

                            if([iqNode.features containsObject:@"urn:xmpp:mam:2"])
                            {
                                self.supportsMam2=YES;
                                DDLogInfo(@" supports mam:2");
                            }
                        }

                        if(iqNode.legacyAuth)
                        {
                            XMPPIQ* auth =[[XMPPIQ alloc] initWithId:@"auth2" andType:kiqSetType];
                            [auth setAuthWithUserName:self.username resource:self.resource andPassword:self.password];
                            [self send:auth];
                        }

                        if(iqNode.shouldSetBind)
                        {
                            self->_jid=iqNode.jid;
                            DDLogVerbose(@"Set jid %@", self->_jid);

                            if(self.supportsSM3)
                            {
                                MLXMLNode *enableNode =[[MLXMLNode alloc] initWithElement:@"enable"];
                                NSDictionary *dic=@{@"xmlns":@"urn:xmpp:sm:3",@"resume":@"true" };
                                enableNode.attributes =[dic mutableCopy];
                                [self send:enableNode];
                            }
                            else
                            {
                                //init session and query disco, roster etc.
                                [self initSession];
                            }
                        }

                        if(iqNode.vCard && iqNode.user)
                        {
                            NSString* fullname=iqNode.fullName;
                            if(!fullname) fullname= iqNode.user;

                            if([fullname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length>0 ) {
                                [[DataLayer sharedInstance] setFullName:fullname forContact:iqNode.user andAccount:self->_accountNo];

                                if(iqNode.photoBinValue)
                                {
                                    [[MLImageManager sharedInstance] setIconForContact:iqNode.user andAccount:self->_accountNo WithData:[iqNode.photoBinValue copy]];

                                }
                                if(iqNode.user) {
                                    if(!fullname) fullname=iqNode.user;

                                    NSDictionary* userDic=@{kusernameKey: iqNode.user,
                                                            kfullNameKey: fullname,
                                                            kaccountNoKey:self->_accountNo
                                                            };
                                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:userDic];
                                }
                            }

                        }

                        if(iqNode.ping)
                        {
                            XMPPIQ* pong =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                            [pong setiqTo:self->_domain];
                            [self send:pong];
                        }

                        if([iqNode.idval isEqualToString:self.pingID])
                        {
                            //response to my ping
                            self.pingID=nil;
                        }

                        if(iqNode.httpUpload)
                        {
                            NSDictionary *matchingRow;
                            //look up id val in upload queue array
                            for(NSDictionary * row in self.httpUploadQueue)
                            {
                                if([[row objectForKey:kId] isEqualToString:iqNode.idval])
                                {
                                    matchingRow= row;
                                    break;
                                }
                            }

                            if(matchingRow) {

                                //upload to put
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [MLHTTPRequest sendWithVerb:kPut path:iqNode.putURL
                                                        headers:@{kContentType:[matchingRow objectForKey:kContentType]}
                                                  withArguments:nil data:[matchingRow objectForKey:kData] andCompletionHandler:^(NSError *error, id result) {
                                        void (^completion) (NSString *url,  NSError *error)  = [matchingRow objectForKey:kCompletion];
                                        if(!error)
                                        {
                                            //send get to contact
                                            if(completion)
                                            {
                                                completion(iqNode.getURL, nil);
                                            }
                                        } else  {
                                            if(completion)
                                            {
                                                completion(nil, error);
                                            }
                                        }

                                    }];
                                });

                            }
                        }


                        if (iqNode.version)
                        {
                            XMPPIQ* versioniq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                            [versioniq setiqTo:iqNode.from];
                            [versioniq setVersion];
                            [self send:versioniq];
                        }

                        if (iqNode.last)
                        {
                            XMPPIQ* lastiq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                            [lastiq setiqTo:iqNode.from];
                            [lastiq setLast];
                            [self send:lastiq];
                        }

                        if (iqNode.time)
                        {
                            XMPPIQ* timeiq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                            [timeiq setiqTo:iqNode.from];
                            //[lastiq setLast];
                            [self send:timeiq];
                        }


                        if([iqNode.from isEqualToString:self->_conferenceServer] && iqNode.discoItems)
                        {
                            self->_roomList=iqNode.items;
                            [[NSNotificationCenter defaultCenter]
                             postNotificationName: kMLHasRoomsNotice object: self];
                        }

                        BOOL success= YES;
                        if([iqNode.type isEqualToString:kiqErrorType]) success=NO;
                        if(self.registrationState==kStateSubmittingForm && self.regFormSubmitCompletion)
                        {
                            self.registrationState=kStateRegistered;
                            self.regFormSubmitCompletion(success, iqNode.errorMessage);
                            self.regFormSubmitCompletion=nil;
                        }

                        xmppCompletion completion = [self.xmppCompletionHandlers objectForKey:iqNode.idval];
                        if(completion)  {
                            [self.xmppCompletionHandlers removeObjectForKey:iqNode.idval]; // remove first to prevent an infinite loop
                            completion(success, iqNode.errorMessage);
                        }


                        if(self.registration && [iqNode.queryXMLNS isEqualToString:kRegisterNameSpace])
                        {
                            if(self.regFormCompletion) {
                                self.regFormCompletion(iqNode.captchaData, iqNode.hiddenFormFields);
                                self.regFormCompletion=nil;
                            }
                        }
}

-(void) processGetIq:(ParseIq *) iqNode {
    if((iqNode.discoInfo))
    {
        XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
        if(iqNode.resource) {
            [discoInfo setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user, iqNode.resource]];
        } else  {
            [discoInfo setiqTo:iqNode.user];
        }
        [discoInfo setDiscoInfoWithFeaturesAndNode:iqNode.queryNode];
        [self send:discoInfo];
        
    }
}

-(void) processSetIq:(ParseIq *) iqNode {
    if ([iqNode.type isEqualToString:kiqSetType]) {
                              if(iqNode.jingleSession) {

                                  //accpetance of our call
                                  if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-accept"] &&
                                     [[iqNode.jingleSession objectForKey:@"sid"] isEqualToString:self.jingle.thesid])
                                  {

                                      NSDictionary* transport1;
                                      NSDictionary* transport2;
                                      for(NSDictionary* candidate in iqNode.jingleTransportCandidates) {
                                          if([[candidate objectForKey:@"component"] isEqualToString:@"1"]) {
                                              transport1=candidate;
                                          }
                                          if([[candidate objectForKey:@"component"] isEqualToString:@"2"]) {
                                              transport2=candidate;
                                          }
                                      }

                                      NSDictionary* pcmaPayload;
                                      for(NSDictionary* payload in iqNode.jinglePayloadTypes) {
                                          if([[payload objectForKey:@"name"] isEqualToString:@"PCMA"]) {
                                              pcmaPayload=payload;
                                              break;
                                          }
                                      }

                                      if (pcmaPayload && transport1) {
                                          self.jingle.recipientIP=[transport1 objectForKey:@"ip"];
                                          self.jingle.destinationPort= [transport1 objectForKey:@"port"];

                                          XMPPIQ* node = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                                          [node setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user,iqNode.resource]];
                                          [self send:node];

                                          [self.jingle rtpConnect];
                                      }
                                      return;
                                  }

                                  if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-terminate"] &&  [[iqNode.jingleSession objectForKey:@"sid"] isEqualToString:self.jingle.thesid]) {
                                      XMPPIQ* node = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                                      [node setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user,iqNode.resource]];
                                      [self send:node];
                                      [self.jingle rtpDisconnect];
                                  }

                                  if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-initiate"]) {
                                      NSDictionary* pcmaPayload;
                                      for(NSDictionary* payload in iqNode.jinglePayloadTypes) {
                                          if([[payload objectForKey:@"name"] isEqualToString:@"PCMA"]) {
                                              pcmaPayload=payload;
                                              break;
                                          }
                                      }

                                      NSDictionary* transport1;
                                      NSDictionary* transport2;
                                      for(NSDictionary* candidate in iqNode.jingleTransportCandidates) {
                                          if([[candidate objectForKey:@"component"] isEqualToString:@"1"]) {
                                              transport1=candidate;
                                          }
                                          if([[candidate objectForKey:@"component"] isEqualToString:@"2"]) {
                                              transport2=candidate;
                                          }
                                      }

                                      if (pcmaPayload && transport1) {
                                          self.jingle = [[jingleCall alloc] init];
                                          self.jingle.initiator= [iqNode.jingleSession objectForKey:@"initiator"];
                                          self.jingle.responder= [iqNode.jingleSession objectForKey:@"responder"];
                                          if(!self.jingle.responder)
                                          {
                                              self.jingle.responder = [NSString stringWithFormat:@"%@/%@", iqNode.to, self.resource];
                                          }

                                          self.jingle.thesid= [iqNode.jingleSession objectForKey:@"sid"];
                                          self.jingle.destinationPort= [transport1 objectForKey:@"port"];
                                          self.jingle.idval=iqNode.idval;
                                          if(transport2) {
                                              self.jingle.destinationPort2= [transport2 objectForKey:@"port"];
                                          }
                                          else {
                                              self.jingle.destinationPort2=[transport1 objectForKey:@"port"]; // if nothing is provided just reuse..
                                          }
                                          self.jingle.recipientIP=[transport1 objectForKey:@"ip"];


                                          if(iqNode.user && iqNode.resource && self.fulluser) {

                                              NSDictionary *dic= @{@"from":iqNode.from,
                                                                   @"user":iqNode.user,
                                                                   @"resource":iqNode.resource,
                                                                   @"id": iqNode.idval,
                                                                   kAccountID:self->_accountNo,
                                                                   kAccountName: self.fulluser
                                                                   };

                                              [[NSNotificationCenter defaultCenter]
                                               postNotificationName: kMonalCallRequestNotice object: dic];

                                          }
                                      }
                                      else {
                                          //does not support the same formats
                                      }

                                  }
                              }
                          }
    
}

-(void) processResultIq:(ParseIq *) iqNode {
 if ([iqNode.type isEqualToString:kiqResultType])
                    {
                        if(iqNode.mam2Last && !iqNode.mam2fin)
                        {
                            //RSM seems broken on servers. Tell UI there is more to fetch
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMLMAMMore object:nil];

                        }

                        //OMEMO
#ifndef DISABLE_OMEMO
                        #ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground)
                            {
#endif
#endif
                                [self.processQueue addOperationWithBlock:^{
                                    NSString *source= iqNode.from;
                                    if(iqNode.omemoDevices)
                                    {

                                        if(!source || [source isEqualToString:self.fulluser])
                                        {
                                            source=self.fulluser;
                                            NSMutableArray *devices= [iqNode.omemoDevices mutableCopy];
                                            NSSet *deviceSet = [NSSet setWithArray:iqNode.omemoDevices];

                                            NSString * deviceString=[NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
                                            if(![deviceSet containsObject:deviceString])
                                            {
                                                [devices addObject:deviceString];
                                            }

                                            [self sendOMEMODevices:devices];
                                        }


                                        NSArray *existingDevices=[self.monalSignalStore knownDevicesForAddressName:source];
                                        NSSet *deviceSet = [NSSet setWithArray:existingDevices];
                                        //only query if the device doesnt exist
                                        [iqNode.omemoDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                                            NSString *device  =(NSString *)obj;
                                            if(![deviceSet containsObject:[NSNumber numberWithInt: device.integerValue]]) {
                                                [self queryOMEMOBundleFrom:source andDevice:device];
                                            }
                                        }];

                                    }


                                    if(iqNode.signedPreKeyPublic && self.signalContext )
                                    {
                                        if(!source)
                                        {
                                            source=self.fulluser;
                                        }


                                        uint32_t device =(uint32_t)[iqNode.deviceid intValue];
                                        if(!iqNode.deviceid) return;

                                        SignalAddress *address = [[SignalAddress alloc] initWithName:source deviceId:device];
                                        SignalSessionBuilder *builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self.signalContext];
                                        NSError *error;

                                        [iqNode.preKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {

                                            NSDictionary *row = (NSDictionary *) obj;
                                            NSString *keyid = (NSString *)[row objectForKey:@"preKeyId"];

                                            SignalPreKeyBundle *bundle = [[SignalPreKeyBundle alloc] initWithRegistrationId:0
                                                                                                                    deviceId:device
                                                                                                                    preKeyId:[keyid integerValue]
                                                                                                                preKeyPublic:[EncodingTools dataWithBase64EncodedString:[row objectForKey:@"preKey"]]
                                                                                                              signedPreKeyId:iqNode.signedPreKeyId.integerValue
                                                                                                          signedPreKeyPublic:[EncodingTools dataWithBase64EncodedString:iqNode.signedPreKeyPublic]
                                                                                                                   signature:[EncodingTools dataWithBase64EncodedString:iqNode.signedPreKeySignature]
                                                                                                                 identityKey:[EncodingTools dataWithBase64EncodedString:iqNode.identityKey]
                                                                                                                       error:nil];

                                            [builder processPreKeyBundle:bundle error:nil];
                                        }];

                                    }
                                }];
                                #ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
                            }
                        });
#endif
#endif
#endif


                        if([iqNode.idval isEqualToString:@"enableCarbons"])
                        {
                            self.usingCarbons2=YES;
                            [self cleanEnableCarbons];
                        }

                        if(iqNode.mam2default)
                        {
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMLMAMPref object:@{@"mamPref":iqNode.mam2default}];
                        }


                        if(iqNode.discoItems==YES)
                        {
                            if(([iqNode.from isEqualToString:self.server] || [iqNode.from isEqualToString:self.domain]) && !self->_discoveredServices)
                            {
                                for (NSDictionary* item in iqNode.items)
                                {
                                    if(!self->_discoveredServices) self->_discoveredServices=[[NSMutableArray alloc] init];
                                    [self->_discoveredServices addObject:item];

                                    if((![[item objectForKey:@"jid"] isEqualToString:self.server]  &&  ![[item objectForKey:@"jid"] isEqualToString:self.domain])) {
                                        [self discoverService:[item objectForKey:@"jid"]];
                                    }
                                }
                                [self discoverService:self.fulluser];   //discover push support
                            }
                            else
                            {

                            }
                        }
                        else if (iqNode.roster==YES)
                        {
                            self.rosterList=iqNode.items;

                            for(NSDictionary* contact in self.rosterList)
                            {

                                if([[contact objectForKey:@"subscription"] isEqualToString:@"both"])
                                {
                                    if([contact objectForKey:@"jid"]) {
                                        [[DataLayer sharedInstance] addContact:[contact objectForKey:@"jid"]
                                                                    forAccount:self->_accountNo
                                                                      fullname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                                                      nickname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""
                                                                withCompletion:^(BOOL success) {

                                                                    if(!success && ((NSString *)[contact objectForKey:@"name"]).length>0)
                                                                    {
                                                                        [[DataLayer sharedInstance] setFullName:[contact objectForKey:@"name"] forContact:[contact objectForKey:@"jid"] andAccount:self->_accountNo ] ;
                                                                    }
                                                                }];
                                    }
                                }

                            }

                            // iterate roster and get cards
                            [self getVcards];
                        }

                        //confirmation of set call after we accepted
                        if([iqNode.idval isEqualToString:self.jingle.idval])
                        {
                            NSString* from= iqNode.user;

                            NSString* fullName;
                            fullName=[[DataLayer sharedInstance] fullName:from forAccount:self->_accountNo];
                            if(!fullName) fullName=from;

                            NSDictionary* userDic=@{@"buddy_name":from,
                                                    @"full_name":fullName,
                                                    kAccountID:self->_accountNo
                                                    };

                            [[NSNotificationCenter defaultCenter]
                             postNotificationName: kMonalCallStartedNotice object: userDic];


                            [self.jingle rtpConnect];
                            return;
                        }

                    }

}

-(void) processErrorIq:(ParseIq *) iqNode {
    
}

@end
