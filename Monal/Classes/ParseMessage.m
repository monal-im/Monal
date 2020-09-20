//
//  ParseMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "ParseMessage.h"
#import "MLSignalStore.h"
#import "HelperTools.h"

@interface ParseMessage()
@property (nonatomic, strong) NSMutableDictionary *currentKey;
@property (nonatomic, strong) NSMutableArray *devices;

@end

@implementation ParseMessage



#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    [super parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
     _messageBuffer = nil;
    
    if(([elementName isEqualToString:@"forwarded"])  )
    {
        State = @"Forwarded";
        return;
    }
    
    //comes first to not change state message below immediatley
    if(([elementName isEqualToString:@"message"]) && [State isEqualToString:@"Forwarded"] )
    {
        if([attributeDict objectForKey:@"to"])
        {
            _to = [[(NSString*)[attributeDict objectForKey:@"to"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
            _to = [_to lowercaseString];
        }
        
        if([(NSString*)[attributeDict objectForKey:@"id"] length]>0) {
            //this is the id of the forwarded message and overwrites the main message stanza's id.
            _idval = [attributeDict objectForKey:@"id"];
        }
    }
    
    if(([elementName isEqualToString:@"active"]) && [namespaceURI isEqualToString:@"http://jabber.org/protocol/chatstates"])
    {
        _composing = NO;
        _notComposing = YES;
    }
    
    if(([elementName isEqualToString:@"composing"]) && [namespaceURI isEqualToString:@"http://jabber.org/protocol/chatstates"])
    {
        _composing = YES;
        _notComposing = NO;
    }
    
    if(([elementName isEqualToString:@"paused"]) && [namespaceURI isEqualToString:@"http://jabber.org/protocol/chatstates"])
    {
        _composing = NO;
        _notComposing = YES;
    }
    
    if(([elementName isEqualToString:@"inactive"]) && [namespaceURI isEqualToString:@"http://jabber.org/protocol/chatstates"])
    {
        _composing = NO;
        _notComposing = YES;
    }
    
    if(([elementName isEqualToString:@"delay"]) && [namespaceURI isEqualToString:@"urn:xmpp:delay"])
    {
        _delayTimeStamp = [HelperTools parseDateTimeString:[attributeDict objectForKey:@"stamp"]];
    }
    
    if([elementName isEqualToString:@"stanza-id"] && [namespaceURI isEqualToString:@"urn:xmpp:sid:0"])
    {
        _stanzaId = [attributeDict objectForKey:@"id"];
    }
    
    if(([elementName isEqualToString:@"message"]))
    {
        DDLogVerbose(@"message type check");
        _type = [attributeDict objectForKey:@"type"];
        State = @"Message";
    }
    
    if([elementName isEqualToString:@"subject"])
    {
        return;
    }
    
    //ignore error message
	if([elementName isEqualToString:@"body"])
	{
		_hasBody = YES;
		return;
	}

	if([elementName isEqualToString:@"message"])
    {
        if([[attributeDict objectForKey:@"type"] isEqualToString:kMessageGroupChatType])
        {
            NSArray* parts = [[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/"];
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
        else if([[attributeDict objectForKey:@"type"] isEqualToString:kMessageHeadlineType])
        {
            _from = [[_from componentsSeparatedByString:@"/" ] objectAtIndex:0];
            _to = [[_to  componentsSeparatedByString:@"/" ] objectAtIndex:0];
            State = @"Headline";
            return;
        }
        else
        {
            _from = [[_from componentsSeparatedByString:@"/" ] objectAtIndex:0];
            _to = [[_to  componentsSeparatedByString:@"/" ] objectAtIndex:0];
            
            // carbons are only from myself
            if([_to isEqualToString:_from])
            {
                _from = [[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
                _to = [[(NSString*)[attributeDict objectForKey:@"to"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
                DDLogVerbose(@"message from %@ to %@", _from, _to);
                return;
            }
            else
            {
                //DDLogError(@"message impersonation");
                return;
            }
        }
    }
    
    if(([elementName isEqualToString:@"x"])  && ([namespaceURI isEqualToString:@""]))
    {
        State = @"OOB";
        return;
    }
    
    if([State isEqualToString:@"OOB"] && [elementName isEqualToString: @"url"])
    {
        DDLogVerbose(@"OOB Url seen");
        State = @"OOBUrl";
        return;
    }
    
    //multi user chat
    //message->user:X
    if(([State isEqualToString:@"Message"]) && ( ([elementName isEqualToString: @"user:invite"]) || ([elementName isEqualToString: @"invite"]))
        // && (([[attributeDict objectForKey:@"xmlns:user"] isEqualToString:@"http://jabber.org/protocol/muc#user"]) ||
        //  ([namespaceURI isEqualToString:@"http://jabber.org/protocol/muc#user"])
        //   )
        )
    {
        State = @"MucUser";
        _mucInvite = YES;

        return;
    }
    
    if((([State isEqualToString:@"MucUser"]) && (([elementName isEqualToString: @"user:reason"]))) || ([elementName isEqualToString: @"reason"]))
    {
        DDLogVerbose(@"user reason set"); 
        State = @"MucUserReason";
        return;
    }
    

    if(([elementName isEqualToString:@"data"])  && ([namespaceURI isEqualToString:@"urn:xmpp:avatar:data"]))
    {
        State = @"AvatarData";
        return;
    }
    
    if(([elementName isEqualToString:@"result"])  && ([namespaceURI isEqualToString:@"urn:xmpp:mam:2"]))
    {
        _mamResult = YES;
        _stanzaId = [attributeDict objectForKey:@"id"];
        _mamQueryId = [attributeDict objectForKey:@"queryid"];
        return;
    }
    
    if(([elementName isEqualToString:@"html"]) )
    {
        State = @"HTML";
        return;
    }
    
    if([elementName isEqualToString:@"request"]  && [namespaceURI isEqualToString:@"urn:xmpp:receipts"] )
    {
        _requestReceipt = YES;
        return;
    }
    
    if([elementName isEqualToString:@"received"]  && [namespaceURI isEqualToString:@"urn:xmpp:receipts"] )
    {
        _receivedID = [attributeDict objectForKey:@"id"];
        return;
    }
    
    if([State isEqualToString:@"Headline"] &&
        [elementName isEqualToString:@"items"]
       && [[attributeDict objectForKey:@"node"] isEqualToString:@"eu.siacs.conversations.axolotl.devicelist"]  )
    {
        State = @"OMEMODevices";
        self.devices = [[NSMutableArray alloc] init];
        return;
    }
    
    if([State isEqualToString:@"OMEMODevices"] &&
       [elementName isEqualToString:@"list"]
       && [namespaceURI isEqualToString:@"eu.siacs.conversations.axolotl"]  )
    {
        State = @"OMEMODeviceList";
        self.devices = [[NSMutableArray alloc] init];
        return;
    }
    
    if([State isEqualToString:@"OMEMODeviceList"] &&
       [elementName isEqualToString:@"device"])
    {
        if([attributeDict objectForKey:@"id"]) {
            [self.devices addObject:[attributeDict objectForKey:@"id"]];
        }
        return;
    }
    
    if(([elementName isEqualToString:@"encrypted"])
       && [namespaceURI isEqualToString:@"eu.siacs.conversations.axolotl"]  )
    {
        State = @"OMEMO";
        return;
    }
    
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"header"] )
    {
        _sid = [attributeDict objectForKey:@"sid"];
        _signalKeys = [[NSMutableArray alloc] init];
    }
    
    //store in array
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"key"]) {
        self.currentKey =[[NSMutableDictionary alloc] init];
        [self.currentKey setObject:[attributeDict objectForKey:@"rid"] forKey:@"rid"];
        
        // Check if key is preKey
        if([[attributeDict objectForKey:@"prekey"] isEqualToString:@"1"]
           || [[attributeDict objectForKey:@"prekey"] isEqualToString:@"true"])
        {
            [self.currentKey setObject:@"1" forKey:@"prekey"];
        }
        else
        {
            [self.currentKey setObject:@"0" forKey:@"prekey"];
        }
    }
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    [super parser:parser didEndElement:elementName namespaceURI:namespaceURI qualifiedName:qName];
    
    if([elementName isEqualToString:@"body"])
    {
        if([State isEqualToString:@"HTML"])
        {
            DDLogVerbose(@"got (and throwing away) message HTML: %@", _messageBuffer);
        }
        else
        {
            _messageText = _messageBuffer;
            DDLogVerbose(@"got message: %@", self.messageText);
        }
    }
    
    if([elementName isEqualToString:@"message"])
    {
        _from=[_from lowercaseString];
        
        // this is the end of parse
        if(!_actualFrom)
            _actualFrom = _from;
    }
    
    if([State isEqualToString:@"OOBUrl"] && [elementName isEqualToString:@"url"])
    {
        _oobURL = _messageBuffer;
    }
    
    if([State isEqualToString:@"AvatarData"])
    {
        _avatarData = _messageBuffer;
    }
    
   if([elementName isEqualToString:@"subject"])
    {
      _subject = _messageBuffer;
    }
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"iv"])
    {
        _iv = _messageBuffer;
    }
    
    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"payload"])
    {
        _encryptedPayload = _messageBuffer;
    }

    if([State isEqualToString:@"OMEMO"] && [elementName isEqualToString:@"key"] &&_messageBuffer)
    {
        [self.currentKey setObject:[_messageBuffer copy] forKey:@"key"];
        [self.signalKeys addObject:self.currentKey];
    }
    
    _messageBuffer = nil;
}

@end
