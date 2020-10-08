//
//  ParseIq.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "ParseIq.h"
#import "SignalPreKey.h"
#import "HelperTools.h"

@interface ParseIq()
{
    NSMutableArray* _identities;
    NSString* _currentUploadHeader;
}

@property (nonatomic, strong) NSMutableArray* omemoDevices;
@property (nonatomic, strong) NSMutableDictionary *currentPreKey;
@property (nonatomic, strong) NSString *currentFormField;

@end

@implementation ParseIq

#pragma mark NSXMLParser delegate

// return always sorted (https://xmpp.org/extensions/xep-0115.html#ver-gen)
-(NSArray*) identities
{
    return [_identities sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    if([elementName isEqualToString:@"iq"])
    {
         [super parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
    }
    
	//start sessionafter bind reply
	if([elementName isEqualToString:@"bind"])
	{
        _shouldSetBind=YES;
		State=@"Bind";
		return; 
	}
	
     if([elementName isEqualToString:@"ping"])
     {
         _queryXMLNS=namespaceURI;
         if([_queryXMLNS isEqualToString:@"urn:xmpp:ping"])
             _ping=YES;
     }

    if([elementName isEqualToString:@"query"])
    {
        _queryXMLNS=namespaceURI;
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#info"])
            _discoInfo=YES;
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#items"])
            _discoItems=YES;
        if([_queryXMLNS isEqualToString:kRegisterNameSpace])
        {
            _registration=YES;
        }
        
        
        if([namespaceURI isEqualToString:@"jabber:iq:roster"])  {
            State=@"RosterQuery";
            _roster=YES;
            _rosterVersion = [attributeDict objectForKey:@"ver"];
        }
        
        NSString* node =[attributeDict objectForKey:@"node"];
        if(node) _queryNode=node; 
          
     }
    
    if([elementName isEqualToString:@"identity"])
    {
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#info"])
        {
            if(!_identities)
                _identities = [[NSMutableArray alloc] init];
            [_identities addObject:[NSString stringWithFormat:@"%@/%@/%@/%@",
                attributeDict[@"category"] ? attributeDict[@"category"] : @"",
                attributeDict[@"type"] ? attributeDict[@"type"] : @"",
                //TODO: check if the xml parser parses this to 'xml:lang' or 'lang' and change accordingly
                attributeDict[@"lang"] ? attributeDict[@"lang"] : @"",
                attributeDict[@"name"] ? attributeDict[@"name"] : @""
            ]];
        }
    }
    
    if([elementName isEqualToString:@"feature"])
    {
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#info"])
        {
            if([namespaceURI isEqualToString:@"jabber:iq:roster"])
                _roster = YES;
            
            if(!_features)
                _features = [[NSMutableSet alloc] init];
            if([attributeDict objectForKey:@"var"])
                [_features addObject:[attributeDict objectForKey:@"var"]];
        }
    }
    
    //http upload
    if([elementName isEqualToString:@"slot"])
    {
        _queryXMLNS = namespaceURI;
        State=@"slot";
        _httpUpload = YES; 
        return;
    }
    
    if([elementName isEqualToString:@"get"] && _httpUpload)
    {
        State = @"slotGet";
        _getURL = [attributeDict objectForKey:@"url"];
        return;
    }
    
    if([elementName isEqualToString:@"put"] && _httpUpload)
    {
        State = @"slotPut";
        _putURL = [attributeDict objectForKey:@"url"];
        _uploadHeaders = [[NSMutableDictionary alloc] init];
        return;
    }
    
    if([elementName isEqualToString:@"header"] && [State isEqualToString:@"slotPut"])
    {
        _currentUploadHeader = [attributeDict objectForKey:@"name"];
        return;
    }
    
    //roster
    
    if([elementName isEqualToString:@"item"] && [State isEqualToString:@"RosterQuery"])
    {
        State=@"RosterItem"; // we can get item info
    }
    
    
    if([elementName isEqualToString:@"group"] && [State isEqualToString:@"RosterItem"])
    {
        State=@"RosterGroup"; // we can get group name here
    }
    
    if([elementName isEqualToString:@"vCard"])
    {
        State=@"vCard";
        _vCard=YES;
    }
    

    if([namespaceURI isEqualToString:@"jabber:iq:version"])
    {
        _version=YES;
        return;
    }
    
    if([elementName isEqualToString:@"item"])
    {
        if(!_items)
            _items=[[NSMutableArray alloc] init];
        [_items addObject:attributeDict];
    }
    
    
    if([elementName isEqualToString:@"prefs"] && [namespaceURI isEqualToString:@"urn:xmpp:mam:2"])
    {
        _mam2default = [attributeDict objectForKey:@"default"];
        return;
    }
    
    if([elementName isEqualToString:@"fin"] && [namespaceURI isEqualToString:@"urn:xmpp:mam:2"])
    {
        if([[attributeDict objectForKey:@"complete"] isEqualToString:@"true"])
            _mam2fin = YES;
        _mamQueryId = [attributeDict objectForKey:@"queryid"];
        return;
    }
    
    if([elementName isEqualToString:@"set"] && [namespaceURI isEqualToString:@"http://jabber.org/protocol/rsm"])
    {
        State=@"MAMSet";
        return;
    }
    
 
    
    
    //** jingle ** /
    
    if([elementName isEqualToString:@"jingle"] &&  [namespaceURI isEqualToString:@"urn:xmpp:jingle:1"])
     {
         _jingleSession=[attributeDict copy];
         return;
     }
    
    if([elementName isEqualToString:@"description"] &&  [namespaceURI isEqualToString:@"urn:xmpp:jingle:apps:rtp:1"])
    {
        State=@"jingleDescription";
        return;
    }
    
    if([elementName isEqualToString:@"payload-type"] &&  [State isEqualToString:@"jingleDescription"])
    {
        if(!_jinglePayloadTypes) {
            _jinglePayloadTypes =[[NSMutableArray alloc] init];
        }
        [_jinglePayloadTypes addObject:attributeDict];
        return;
    }
    
    if([elementName isEqualToString:@"transport"] &&  [namespaceURI isEqualToString:@"urn:xmpp:jingle:transports:raw-udp:1"])
    {
        State=@"jingleTransport";
        return;
    }
    
    if([elementName isEqualToString:@"candidate"] &&  [State isEqualToString:@"jingleTransport"])
    {
        if(!_jingleTransportCandidates) {
            _jingleTransportCandidates =[[NSMutableArray alloc] init];
        }
        [_jingleTransportCandidates addObject:attributeDict];
        return;
    }
    
    //OMEMO
    
    if( [elementName isEqualToString:@"item"] || [elementName isEqualToString:@"items"] )
    {
        NSString *node = (NSString *) [attributeDict objectForKey:@"node"];
        if([node hasPrefix:@"eu.siacs.conversations.axolotl.bundles:"])
        {
            NSArray *parts = [node componentsSeparatedByString:@":"];
            if(parts.count>1)
            {
                _deviceid= parts[1];
            }
        }
        
    }
    
    if([namespaceURI isEqualToString:@"eu.siacs.conversations.axolotl"]) {
        if([elementName isEqualToString:@"bundle"])
        {
            State=@"Bundle";
            _preKeys =[[NSMutableArray alloc] init];
            return;
        }
        
        if([elementName isEqualToString:@"list"] )
        {
            State=@"DeviceList";
            self.omemoDevices = [[NSMutableArray alloc] init];
            return;
        }
    }
    
    if([State isEqualToString:@"DeviceList"] && [elementName isEqualToString:@"device"] )
    {
        [self.omemoDevices addObject:[attributeDict objectForKey:@"id"]];
    }
    
    
    if([State isEqualToString:@"Bundle"] && [elementName isEqualToString:@"preKeyPublic"] )
    {
        self.currentPreKey =[[NSMutableDictionary alloc] init];
        [self.currentPreKey setObject:[attributeDict objectForKey:@"preKeyId"] forKey:@"preKeyId"];
    }
    
    
    if([elementName isEqualToString:@"signedPreKeyPublic"] &&  [State isEqualToString:@"Bundle"])
    {
        _signedPreKeyId = [attributeDict objectForKey:@"signedPreKeyId"];
    }
    
 
    //register
    if([namespaceURI isEqualToString:kDataNameSpace] && self.registration) {
        if([elementName isEqualToString:@"x"]) {
            State = @"RegistrationForm";
            return;
        }
    }
    
    if([State isEqualToString:@"RegistrationForm"])
    {
        if([elementName isEqualToString:@"field"] && [[attributeDict objectForKey:@"type"] isEqualToString:@"hidden"]) {
            self.currentFormField =[attributeDict objectForKey:@"var"];
            if(!self.hiddenFormFields) self.hiddenFormFields = [[NSMutableDictionary alloc] init];
        }
        
        if([elementName isEqualToString:@"data"]) {
            State = @"RegistrationFormData";
            return;
        }
    }
    
    if([elementName isEqualToString:@"error"]) {
        State = @"Error";
        return;
    }
    
    if([State isEqualToString:@"Error"] ) {
        if([elementName isEqualToString:@"text"]) {
            State = @"ErrorText";
            return;
        }
    }
    
    
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    [super parser:parser didEndElement:elementName namespaceURI:namespaceURI qualifiedName:qName];
    
    if([elementName isEqualToString:@"header"] && [State isEqualToString:@"slotPut"])
    {
        if(_currentUploadHeader)
            _uploadHeaders[_currentUploadHeader] = [_messageBuffer copy];
        _currentUploadHeader = nil;
        return;
    }
    
    if(([elementName isEqualToString:@"text"]) && [State isEqualToString:@"ErrorText"])
    {
        _errorMessage=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"value"]) && [State isEqualToString:@"RegistrationForm"]
       )
    {
        if(self.currentFormField && _messageBuffer) {
            [self.hiddenFormFields setObject:[_messageBuffer copy] forKey:self.currentFormField];
        }
        self.currentFormField=nil;
        return;
    }
    
    if(([elementName isEqualToString:@"jid"]) && [State isEqualToString:@"Bind"]
	   )
    {
        _jid=[_messageBuffer copy];
        return; 
    }
    
    if(([elementName isEqualToString:@"FN"]) && [State isEqualToString:@"vCard"]
	   )
    {
        if(!_fullName){ //might already be set by nick name. prefer that
        _fullName=[_messageBuffer copy];
        }
        return;
    }
    
    if(([elementName isEqualToString:@"NICKNAME"]) && [State isEqualToString:@"vCard"]
       )
    {
        _fullName=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"URL"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _URL=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"TYPE"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _photoType=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"BINVAL"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _photoBinValue=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"item"]) && [State isEqualToString:@"RosterItem"]
       )
    {
        //we would have a user name here
        // _photoBinValue=_messageBuffer;
        return;
    }
    
    if(([elementName isEqualToString:@"group"]) && [State isEqualToString:@"RosterGroup"]
	   )
    {
        //we would have a group name here
       // _photoBinValue=_messageBuffer;
        return;
    }
    
    if([elementName isEqualToString:@"signedPreKeyPublic"] &&  [State isEqualToString:@"Bundle"])
    {
       _signedPreKeyPublic= [_messageBuffer copy];
        _messageBuffer=nil;
        return;
    }
    
    if([elementName isEqualToString:@"signedPreKeySignature"] &&  [State isEqualToString:@"Bundle"])
    {
        _signedPreKeySignature= [_messageBuffer copy];
        _messageBuffer=nil;
        return;
    }
    
    
    if([elementName isEqualToString:@"identityKey"] &&  [State isEqualToString:@"Bundle"])
    {
        _identityKey= [_messageBuffer copy];
        _messageBuffer=nil;
        return;
    }
    
    
    
    
    if([elementName isEqualToString:@"preKeyPublic"] &&  [State isEqualToString:@"Bundle"])
    {
        [self.currentPreKey setObject:[_messageBuffer copy]  forKey:@"preKey"];
        [self.preKeys addObject:self.currentPreKey];
        _messageBuffer=nil;
        return;
    }
 

    if([elementName isEqualToString:@"last"] && [State isEqualToString:@"MAMSet"])
    {
        _mam2Last=[_messageBuffer copy];
        return;
    }
    
    if([elementName isEqualToString:@"first"] && [State isEqualToString:@"MAMSet"])
    {
        _mam2First=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"data"]) && [State isEqualToString:@"RegistrationFormData"]
       )
    {
        _captchaData=[HelperTools dataWithBase64EncodedString:_messageBuffer];
        return;
    }
    
    if(([elementName isEqualToString:@"name"]) && [namespaceURI isEqualToString:@"jabber:iq:version"]
       )
    {
        _entityName = [_messageBuffer copy];
        _entitySoftwareVersion = YES;
        return;
    }
    
    if(([elementName isEqualToString:@"version"]) && [namespaceURI isEqualToString:@"jabber:iq:version"]
       )
    {
        _entityVersion = [_messageBuffer copy];
        _entitySoftwareVersion = YES;
        return;
    }
    
    if(([elementName isEqualToString:@"os"]) && [namespaceURI isEqualToString:@"jabber:iq:version"]
       )
    {
        _entityOs = [_messageBuffer copy];
        _entitySoftwareVersion = YES;
        return;
    }
}




@end
