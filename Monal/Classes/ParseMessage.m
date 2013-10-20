//
//  ParseMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "ParseMessage.h"

@implementation ParseMessage


#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    
   
	if(([elementName isEqualToString:@"message"])  )
	{
		debug_NSLog(@" message error");
		
        if ([[attributeDict objectForKey:@"type"] isEqualToString:kMessageErrorType])
        {
            _type=kMessageErrorType;
        }
        
        if ([[attributeDict objectForKey:@"type"] isEqualToString:kMessageGroupChatType])
        {
            _type=kMessageGroupChatType;
        }
        
        if ([[attributeDict objectForKey:@"type"] isEqualToString:kMessageChatType])
        {
            _type=kMessageChatType;
        }
        
        State=@"Message";
	}
	
	
    //ignore error message
	if([elementName isEqualToString:@"body"])
	{
		_hasBody=YES;
		return;
	}
    
    if(([elementName isEqualToString:@"message"])  && ([[attributeDict objectForKey:@"type"] isEqualToString:kMessageGroupChatType]))
	{
	
		NSArray*  parts=[[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/"];
		
		if([parts count]>1)
		{
            debug_NSLog(@"group chat message");
            _actualFrom=[parts objectAtIndex:0];
			_from=[parts objectAtIndex:1];
		}
        else
            
        {
            debug_NSLog(@"group chat message from a room ");
            _from=[attributeDict objectForKey:@"from"];
            _actualFrom= [attributeDict objectForKey:@"from"];
		}

		return;
	}
	else
        if([elementName isEqualToString:@"message"])
        {
            _from=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
            debug_NSLog(@"message from %@", _from);
            return;
        }

	//multi user chat
	//message->user:X
	if(([State isEqualToString:@"Message"]) && ( ([elementName isEqualToString: @"user:invite"]) || ([elementName isEqualToString: @"invite"]))
       // && (([[attributeDict objectForKey:@"xmlns:user"] isEqualToString:@"http://jabber.org/protocol/muc#user"]) ||
       //  ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/muc#user"])
       //   )
	   )
	{
		State=@"MucUser";
		_mucInvite=YES;

		return;
	}

	
	if((([State isEqualToString:@"MucUser"]) && (([elementName isEqualToString: @"user:reason"]))) || ([elementName isEqualToString: @"reason"]))
	{
		debug_NSLog(@"user reason set"); 
		State=@"MucUserReason";

		return;
	}
	

	if(([elementName isEqualToString:@"data"])  && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:avatar:data"]))
	{
        State=@"AvatarData";
		
		return;
	}
	
    
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if([elementName isEqualToString:@"body"])
    {
        _messageText=_messageBuffer;
        debug_NSLog(@"got message %@", _messageText);
    }
    
    if([elementName isEqualToString:@"message"])
    {
        _from=[_from lowercaseString];
        
        // this is the end of parse
        if(!_actualFrom) _actualFrom=_from;
        if(!_messageText) _messageText=_messageBuffer; 
    }
    
    if([State isEqualToString:@"AvatarData"])
    {
        _avatarData=_messageBuffer;
    }
    
}

@end
