//
//  ParseMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "ParseMessage.h"
#import "MLSignalStore.h"

@interface ParseMessage()
@property (nonatomic, strong) NSMutableDictionary *currentKey; 

@end

@implementation ParseMessage

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    
     _messageBuffer=nil;
    
    if(([elementName isEqualToString:@"forwarded"])  )
    {
        State=@"Forwarded";
        return;
    }
    
    //comes first to not change state t message below immediatley
    if(([elementName isEqualToString:@"message"]) && [State isEqualToString:@"Forwarded"] )
    {
        if([attributeDict objectForKey:@"to"])
        {
            _to =[[(NSString*)[attributeDict objectForKey:@"to"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
            _to=[_to lowercaseString];
        }
        
        //this is the id of the forwarded message and overwrites the main message stanza's id. 
        _idval =[attributeDict objectForKey:@"id"];
        
    }
    
    if(([elementName isEqualToString:@"delay"]) && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:delay"])
    {
        NSDateFormatter *rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSSSSXXXXX"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
       
        _delayTimeStamp = [rfc3339DateFormatter dateFromString:[attributeDict objectForKey:@"stamp"]];
        if(!_delayTimeStamp)
        {
            NSDateFormatter *rfc3339DateFormatter2 = [[NSDateFormatter alloc] init];
       
            [rfc3339DateFormatter2 setLocale:enUSPOSIXLocale];
            [rfc3339DateFormatter2 setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
            [rfc3339DateFormatter2 setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"];
            _delayTimeStamp = [rfc3339DateFormatter2 dateFromString:[attributeDict objectForKey:@"stamp"]];
        }
        
        
    }
    
    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:sid:0"])
    {
        _stanzaId = [attributeDict objectForKey:@"id"];
        return;
    }
    
   
	if(([elementName isEqualToString:@"message"])  )
	{
		DDLogVerbose(@" message type check");
		
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
        
        _idval =[attributeDict objectForKey:@"id"] ;
        
        State=@"Message";
	}
    
    
    if([elementName isEqualToString:@"subject"])
    {
        return;
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
            DDLogVerbose(@"group chat message");
            _actualFrom=[parts objectAtIndex:1]; // the user name
			_from=[parts objectAtIndex:0]; // should be group name
		}
        else
            
        {
            DDLogVerbose(@"group chat message from a room ");
            _from=[attributeDict objectForKey:@"from"];
		}

		return;
	}
	else
        if([elementName isEqualToString:@"message"])
        {
            _from=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
            _to=[[(NSString*)[attributeDict objectForKey:@"to"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
            DDLogVerbose(@"message from %@ to %@", _from, _to);
            return;
        }
    
    
    if(([elementName isEqualToString:@"x"])  && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@""]))
    {
        State=@"OOB";
        return;
    }
    
    if([State isEqualToString:@"OOB"] && [elementName isEqualToString: @"url"])
    {
        DDLogVerbose(@"OOB Url seen");
        State=@"OOBUrl";
        
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
		DDLogVerbose(@"user reason set"); 
		State=@"MucUserReason";

		return;
	}
	

	if(([elementName isEqualToString:@"data"])  && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:avatar:data"]))
	{
        State=@"AvatarData";
		
		return;
	}
	
    
    if(([elementName isEqualToString:@"result"])  && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:mam:2"]))
    {
        _mamResult=YES;
        return;
    }
    
  
    
	if(([elementName isEqualToString:@"html"]) )
	{
        State=@"HTML";
		
		return;
	}

    
    if([elementName isEqualToString:@"request"]  && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:receipts"] )
    {
        _requestReceipt=YES;
        return;
    }
    
    if([elementName isEqualToString:@"received"]  && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:receipts"] )
    {
        _receivedID =[attributeDict objectForKey:@"id"];
        return;
    }
    
    
    
    if(([elementName isEqualToString:@"encryption"]) )
    {
        State=@"Encryption"; //TODO figure out the poing of this
        
        return;
    }
    
    
    if(([elementName isEqualToString:@"encrypted"])
       && [[attributeDict objectForKey:@"xmlns"] isEqualToString:@"eu.siacs.conversations.axolotl"]  )
    {
        State=@"OMEMO";
        return;
    }
    
    
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"header"] )
    {
        _sid=[attributeDict objectForKey:@"sid"];
        _signalKeys =[[NSMutableArray alloc] init];
        
    }
    
    
    //store in array
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"key"]) {
        
        self.currentKey =[[NSMutableDictionary alloc] init];
        [self.currentKey setObject:[attributeDict objectForKey:@"rid"] forKey:@"rid"];
        
        if([[attributeDict objectForKey:@"prekey"] isEqualToString:@"1"]
           || [[attributeDict objectForKey:@"prekey"] isEqualToString:@"true"])
        {
            [self.currentKey setObject:@"1" forKey:@"prekey"];
        } else  {
       [self.currentKey setObject:@"0" forKey:@"prekey"];
            
        }
       
    }
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if([elementName isEqualToString:@"body"])
    {
        if([State isEqualToString:@"HTML"]){
            _messagHTML=_messageBuffer;
            DDLogVerbose(@"got message HTML %@", self.messagHTML);
        } else
        {
            _messageText=_messageBuffer;
            DDLogVerbose(@"got message %@", self.messageText);
        }
    }
    
    if([elementName isEqualToString:@"message"])
    {
        _from=[_from lowercaseString];
        
        // this is the end of parse
        if(!_actualFrom) _actualFrom=_from;
        if(!_messageText) _messageText=_messagHTML;
        if(!_messageText) _messageText=_messageBuffer; 
    }
    
    if([State isEqualToString:@"OOBUrl"] && [elementName isEqualToString:@"url"])
    {
        _oobURL=_messageBuffer;
        _messageBuffer=nil;
    }
    
    if([State isEqualToString:@"AvatarData"])
    {
        _avatarData=_messageBuffer;
    }
    
   if([elementName isEqualToString:@"subject"])
    {
      _subject=_messageBuffer;
        _messageBuffer=nil; // specifically so the body doesnt get set 
    }
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"iv"])
    {
        _iv=_messageBuffer;
        _messageBuffer=nil;
    }
    
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"payload"])
    {
        _encryptedPayload=_messageBuffer;
        _messageBuffer=nil;
    }

    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"key"] &&_messageBuffer)
    {
        [self.currentKey setObject:[_messageBuffer copy] forKey:@"key"];
        [self.signalKeys addObject:self.currentKey];
        _messageBuffer=nil;
    }
}

@end
