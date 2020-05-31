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
    
    [super parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
     _messageBuffer=nil;
     
    //getting login mechanisms
	if([elementName isEqualToString:@"features"])
	{
		State=@"Features";
		return;
		
	}
	
    if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"auth"]))
	{
        DDLogVerbose(@"Supports legacy auth");
        _supportsLegacyAuth=true;
        
		return;
    }
    
    if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"register"]))
	{
        DDLogVerbose(@"Supports user registration");
        _supportsUserReg=YES;
        
		return;
    }
    
	if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"starttls"]))
	{
        DDLogVerbose(@"Using new style SSL");
        _callStartTLS=YES;
		return; 
	}
    
    if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"csi"]))
    {
        DDLogVerbose(@"supports csi");
        _supportsClientState=YES;
        return;
    }
    
	if(([elementName isEqualToString:@"proceed"]) && ([namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-tls"]) )
	{
		DDLogVerbose(@"Got SartTLS procced");
		//trying to switch to TLS
        _startTLSProceed=YES;
        return;
		
	}
    
	if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"bind"]))
	{

        _bind=YES;
		return;
    }
	
    /** stream management **/
    if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"sm"]))
    {
        if([namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
        {
            _supportsSM3=YES;
        }
        return;
    }
    
    if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"ver"]))
    {
        if([namespaceURI isEqualToString:@"urn:xmpp:features:rosterver"])
        {
            _supportsRosterVer=YES;
        }
       
        return;
    }
    
    
    //***** sasl success...
	if([elementName isEqualToString:@"success"] && [namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
	{
		_SASLSuccess=YES;
        return;
	}
    
	if(([State isEqualToString:@"Features"]) && [elementName isEqualToString:@"mechanisms"] )
	{
	
		DDLogVerbose(@"mechanisms xmlns:%@ ", namespaceURI);
		if([namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
		{
			DDLogVerbose(@"SASL supported");
			_supportsSASL=YES;
		}
		State=@"Mechanisms";
		return;
	}

	if(([State isEqualToString:@"Mechanisms"]) && [elementName isEqualToString:@"mechanism"])
	{
		DDLogVerbose(@"Reading mechanism"); 
		State=@"Mechanism";
        
		return;
	}
	
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    [super parser:parser didEndElement:elementName namespaceURI:namespaceURI qualifiedName:qName];
    
    if(([elementName isEqualToString:@"mechanism"]) && ([State isEqualToString:@"Mechanism"]))
	{
		State=@"Mechanisms";
		
		DDLogVerbose(@"got login mechanism: %@", _messageBuffer);
		if([_messageBuffer isEqualToString:@"PLAIN"])
		{
			DDLogVerbose(@"SASL PLAIN is supported");
			_SASLPlain=YES;
		}
		
		if([_messageBuffer isEqualToString:@"CRAM-MD5"])
		{
			DDLogVerbose(@"SASL CRAM-MD5 is supported");
			_SASLCRAM_MD5=YES;
		}
		
		if([_messageBuffer isEqualToString:@"DIGEST-MD5"])
		{
			DDLogVerbose(@"SASL DIGEST-MD5 is supported");
			_SASLDIGEST_MD5=YES;
		}
        
        _messageBuffer=nil; 
		return;
	}
    
    if( ([elementName isEqualToString:@"mechanisms"]) && ([State isEqualToString:@"Mechanisms"]))
    {
        State =@"Features"; 
    }
}

@end
