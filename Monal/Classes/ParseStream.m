//
//  ParseStream.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "ParseStream.h"

@implementation ParseStream

#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{
    debug_NSLog(@"began this element: %@", elementName);
     _messageBuffer=nil;
    
    //getting login mechanisms
	if([elementName isEqualToString:@"stream:features"])
	{
		State=@"Features";
		return;
		
	}
	
    if(([State isEqualToString:@"Features"]) &&([elementName isEqualToString:@"auth"]))
	{
        debug_NSLog(@"Supports legacy auth");
        _supportsLegacyAuth=true;
        
		return;
    }
    
    if(([State isEqualToString:@"Features"]) &&([elementName isEqualToString:@"register"]))
	{
        debug_NSLog(@"Supports user registration");
        _supportsUserReg=YES;
        
		return;
    }
    
	if(([State isEqualToString:@"Features"]) &&([elementName isEqualToString:@"starttls"]))
	{
        debug_NSLog(@"Using new style SSL");
        _callStartTLS=YES;
		[parser abortParsing];
	}
    
    
	if(([elementName isEqualToString:@"proceed"]) && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-tls"]) )
	{
		debug_NSLog(@"Got SartTLS procced");
		//trying to switch to TLS
        _startTLSProceed=YES;
		[parser abortParsing];
		
	}
    
	if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"bind"]))
	{

        _bind=YES;
		return;
    }
	
	
    //***** sasl success...
	if(([elementName isEqualToString:@"success"]) &&  ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
	   )
		
	{
		_SASLSuccess=YES;
        [parser abortParsing];
	}
    
	
	if(([State isEqualToString:@"Features"]) && [elementName isEqualToString:@"mechanisms"] )
	{
	
		debug_NSLog(@"mechanisms xmlns:%@ ", [attributeDict objectForKey:@"xmlns"]);
		if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
		{
			debug_NSLog(@"SASL supported");
			_supportsSASL=YES;
		}
		State=@"Mechanisms";
		return;
	}

	if(([State isEqualToString:@"Mechanisms"]) && [elementName isEqualToString:@"mechanism"])
	{
		debug_NSLog(@"Reading mechanism"); 
		State=@"Mechanism";
		return;
	}
	
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if( ([elementName isEqualToString:@"mechanism"]) && ([State isEqualToString:@"Mechanism"]))
	{
		
		State=@"Mechanisms";
		
		debug_NSLog(@"got login mechanism: %@", _messageBuffer);
		if([_messageBuffer isEqualToString:@"PLAIN"])
		{
			debug_NSLog(@"SASL PLAIN is supported");
			_SASLPlain=YES;
		}
		
		if([_messageBuffer isEqualToString:@"CRAM-MD5"])
		{
			debug_NSLog(@"SASL CRAM-MD5 is supported");
			_SASLCRAM_MD5=YES;
		}
		
		if([_messageBuffer isEqualToString:@"DIGEST-MD5"])
		{
			debug_NSLog(@"SASL DIGEST-MD5 is supported");
			_SASLDIGEST_MD5=YES;
		}
        
        _messageBuffer=nil; 
		return;
		
	}
}




@end
