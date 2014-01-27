//
//  ParseIq.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "ParseIq.h"

@implementation ParseIq

-(id) init{
    self=[super init];
    _features=[[NSMutableArray alloc] init];
   
    return self;
}


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
        if([_queryXMLNS isEqualToString:@"jabber:iq:roster"]) _roster=YES;
        
         [_features addObject:[attributeDict objectForKey:@"val"]];
          
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
    
    
    if([elementName isEqualToString:@"item"])
    {
        if(!_items)  _items=[[NSMutableArray alloc] init];
        [_items addObject:attributeDict];
    }
    
    
    
    if([elementName isEqualToString:@"identity"])
	{
        if([[attributeDict objectForKey:@"category"] isEqualToString:@"conference"])
        {
            _conferenceServer=self.from;
        }
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
