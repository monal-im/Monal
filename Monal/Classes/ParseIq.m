//
//  ParseIq.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "ParseIq.h"
#import "SignalPreKey.h"

@interface ParseIq()

@property (nonatomic, strong) NSMutableArray* omemoDevices;
@property (nonatomic, strong) NSMutableDictionary *currentPreKey;

@end

@implementation ParseIq

#pragma mark NSXMLParser delegate

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
         _queryXMLNS=[attributeDict objectForKey:@"xmlns"];
         if([_queryXMLNS isEqualToString:@"urn:xmpp:ping"])
             _ping=YES;
     }

    if([elementName isEqualToString:@"query"])
    {
        _queryXMLNS=[attributeDict objectForKey:@"xmlns"];
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#info"]) _discoInfo=YES;
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#items"]) _discoItems=YES;
        
        if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:roster"])  {
            State=@"RosterQuery";
            _roster=YES;
        }
        
        NSString* node =[attributeDict objectForKey:@"node"];
        if(node) _queryNode=node; 
          
     }
  
    
    if([elementName isEqualToString:@"feature"])
    {
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#info"]) {
            if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:roster"])
            {
                _roster=YES;
            }
        
            if(!_features)  _features=[[NSMutableSet alloc] init];
            if([attributeDict objectForKey:@"var"]) {
                [_features addObject:[attributeDict objectForKey:@"var"]];
            }
            
        }
        
    }
    
    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:auth"]) _legacyAuth=YES;
    
    //http upload
    
    if([elementName isEqualToString:@"slot"])
    {
        _queryXMLNS=[attributeDict objectForKey:@"xmlns"];
          State=@"slot";
        _httpUpload =YES; 
        return;
    }
    
    if([elementName isEqualToString:@"get"] && _httpUpload)
    {
        State = @"slotGet";
        return;
    }
    
    if([elementName isEqualToString:@"put"] && _httpUpload)
    {
         State = @"slotPut";
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
    
    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:time"])
    {
        _time=YES;
        return;
    }
    
    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:version"])
    {
        _version=YES;
        return;
    }
    
    
    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:last"])
    {
        _last=YES;
        return;
    }
    
    if([elementName isEqualToString:@"item"])
    {
        if(!_items)  _items=[[NSMutableArray alloc] init];
        [_items addObject:attributeDict];
    }
    
    
    if([elementName isEqualToString:@"prefs"] && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:mam:2"])
    {
        _mam2default =[attributeDict objectForKey:@"default"];
        return;
    }
    
    if([elementName isEqualToString:@"fin"] && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:mam:2"]  &&  [[attributeDict objectForKey:@"complete"] isEqualToString:@"true"])
    {
        _mam2fin =YES;
        return;
    }
    
    if([elementName isEqualToString:@"set"] && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/rsm"])
    {
        State=@"MAMSet";
        return;
    }
    
 
    
    
    //** jingle ** /
    
    if([elementName isEqualToString:@"jingle"] &&  [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:jingle:1"])
     {
         _jingleSession=[attributeDict copy];
         return;
     }
    
    if([elementName isEqualToString:@"description"] &&  [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:jingle:apps:rtp:1"])
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
    
    if([elementName isEqualToString:@"transport"] &&  [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:jingle:transports:raw-udp:1"])
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
    
    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"eu.siacs.conversations.axolotl"]) {
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
    
    
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
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
    
    if(([elementName isEqualToString:@"get"]) && _httpUpload )
    {
        _getURL=[_messageBuffer copy];
        return;
    }
    
    if(([elementName isEqualToString:@"put"]) && _httpUpload )
    {
        _putURL=[_messageBuffer copy];
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

}




@end
