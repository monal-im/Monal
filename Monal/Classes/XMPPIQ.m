//
//  XMPPIQ.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPIQ.h"
#import "EncodingTools.h"
#import "SignalPreKey.h"

#if TARGET_OS_IPHONE
#import "MLPush.h"
#endif

NSString *const kiqGetType = @"get";
NSString *const kiqSetType = @"set";
NSString *const kiqResultType = @"result";
NSString *const kiqErrorType = @"error";

@implementation XMPPIQ


-(id) initWithId:(NSString*) sessionid andType:(NSString*) iqType
{
    self=[super init];
    self.element=@"iq";
    if (sessionid && iqType) {
        [self.attributes setObject:sessionid forKey:@"id"];
        [self.attributes setObject:iqType forKey:@"type"];
    }
    return self;
}

-(id) initWithType:(NSString*) iqType
{
    return [self initWithId:[[NSUUID UUID] UUIDString] andType:iqType];
}

+ (NSArray *) features {
    static NSArray* featuresArray;
     static dispatch_once_t onceToken;
     dispatch_once(&onceToken, ^{
         //This list must be in aphabetical order
    featuresArray=@[@"eu.siacs.conversations.axolotl.devicelist+notify",
                    @"http://jabber.org/protocol/caps",
                        @"http://jabber.org/protocol/disco#info",
                        @"http://jabber.org/protocol/disco#items",
                        @"http://jabber.org/protocol/muc",
                        @"urn:xmpp:jingle:1",
                        @"urn:xmpp:jingle:apps:rtp:1",
                        @"urn:xmpp:jingle:apps:rtp:audio",
                        @"urn:xmpp:jingle:transports:raw-udp:0",
                        @"urn:xmpp:jingle:transports:raw-udp:1",
                        @"urn:xmpp:receipts"
                    
                        ];
     });
    
    return featuresArray;
}

+(NSString *) featuresString
{
    NSMutableString *toreturn = [[NSMutableString alloc] init];
    
    for(NSString* feature in [XMPPIQ features])
    {
        [toreturn appendString:feature];
        [toreturn appendString:@"<"];
    }
    return toreturn;
}


#pragma mark iq set
 #if TARGET_OS_IPHONE
-(void) setPushEnableWithNode:(NSString *)node andSecret:(NSString *)secret
{
    MLXMLNode* enableNode =[[MLXMLNode alloc] init];
    enableNode.element=@"enable";
    [enableNode.attributes setObject:@"urn:xmpp:push:0" forKey:kXMLNS];
    [enableNode.attributes setObject:[MLPush pushServer] forKey:@"jid"];
    [enableNode.attributes setObject:node forKey:@"node"];
    [self.children addObject:enableNode];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xNode.attributes setObject:@"submit" forKey:@"type"];
    [enableNode.children addObject:xNode];
    
    MLXMLNode* formTypeFieldNode =[[MLXMLNode alloc] init];
    formTypeFieldNode.element=@"field";
    [formTypeFieldNode.attributes setObject:@"FORM_TYPE" forKey:@"var"];
    MLXMLNode* formTypeValueNode =[[MLXMLNode alloc] init];
    formTypeValueNode.element=@"value";
    formTypeValueNode.data=@"http://jabber.org/protocol/pubsub#publish-options";
    [formTypeFieldNode.children addObject:formTypeValueNode];
    [xNode.children addObject:formTypeFieldNode];
    
    MLXMLNode* secretFieldNode =[[MLXMLNode alloc] init];
    secretFieldNode.element=@"field";
    [secretFieldNode.attributes setObject:@"secret" forKey:@"var"];
    MLXMLNode* secretValueNode =[[MLXMLNode alloc] init];
    secretValueNode.element=@"value";
    secretValueNode.data=secret;
    [secretFieldNode.children addObject:secretValueNode];
    [xNode.children addObject:secretFieldNode];
}
#endif

-(void) setPushDisableWithNode:(NSString *)node
{
    MLXMLNode* disableNode =[[MLXMLNode alloc] init];
    disableNode.element=@"disable";
    [disableNode.attributes setObject:@"urn:xmpp:push:0" forKey:kXMLNS];
    [disableNode.attributes setObject:[MLPush pushServer] forKey:@"jid"];
    [disableNode.attributes setObject:@"192.168.2.3" forKey:@"jid"];
    [disableNode.attributes setObject:node forKey:@"node"];
    [self.children addObject:disableNode];
}

-(void) setAuthWithUserName:(NSString *)username resource:(NSString *) resource andPassword:(NSString *) password
{
    [self.attributes setObject:@"auth1" forKey:@"id"];
    [self.attributes setObject:kiqSetType forKey:@"type"];
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"jabber:iq:auth"];
    
    MLXMLNode* userNode =[[MLXMLNode alloc] init];
    userNode.element=@"username";
    userNode.data =username;
    
    MLXMLNode* resourceNode =[[MLXMLNode alloc] init];
    resourceNode.element=@"resource";
    resourceNode.data =resource;
    
    MLXMLNode* passNode =[[MLXMLNode alloc] init];
    passNode.element=@"password";
    passNode.data =password;
    
    [queryNode.children addObject:userNode];
    [queryNode.children addObject:resourceNode];
    [queryNode.children addObject:passNode];
    [self.children addObject:queryNode];
}

-(void) setBindWithResource:(NSString*) resource
{

    MLXMLNode* bindNode =[[MLXMLNode alloc] init];
    bindNode.element=@"bind";
    [bindNode.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-bind" forKey:kXMLNS];
    
    MLXMLNode* resourceNode =[[MLXMLNode alloc] init];
    resourceNode.element=@"resource";
    resourceNode.data=resource;
    [bindNode.children addObject:resourceNode];
    
    [self.children addObject:bindNode];
    
    
}

-(void) setDiscoInfoNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#info"];
    [self.children addObject:queryNode];
}

-(void) setDiscoItemNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#items"];
    [self.children addObject:queryNode];
}

-(void) setDiscoInfoWithFeaturesAndNode:(NSString*) node
{
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#info"];
    if(node){
        [queryNode. attributes setObject:node forKey:@"node"];
    }
    

    for(NSString* feature in [XMPPIQ features])
    {
    
    MLXMLNode* featureNode =[[MLXMLNode alloc] init];
    featureNode.element=@"feature";
        [featureNode.attributes setObject:feature forKey:@"var"];
    [queryNode.children addObject:featureNode];
    
   }
    
    MLXMLNode* identityNode =[[MLXMLNode alloc] init];
    identityNode.element=@"identity";
    [identityNode.attributes setObject:@"client" forKey:@"category"];
    [identityNode.attributes setObject:@"phone" forKey:@"type"];
    [identityNode.attributes setObject:[NSString stringWithFormat:@"Monal %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]] forKey:@"name"];
    [queryNode.children addObject:identityNode];
       
    [self.children addObject:queryNode];
    
}

-(void) setiqTo:(NSString*) to
{
    if(to)
    [self.attributes setObject:to forKey:@"to"];
}

-(void) setPing
{
    MLXMLNode* pingNode =[[MLXMLNode alloc] init];
    pingNode.element=@"ping";
    [pingNode.attributes setObject:@"urn:xmpp:ping" forKey:kXMLNS];
    [self.children addObject:pingNode];

}

#pragma mark - MAM

-(void) mamArchivePref
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"prefs";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    [self.children addObject:queryNode];
}

-(void) updateMamArchivePrefDefault:(NSString *) pref
{
    /**
     pref is aways, never or roster
     */
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"prefs";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    [queryNode.attributes setObject:pref forKey:@"default"];
    [self.children addObject:queryNode];
}

/**
 Get last 50 messages
 */
-(void) setMAMQueryLatestMessagesForJid:(NSString *)jid
{
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    
    
    MLXMLNode* xnode =[[MLXMLNode alloc] init];
    xnode.element=@"x";
    [xnode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xnode.attributes setObject:@"submit" forKey:@"type"];
    
    MLXMLNode* field1 =[[MLXMLNode alloc] init];
    field1.element=@"field";
    [field1.attributes setObject:@"FORM_TYPE" forKey:@"var"];
    [field1.attributes setObject:@"hidden" forKey:@"type"];
    
    MLXMLNode* value =[[MLXMLNode alloc] init];
    value.element=@"value";
    value.data=@"urn:xmpp:mam:2";
    [field1.children addObject:value];
    
    [xnode.children addObject:field1];
    

    
    //if we are fetching "all" limit with RSM to 50 for now
    MLXMLNode* set =[[MLXMLNode alloc] init];
    set.element=@"set";
    [set.attributes setObject:@"http://jabber.org/protocol/rsm" forKey:kXMLNS];
    
    MLXMLNode* max =[[MLXMLNode alloc] init];
    max.element=@"max";
    max.data=@"50";
    [set.children addObject:max];
    
    MLXMLNode* before =[[MLXMLNode alloc] init];
    before.element=@"before";
    [set.children addObject:before];
    
    [queryNode.children addObject:set];

    if(jid) {
        MLXMLNode* field3 =[[MLXMLNode alloc] init];
        field3.element=@"field";
        [field3.attributes setObject:@"with" forKey:@"var"];
        
        MLXMLNode* value3 =[[MLXMLNode alloc] init];
        value3.element=@"value";
        value3.data=jid;
        [field3.children addObject:value3];
        
        [xnode.children addObject:field3];
    }
    
    
    [queryNode.children addObject:xnode];
    
    [self.children addObject:queryNode];
    
}

/**
 You can send just start or just jid. Setting  endDate alone doesnt make sense.
 If querying all good idea to set a max
 */
-(void) setMAMQueryFromStart:(NSDate *) startDate toDate:(NSDate *) endDate withMax:(NSString *) maxResults  andJid:(NSString *)jid
{
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    
    
    MLXMLNode* xnode =[[MLXMLNode alloc] init];
    xnode.element=@"x";
    [xnode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xnode.attributes setObject:@"submit" forKey:@"type"];
    
    MLXMLNode* field1 =[[MLXMLNode alloc] init];
    field1.element=@"field";
    [field1.attributes setObject:@"FORM_TYPE" forKey:@"var"];
    [field1.attributes setObject:@"hidden" forKey:@"type"];
    
    MLXMLNode* value =[[MLXMLNode alloc] init];
    value.element=@"value";
    value.data=@"urn:xmpp:mam:2";
    [field1.children addObject:value];
    
    [xnode.children addObject:field1];
    
    NSDateFormatter *rfc3339DateFormatter;
    if(startDate || endDate) {
        rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
    
    if(startDate){
        MLXMLNode* field2 =[[MLXMLNode alloc] init];
        field2.element=@"field";
        [field2.attributes setObject:@"start" forKey:@"var"];
        
        MLXMLNode* value2 =[[MLXMLNode alloc] init];
        value2.element=@"value";
        if(startDate) {
            value2.data=[rfc3339DateFormatter stringFromDate:startDate];
        }
        else  {
            value2.data=[rfc3339DateFormatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:0]];
        }
        
        [field2.children addObject:value2];
        [xnode.children addObject:field2];
    }
    
    if(maxResults)
    {
        MLXMLNode* set =[[MLXMLNode alloc] init];
        set.element=@"set";
        [set.attributes setObject:@"http://jabber.org/protocol/rsm" forKey:kXMLNS];
        
        MLXMLNode* max =[[MLXMLNode alloc] init];
        max.element=@"max";
        max.data=maxResults;
        [set.children addObject:max];
        [queryNode.children addObject:set];
        
    }
    
    if(endDate) {
        MLXMLNode* field3 =[[MLXMLNode alloc] init];
        field3.element=@"field";
        [field3.attributes setObject:@"end" forKey:@"var"];
        
        MLXMLNode* value3 =[[MLXMLNode alloc] init];
        value3.element=@"value";
        if(endDate) {
            value3.data=[rfc3339DateFormatter stringFromDate:endDate];
        }
        else  {
            value3.data=[rfc3339DateFormatter stringFromDate:[NSDate date]];
        }
        [field3.children addObject:value3];
        [xnode.children addObject:field3];
    }
    
    
    if(jid) {
        MLXMLNode* field3 =[[MLXMLNode alloc] init];
        field3.element=@"field";
        [field3.attributes setObject:@"with" forKey:@"var"];
        
        MLXMLNode* value3 =[[MLXMLNode alloc] init];
        value3.element=@"value";
        value3.data=jid;
        [field3.children addObject:value3];
        
        [xnode.children addObject:field3];
    }
    
    
    [queryNode.children addObject:xnode];
    
    [self.children addObject:queryNode];
    
}


/**
 The after here is the id usually received in the last stanza of the mam page
 */
-(void) setMAMQueryFromStart:(NSDate *) startDate after:(NSString *) uid withMax:(NSString *) maxResults  andJid:(NSString *)jid
{
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    
    
    MLXMLNode* xnode =[[MLXMLNode alloc] init];
    xnode.element=@"x";
    [xnode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xnode.attributes setObject:@"submit" forKey:@"type"];
    
    MLXMLNode* field1 =[[MLXMLNode alloc] init];
    field1.element=@"field";
    [field1.attributes setObject:@"FORM_TYPE" forKey:@"var"];
    [field1.attributes setObject:@"hidden" forKey:@"type"];
    
    MLXMLNode* value =[[MLXMLNode alloc] init];
    value.element=@"value";
    value.data=@"urn:xmpp:mam:2";
    [field1.children addObject:value];
    
    [xnode.children addObject:field1];
    
    NSDateFormatter *rfc3339DateFormatter;
    if(startDate) {
        rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
    
    if(startDate){
        MLXMLNode* field2 =[[MLXMLNode alloc] init];
        field2.element=@"field";
        [field2.attributes setObject:@"start" forKey:@"var"];
        
        MLXMLNode* value2 =[[MLXMLNode alloc] init];
        value2.element=@"value";
        if(startDate) {
            value2.data=[rfc3339DateFormatter stringFromDate:startDate];
        }
        else  {
            value2.data=[rfc3339DateFormatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:0]];
        }
        
        [field2.children addObject:value2];
        [xnode.children addObject:field2];
    }

    
    if(jid) {
        MLXMLNode* field3 =[[MLXMLNode alloc] init];
        field3.element=@"field";
        [field3.attributes setObject:@"with" forKey:@"var"];
        
        MLXMLNode* value3 =[[MLXMLNode alloc] init];
        value3.element=@"value";
        value3.data=jid;
        [field3.children addObject:value3];
        
        [xnode.children addObject:field3];
    }
    
    MLXMLNode* field3 =[[MLXMLNode alloc] init];
    field3.element=@"set";
    [field3.attributes setObject:@"http://jabber.org/protocol/rsm" forKey:kXMLNS];
    
    if(maxResults) {
        MLXMLNode* max =[[MLXMLNode alloc] init];
        max.element=@"max";
        max.data=maxResults;
        [field3.children addObject:max];
    }
    
    if(uid) {
   
        MLXMLNode* value3 =[[MLXMLNode alloc] init];
        value3.element=@"after";
        value3.data=uid;
        [field3.children addObject:value3];
        
       
    }
     [queryNode.children addObject:field3];
    
    [queryNode.children addObject:xnode];
    
    [self.children addObject:queryNode];
    
}

-(void) setRemoveFromRoster:(NSString*) jid
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:kXMLNS];
    [self.children addObject:queryNode];
    
    MLXMLNode* itemNode =[[MLXMLNode alloc] init];
    itemNode.element=@"item";
    [itemNode.attributes setObject:jid forKey:@"jid"];
    [itemNode.attributes setObject:@"remove" forKey:@"subscription"];
    [queryNode.children addObject:itemNode];
}

-(void) setRosterRequest:(NSString *) version
{       
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:kXMLNS];
    if(version)
    {
        [queryNode.attributes setObject:version forKey:@"ver"];
    }
    [self.children addObject:queryNode];
}

-(void) setVersion
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:version" forKey:kXMLNS];
    
    MLXMLNode* name =[[MLXMLNode alloc] init];
    name.element=@"name";
    name.data=@"Monal";
    
#if TARGET_OS_IPHONE
    MLXMLNode* os =[[MLXMLNode alloc] init];
    os.element=@"os";
    os.data=@"iOS";
#else
    MLXMLNode* os =[[MLXMLNode alloc] init];
    os.element=@"os";
    os.data=@"macOS";
#endif
    
    MLXMLNode* appVersion =[[MLXMLNode alloc] init];
    appVersion.element=@"version";
    appVersion.data=[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    
    [queryNode.children addObject:name];
    [queryNode.children addObject:os];
    [queryNode.children addObject:appVersion];
    [self.children addObject:queryNode];
}



-(void) setLast
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:last" forKey:kXMLNS];
    [queryNode.attributes setObject:@"0" forKey:@"seconds"];  // hasnt been away for 0 seconds
    [self.children addObject:queryNode];
}



-(void) httpUploadforFile:(NSString *) file ofSize:(NSNumber *) filesize andContentType:(NSString *) contentType
{
    MLXMLNode* requestNode =[[MLXMLNode alloc] init];
    requestNode.element=@"request";
    [requestNode.attributes setObject:@"urn:xmpp:http:upload" forKey:kXMLNS];
    
    MLXMLNode* filename =[[MLXMLNode alloc] init];
    filename.element=@"filename";
    filename.data=file;
    
    MLXMLNode* size =[[MLXMLNode alloc] init];
    size.element=@"size";
    size.data=[NSString stringWithFormat:@"%@", filesize];
    
    MLXMLNode* contentTypeNode =[[MLXMLNode alloc] init];
    contentTypeNode.element=@"content-type";
    contentTypeNode.data=contentType;
    
    [requestNode.children addObjectsFromArray:@[filename, size, contentTypeNode]];
    [self.children addObject:requestNode];
}


#pragma mark iq get
-(void) getAuthwithUserName:(NSString *)username
{
    [self.attributes setObject:@"auth1" forKey:@"id"];
    [self.attributes setObject:kiqGetType forKey:@"type"];
    
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"jabber:iq:auth"];
    
    MLXMLNode* userNode =[[MLXMLNode alloc] init];
    userNode.element=@"username";
    userNode.data =username;
    
    [queryNode.children addObject:userNode];
    [self.children addObject:queryNode];
}

-(void) getVcardTo:(NSString*) to
{
    [self setiqTo:to];

    MLXMLNode* vcardNode =[[MLXMLNode alloc] init];
    vcardNode.element=@"vCard";
    [vcardNode setXMLNS:@"vcard-temp"];
    
    [self.children addObject:vcardNode];
}

#pragma mark MUC
-(void) setInstantRoom
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"http://jabber.org/protocol/muc#owner" forKey:kXMLNS];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xNode.attributes setObject:@"submit" forKey:@"type"];
    
    [queryNode.children addObject:xNode];
    [self.children addObject:queryNode];
}

#pragma mark Jingle

-(void) setJingleInitiateTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];
    
    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-initiate" forKey:@"action"];
    [jingleNode.attributes setObject:[info objectForKey:@"initiator"] forKey:@"initiator"];
   [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
 
   MLXMLNode* contentNode =[[MLXMLNode alloc] init];
    contentNode.element=@"content";
    [contentNode.attributes setObject:@"initiator" forKey:@"creator"];
    [contentNode.attributes setObject:@"audio-session" forKey:@"name"];
    
    MLXMLNode* description =[[MLXMLNode alloc] init];
    description.element=@"description";
    [description.attributes setObject:@"urn:xmpp:jingle:apps:rtp:1" forKey:kXMLNS];
    [description.attributes setObject:@"audio" forKey:@"media"];

    
    MLXMLNode* payload =[[MLXMLNode alloc] init];
    payload.element=@"payload-type";
    [payload.attributes setObject:@"8" forKey:@"id"];
    [payload.attributes setObject:@"PCMA" forKey:@"name"];
    [payload.attributes setObject:@"8000" forKey:@"clockrate"];
    [payload.attributes setObject:@"1" forKey:@"channels"];
    
    [description.children addObject:payload];
    
    MLXMLNode* transport =[[MLXMLNode alloc] init];
    transport.element=@"transport";
    [transport.attributes setObject:@"urn:xmpp:jingle:transports:raw-udp:1" forKey:kXMLNS];

    
    MLXMLNode* candidate1 =[[MLXMLNode alloc] init];
    candidate1.element=@"candidate";
    [candidate1.attributes setObject:@"1" forKey:@"component"];
    [candidate1.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate1.attributes setObject:[info objectForKey:@"localport1"] forKey:@"port"];
    [candidate1.attributes setObject:@"monal001" forKey:@"id"];
    [candidate1.attributes setObject:@"0" forKey:@"generation"];
    
    MLXMLNode* candidate2 =[[MLXMLNode alloc] init];
    candidate2.element=@"candidate";
    [candidate2.attributes setObject:@"2" forKey:@"component"];
    [candidate2.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate2.attributes setObject:[info objectForKey:@"localport2"] forKey:@"port"];
    [candidate2.attributes setObject:@"monal002" forKey:@"id"];
    [candidate2.attributes setObject:@"0" forKey:@"generation"];
    
    [transport.children addObject:candidate1];
    [transport.children addObject:candidate2];
    
    [contentNode.children addObject:description];
    [contentNode.children addObject:transport];
    
    [jingleNode.children addObject:contentNode];
    [self.children addObject:jingleNode];
    
    
//        [query appendFormat:@" <iq to='%@/%@' id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' responder='%@' sid='%@'>
//         <content creator='initiator'  name=\"audio-session\" senders=\"both\" responder='%@'>
//         <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\">
//         <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\" channels='0'/></description>
//         
//         <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'>
//         <candidate component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\"   />
//         <candidate component=\"2\" ip=\"%@\" port=\"%@\"   id=\"monal002\" generation=\"0\"  /> </transport> </content>
//         
//         </jingle> </iq>", self.otherParty, _resource, _iqid, self.me, _to,  self.thesid, _to, _ownIP, self.localPort, _ownIP,self.localPort2];
}


-(void) setJingleAcceptTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];
    
    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-accept" forKey:@"action"];
    [jingleNode.attributes setObject:[info objectForKey:@"initiator"] forKey:@"initiator"];
    [jingleNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* contentNode =[[MLXMLNode alloc] init];
    contentNode.element=@"content";
    [contentNode.attributes setObject:@"creator" forKey:@"initiator"];
    [contentNode.attributes setObject:@"audio-session" forKey:@"name"];
    [contentNode.attributes setObject:@"both" forKey:@"senders"];
    [contentNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    
    
    MLXMLNode* description =[[MLXMLNode alloc] init];
    description.element=@"description";
    [description.attributes setObject:@"urn:xmpp:jingle:apps:rtp:1" forKey:kXMLNS];
    [description.attributes setObject:@"audio" forKey:@"media"];
    
    
    MLXMLNode* payload =[[MLXMLNode alloc] init];
    payload.element=@"payload-type";
    [payload.attributes setObject:@"8" forKey:@"id"];
    [payload.attributes setObject:@"PCMA" forKey:@"name"];
    [payload.attributes setObject:@"8000" forKey:@"clockrate"];
    [payload.attributes setObject:@"1" forKey:@"channels"];
    
    [description.children addObject:payload];
    
    MLXMLNode* transport =[[MLXMLNode alloc] init];
    transport.element=@"transport";
    [transport.attributes setObject:@"urn:xmpp:jingle:transports:raw-udp:1" forKey:kXMLNS];
    
    
    MLXMLNode* candidate1 =[[MLXMLNode alloc] init];
    candidate1.element=@"candidate";
    [candidate1.attributes setObject:@"1" forKey:@"component"];
    [candidate1.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate1.attributes setObject:[info objectForKey:@"localport1"] forKey:@"port"];
    [candidate1.attributes setObject:@"monal001" forKey:@"id"];
    [candidate1.attributes setObject:@"0" forKey:@"generation"];
    
    MLXMLNode* candidate2 =[[MLXMLNode alloc] init];
    candidate2.element=@"candidate";
    [candidate2.attributes setObject:@"2" forKey:@"component"];
    [candidate2.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate2.attributes setObject:[info objectForKey:@"localport2"] forKey:@"port"];
    [candidate2.attributes setObject:@"monal002" forKey:@"id"];
    [candidate2.attributes setObject:@"0" forKey:@"generation"];
    
    [transport.children addObject:candidate1];
    [transport.children addObject:candidate2];
    
    [contentNode.children addObject:description];
    [contentNode.children addObject:transport];
    
    [jingleNode.children addObject:contentNode];
    [self.children addObject:jingleNode];
    
}
-(void) setJingleDeclineTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];

    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-terminate" forKey:@"action"];
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* reason =[[MLXMLNode alloc] init];
    reason.element=@"reason";
    
    MLXMLNode* decline =[[MLXMLNode alloc] init];
    decline.element=@"decline";
    
    [reason.children addObject:decline] ;
    [jingleNode.children addObject:reason];
    [self.children addObject:jingleNode];
    
}

-(void) setJingleTerminateTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    if([jid rangeOfString:@"/"].location==NSNotFound) {
        [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];
    }
    else {
        [self setiqTo:jid];
    }
    
    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-terminate" forKey:@"action"];
  
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* reason =[[MLXMLNode alloc] init];
    reason.element=@"reason";

    MLXMLNode* success =[[MLXMLNode alloc] init];
    success.element=@"success";

    [reason.children addObject:success] ;
    [jingleNode.children addObject:reason];
    [self.children addObject:jingleNode];

  
}

#pragma mark - signal

-(void) subscribeDevices:(NSString*) jid
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];
    
    MLXMLNode* subscribe =[[MLXMLNode alloc] init];
    subscribe.element=@"subscribe";
    [subscribe.attributes setObject:@"eu.siacs.conversations.axolotl.devicelist" forKey:@"node"];
    [subscribe.attributes setObject:jid forKey:@"jid"];
    [pubsubNode.children addObject:subscribe];
    
    [self.children addObject:pubsubNode];
}


-(void) publishDevices:(NSArray*) devices
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];
    
    MLXMLNode* publish =[[MLXMLNode alloc] init];
    publish.element=@"publish";
    [publish.attributes setObject:@"eu.siacs.conversations.axolotl.devicelist" forKey:@"node"];
    
    MLXMLNode* itemNode =[[MLXMLNode alloc] initWithElement:@"item"];
    [itemNode.attributes setObject:@"current" forKey:kId];
    
    MLXMLNode* listNode =[[MLXMLNode alloc] init];
    listNode.element=@"list";
    [listNode.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
    
    [devices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *deviceid= (NSString *)obj;
        MLXMLNode* device =[[MLXMLNode alloc] init];
        device.element=@"device";
        [device.attributes setObject:deviceid forKey:kId];
        [listNode.children addObject:device];
    }];
  
    [itemNode.children addObject:listNode];
    
    [publish.children addObject:itemNode];
    [pubsubNode.children addObject:publish];
    
    [self.children addObject:pubsubNode];
}



-(void) publishKeys:(NSDictionary *) keys andPreKeys:(NSArray *) prekeys withDeviceId:(NSString*) deviceid
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];
    
    MLXMLNode* publish =[[MLXMLNode alloc] init];
    publish.element=@"publish";
    [publish.attributes setObject:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid] forKey:@"node"];
    
    MLXMLNode* itemNode =[[MLXMLNode alloc] init];
    itemNode.element=@"item";
    [itemNode.attributes setObject:@"current" forKey:kId];
    
    MLXMLNode* bundle =[[MLXMLNode alloc] init];
    bundle.element=@"bundle";
    [bundle.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
    
    MLXMLNode* signedPreKeyPublic =[[MLXMLNode alloc] init];
    signedPreKeyPublic.element=@"signedPreKeyPublic";
    [signedPreKeyPublic.attributes setObject:[keys objectForKey:@"signedPreKeyId"] forKey:@"signedPreKeyId"];
    signedPreKeyPublic.data = [EncodingTools encodeBase64WithData: [keys objectForKey:@"signedPreKeyPublic"]];
    [bundle.children addObject:signedPreKeyPublic];
    
    
    MLXMLNode* signedPreKeySignature =[[MLXMLNode alloc] init];
    signedPreKeySignature.element=@"signedPreKeySignature";
    signedPreKeySignature.data = [EncodingTools encodeBase64WithData:[keys objectForKey:@"signedPreKeySignature"]];
    [bundle.children addObject:signedPreKeySignature];
    
    MLXMLNode* identityKey =[[MLXMLNode alloc] init];
    identityKey.element=@"identityKey";
    identityKey.data = [EncodingTools encodeBase64WithData:[keys objectForKey:@"identityKey"]];
    [bundle.children addObject:identityKey];
    
    MLXMLNode* prekeyNode =[[MLXMLNode alloc] init];
    prekeyNode.element=@"prekeys";

    [prekeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        SignalPreKey *prekey=(SignalPreKey *) obj;
        
        MLXMLNode* preKeyPublic =[[MLXMLNode alloc] init];
        preKeyPublic.element=@"preKeyPublic";
        [preKeyPublic.attributes setObject:[NSString stringWithFormat:@"%d", prekey.preKeyId] forKey:@"preKeyId"];
        preKeyPublic.data = [EncodingTools encodeBase64WithData:prekey.keyPair.publicKey];
        [prekeyNode.children addObject:preKeyPublic];
        
    }];
    
    [bundle.children addObject:prekeyNode];
    [itemNode.children addObject:bundle];
    
    [publish.children addObject:itemNode];
    [pubsubNode.children addObject:publish];
    
    [self.children addObject:pubsubNode];
}


-(void) requestNode:(NSString*) node
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];

    
    MLXMLNode* subscribe =[[MLXMLNode alloc] init];
    subscribe.element=@"items";
    [subscribe.attributes setObject:node forKey:@"node"];
//[subscribe.attributes setObject:@"1" forKey:@"max_items"];
    
    [pubsubNode.children addObject:subscribe];
    [self.children addObject:pubsubNode];
    
}

-(void) requestDevices
{
    [self requestNode:@"eu.siacs.conversations.axolotl.devicelist"];
    
}

-(void) requestBundles:(NSString*) deviceid
{
    [self requestNode:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid]];
    
}

#pragma mark - Account Management
-(void) getRegistrationFields
{
    MLXMLNode* query =[[MLXMLNode alloc] init];
    query.element=@"query";
    [query setXMLNS:kRegisterNameSpace];
    [self.children addObject:query];
}

/*
 This is really hardcoded for yax.im might work for others
 */
-(void) registerUser:(NSString *) user withPassword:(NSString *) newPass captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields
{
    MLXMLNode* query =[[MLXMLNode alloc] init];
    query.element=@"query";
    [query setXMLNS:kRegisterNameSpace];
    
    MLXMLNode* x =[[MLXMLNode alloc] init];
    x.element=@"x";
    [x setXMLNS:kDataNameSpace];
    [x.attributes setValue:@"submit" forKey:@"type"];
    
    
    MLXMLNode* username =[[MLXMLNode alloc] init];
    username.element=@"field";
    [username.attributes setValue:@"username" forKey:@"var"];
    MLXMLNode* usernameValue =[[MLXMLNode alloc] init];
    usernameValue.element=@"value";
    usernameValue.data=user;
    [username.children addObject:usernameValue];
    
    MLXMLNode* password =[[MLXMLNode alloc] init];
    password.element=@"field";
    [password.attributes setValue:@"password" forKey:@"var"];
    MLXMLNode* passwordValue =[[MLXMLNode alloc] init];
    passwordValue.element=@"value";
    passwordValue.data=newPass;
     [password.children addObject:passwordValue];
    
    MLXMLNode* ocr =[[MLXMLNode alloc] init];
    ocr.element=@"field";
     [ocr.attributes setValue:@"ocr" forKey:@"var"];
    MLXMLNode* ocrValue =[[MLXMLNode alloc] init];
    ocrValue.element=@"value";
    ocrValue.data=captcha;
    [ocr.children addObject:ocrValue];
    
    [hiddenFields enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
       
        MLXMLNode* field =[[MLXMLNode alloc] init];
        field.element=@"field";
        [field.attributes setValue:key forKey:@"var"];
        MLXMLNode* fieldValue =[[MLXMLNode alloc] init];
        fieldValue.element=@"value";
        fieldValue.data=obj;
        [field.children addObject:fieldValue];
        
        [x.children addObject:field];
        
    }];
    
    [x.children addObject:username];
    [x.children addObject:password];
    [x.children addObject:ocr];
    
    [query.children addObject:x];
    
    [self.children addObject:query];
}

-(void) changePasswordForUser:(NSString *) user newPassword:(NSString *)newPass
{
    MLXMLNode* query =[[MLXMLNode alloc] init];
    query.element=@"query";
    [query setXMLNS:kRegisterNameSpace];
    
    MLXMLNode* username =[[MLXMLNode alloc] init];
    username.element=@"username";
    username.data=user;
    
    MLXMLNode* password =[[MLXMLNode alloc] init];
    password.element=@"password";
    password.data=newPass;
   
    [query.children addObject:username];
    [query.children addObject:password];
    
    [self.children addObject:query];
    
}


@end
