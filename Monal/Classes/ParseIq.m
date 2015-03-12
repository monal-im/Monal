//
//  ParseIq.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "ParseIq.h"

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
        
        NSString* node =[attributeDict objectForKey:@"node"];
        if(node) _queryNode=node; 
          
     }
    
    
    if([elementName isEqualToString:@"feature"])
    {
        if([_queryXMLNS isEqualToString:@"http://jabber.org/protocol/disco#info"]) {
            if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:roster"]) _roster=YES;
            else if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:auth"]) _legacyAuth=YES;
            
            if(!_features)  _features=[[NSMutableSet alloc] init];
            if([attributeDict objectForKey:@"var"]) {
                [_features addObject:[attributeDict objectForKey:@"var"]];
            }
            
        }
        
    }
  
    
    if([elementName isEqualToString:@"group"] && _roster==YES)
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
    
    
    
    if([elementName isEqualToString:@"identity"])
	{
        if([[attributeDict objectForKey:@"category"] isEqualToString:@"conference"])
        {
            if([[attributeDict objectForKey:@"type"] isEqualToString:@"text"])
            {
            _conferenceServer=self.from;
            }
        }
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
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if(([elementName isEqualToString:@"jid"]) && [State isEqualToString:@"Bind"]
	   )
    {
        _jid=_messageBuffer;
        return; 
    }
    
    if(([elementName isEqualToString:@"FN"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _fullName=_messageBuffer;
        return;
    }
    
    if(([elementName isEqualToString:@"URL"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _URL=_messageBuffer;
        return;
    }
    
    if(([elementName isEqualToString:@"TYPE"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _photoType=_messageBuffer;
        return;
    }
    
    if(([elementName isEqualToString:@"BINVAL"]) && [State isEqualToString:@"vCard"]
	   )
    {
        _photoBinValue=_messageBuffer;
        return;
    }
    
    if(([elementName isEqualToString:@"group"]) && [State isEqualToString:@"RosterGroup"]
	   )
    {
        //we would have a group name here
       // _photoBinValue=_messageBuffer;
        return;
    }
   
}




@end
