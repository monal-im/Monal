//
//  XMPPIQ.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPIQ.h"
#import "XMPPDataForm.h"
#import "HelperTools.h"
#import "SignalPreKey.h"

NSString* const kiqGetType = @"get";
NSString* const kiqSetType = @"set";
NSString* const kiqResultType = @"result";
NSString* const kiqErrorType = @"error";

@implementation XMPPIQ

-(id) initInternalWithId:(NSString*) iqid andType:(NSString*) iqType
{
    self = [super initWithElement:@"iq"];
    [self setXMLNS:@"jabber:client"];
    self.id = iqid;
    if(iqType)
        self.attributes[@"type"] = iqType;
    return self;
}

-(id) initWithType:(NSString*) iqType
{
    return [self initInternalWithId:[[NSUUID UUID] UUIDString] andType:iqType];
}

-(id) initWithType:(NSString*) iqType to:(NSString*) to
{
    self = [self initWithType:iqType];
    if(to)
        [self setiqTo:to];
    return self;
}

-(id) initAsResponseTo:(XMPPIQ*) iq
{
    self = [self initInternalWithId:[iq findFirst:@"/@id"] andType:kiqResultType];
    if(iq.from)
        [self setiqTo:iq.from];
    return self;
}

-(id) initAsErrorTo:(XMPPIQ*) iq
{
    self = [self initInternalWithId:[iq findFirst:@"/@id"] andType:kiqErrorType];
    if(iq.from)
        [self setiqTo:iq.from];
    return self;
}

#pragma mark iq set

-(void) setRegisterOnAppserverWithToken:(NSString*) token
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"command" andNamespace:@"http://jabber.org/protocol/commands" withAttributes:@{
        @"node": @"v1-register-push",
        @"action": @"execute"
    } andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" formType:@"https://github.com/tmolitor-stud-tu/mod_push_appserver/#v1-register-push" andDictionary:@{
            @"type": @"apns",
            @"node": [[[UIDevice currentDevice] identifierForVendor] UUIDString],
            @"token": token
        }]
    ] andData:nil]];
}

-(void) setUnregisterOnAppserver
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"command" andNamespace:@"http://jabber.org/protocol/commands" withAttributes:@{
        @"node": @"v1-unregister-push",
        @"action": @"execute"
    } andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" formType:@"https://github.com/tmolitor-stud-tu/mod_push_appserver/#v1-unregister-push" andDictionary:@{
            @"type": @"apns",
            @"node": [[[UIDevice currentDevice] identifierForVendor] UUIDString],
        }]
    ] andData:nil]];
}

// direct push registration at xmpp server without registration at appserver
-(void) setPushEnableWithNode:(NSString*) node onAppserver:(NSString*) jid
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"enable" andNamespace:@"urn:xmpp:push:0" withAttributes:@{
        @"jid": jid,
        @"node": node
    } andChildren:@[] andData:nil]];
}

// legacy push registration at appserver
-(void) setPushEnableWithNode:(NSString*) node andSecret:(NSString*) secret onAppserver:(NSString*) jid
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"enable" andNamespace:@"urn:xmpp:push:0" withAttributes:@{
        @"jid": jid,
        @"node": node
    } andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/pubsub#publish-options" andDictionary:@{
            @"secret": secret
        }]
    ] andData:nil]];
}

-(void) setPushDisable:(NSString*) node
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"disable" andNamespace:@"urn:xmpp:push:0" withAttributes:@{
        @"jid": [HelperTools pushServer],
        @"node": node
    } andChildren:@[] andData:nil]];
}

-(void) setBindWithResource:(NSString*) resource
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"bind" andNamespace:@"urn:ietf:params:xml:ns:xmpp-bind" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"resource" andData:resource]
    ] andData:nil]];
}

-(void) setMucListQueryFor:(NSString*) listType
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/muc#admin" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"affiliation": listType} andChildren:@[] andData:nil]
    ] andData:nil]];
}

-(void) setDiscoInfoNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/disco#info"];
    [self addChildNode:queryNode];
}

-(void) setDiscoItemNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/disco#items"];
    [self addChildNode:queryNode];
}

-(void) setDiscoInfoWithFeatures:(NSSet*) features identity:(MLXMLNode*) identity andNode:(NSString*) node
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/disco#info"];
    if(node)
        [queryNode.attributes setObject:node forKey:@"node"];
    
    for(NSString* feature in features)
    {
        MLXMLNode* featureNode = [[MLXMLNode alloc] initWithElement:@"feature"];
        featureNode.attributes[@"var"] = feature;
        [queryNode addChildNode:featureNode];
    }
    
    [queryNode addChildNode:identity];
    
    [self addChildNode:queryNode];
}

-(void) setiqTo:(NSString*) to
{
    if(to)
        self.to = to;
}

-(void) setPing
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"ping" andNamespace:@"urn:xmpp:ping"]];
}

-(void) setPurgeOfflineStorage
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"offline" andNamespace:@"http://jabber.org/protocol/offline" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"purge"]
    ] andData:nil]];
}

#pragma mark - MAM

-(void) mamArchivePref
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"prefs" andNamespace:@"urn:xmpp:mam:2"]];
}

-(void) updateMamArchivePrefDefault:(NSString *) pref
{
    /**
     pref is aways, never or roster
     */
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"prefs" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{@"default": pref} andChildren:@[] andData:nil]];
}

-(void) setMAMQueryLatestMessagesForJid:(NSString* _Nullable) jid before:(NSString* _Nullable) uid
{
    //set iq id to mam query id
    self.id = [NSString stringWithFormat:@"MLhistory:%@", [[NSUUID UUID] UUIDString]];
    XMPPDataForm* form = [[XMPPDataForm alloc] initWithType:@"submit" andFormType:@"urn:xmpp:mam:2"];
    if(jid)
        form[@"with"] = jid;
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": self.id
    } andChildren:@[
        form,
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" andData:@"50"],
            [[MLXMLNode alloc] initWithElement:@"before" andData:uid]
        ] andData:nil]
    ] andData:nil];
    [self addChildNode:queryNode];
}

-(void) setMAMQueryForLatestId
{
    //set iq id to mam query id
    self.id = [NSString stringWithFormat:@"MLignore:%@", [[NSUUID UUID] UUIDString]];
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": self.id
    } andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" formType:@"urn:xmpp:mam:2" andDictionary:@{
            @"end": [HelperTools generateDateTimeString:[NSDate date]]
        }],
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" andData:@"1"],
            [[MLXMLNode alloc] initWithElement:@"before"]
        ] andData:nil]
    ] andData:nil];
    [self addChildNode:queryNode];
}

-(void) setMAMQueryAfter:(NSString*) uid
{
    //set iq id to mam query id
    self.id = [NSString stringWithFormat:@"MLcatchup:%@", [[NSUUID UUID] UUIDString]];
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": self.id
    } andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" andFormType:@"urn:xmpp:mam:2"],
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" andData:@"50"],
            [[MLXMLNode alloc] initWithElement:@"after" andData:uid]
        ] andData:nil]
    ] andData:nil];
    [self addChildNode:queryNode];
}

-(void) setCompleteMAMQuery
{
    //set iq id to mam query id
    self.id = [NSString stringWithFormat:@"MLcatchup:%@", [[NSUUID UUID] UUIDString]];
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": self.id
    } andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" andFormType:@"urn:xmpp:mam:2"],
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" andData:@"50"]
        ] andData:nil]
    ] andData:nil];
    [self addChildNode:queryNode];
}

-(void) setRemoveFromRoster:(NSString*) jid
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:roster" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{
            @"jid": jid,
            @"subscription": @"remove"
        } andChildren:@[] andData:nil]
    ] andData:nil]];
}

-(void) setUpdateRosterItem:(NSString* _Nonnull) jid withName:(NSString* _Nonnull) name
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:roster" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{
            @"jid": jid,
            @"name": name,
        } andChildren:@[] andData:nil]
    ] andData:nil]];
}

-(void) setRosterRequest:(NSString*) version
{
    NSDictionary* attrs = @{};
    if(version && ![version isEqual:@""])
        attrs = @{@"ver": version};
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:roster" withAttributes:attrs andChildren:@[] andData:nil]];
}

-(void) setVersion
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:version" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"name" andData:@"Monal"],
#if TARGET_OS_MACCATALYST
        [[MLXMLNode alloc] initWithElement:@"os" andData:@"macOS"],
#else
        [[MLXMLNode alloc] initWithElement:@"os" andData:@"iOS"],
#endif
        [[MLXMLNode alloc] initWithElement:@"version" andData:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]],
    ] andData:nil]];
}

-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid
{
    MLXMLNode* blockNode = [[MLXMLNode alloc] initWithElement:(blocked ? @"block" : @"unblock") andNamespace:@"urn:xmpp:blocking"];
    
    MLXMLNode* itemNode = [[MLXMLNode alloc] initWithElement:@"item"];
    [itemNode.attributes setObject:blockedJid forKey:kJid];
    [blockNode addChildNode:itemNode];
    
    [self addChildNode:blockNode];
}

-(void) requestBlockList
{
    MLXMLNode* blockNode = [[MLXMLNode alloc] initWithElement:@"blocklist" andNamespace:@"urn:xmpp:blocking"];
    [self addChildNode:blockNode];
}

-(void) httpUploadforFile:(NSString *) file ofSize:(NSNumber *) filesize andContentType:(NSString *) contentType
{
    MLXMLNode* requestNode = [[MLXMLNode alloc] initWithElement:@"request" andNamespace:@"urn:xmpp:http:upload:0"];
    requestNode.attributes[@"filename"] = file;
    requestNode.attributes[@"size"] = [NSString stringWithFormat:@"%@", filesize];
    requestNode.attributes[@"content-type"] = contentType;
    [self addChildNode:requestNode];
}


#pragma mark iq get

-(void) getEntitySoftWareVersionTo:(NSString*) to
{
    [self setiqTo:to];
    
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:version"];
    
    [self addChildNode:queryNode];
}

#pragma mark MUC

-(void) setInstantRoom
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/muc#owner" withAttributes:@{} andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" andFormType:@"http://jabber.org/protocol/muc#roomconfig"]
    ] andData:nil]];
}

-(void) setVcardAvatarWithData:(NSData*) imageData andType:(NSString*) imageType
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"vCard" andNamespace:@"vcard-temp" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"PHOTO" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"PHOTO" andData:imageType],
            [[MLXMLNode alloc] initWithElement:@"BINVAL" andData:[HelperTools encodeBase64WithData:imageData]],
        ] andData:nil]
    ] andData:nil]];
}

-(void) setVcardQuery
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"vCard" andNamespace:@"vcard-temp"]];
}

#pragma mark - Account Management

-(void) submitRegToken:(NSString*) token
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"preauth" andNamespace:@"urn:xmpp:pars:0" withAttributes:@{
        @"token": token
    } andChildren:@[] andData:nil]];
}

-(void) getRegistrationFields
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:kRegisterNameSpace]];
}

/*
 This is really hardcoded for yax.im might work for others
 */
-(void) registerUser:(NSString*) user withPassword:(NSString*) newPass captcha:(NSString*) captcha andHiddenFields:(NSDictionary*) hiddenFields
{
    NSMutableDictionary* fields = [NSMutableDictionary dictionaryWithDictionary:@{
        @"username": user,
        @"password": newPass,
    }];
    if(captcha)
        fields[@"ocr"] = captcha;
    [fields addEntriesFromDictionary:hiddenFields];
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:kRegisterNameSpace withAttributes:@{} andChildren:@[
        [[XMPPDataForm alloc] initWithType:@"submit" formType:kRegisterNameSpace andDictionary:fields]
    ] andData:nil]];
}

-(void) changePasswordForUser:(NSString*) user newPassword:(NSString*) newPass
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:kRegisterNameSpace withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"username" andData:user],
        [[MLXMLNode alloc] initWithElement:@"password" andData:newPass],
    ] andData:nil]];
}

@end
