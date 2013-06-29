//
//  ParseStream.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "ParseStream.h"

@implementation ParseStream


- (id) initWithDictionary:(NSDictionary*) dictionary
{
    self=[super init];
    
    NSData* stanzaData= [[dictionary objectForKey:@"stanzaString"] dataUsingEncoding:NSUTF8StringEncoding];
	
    //xml parsing
	NSXMLParser* parser = [[NSXMLParser alloc] initWithData:stanzaData];
	[parser setShouldProcessNamespaces:NO];
    [parser setShouldReportNamespacePrefixes:NO];
    [parser setShouldResolveExternalEntities:NO];
	[parser setDelegate:self];
	
	[parser parse];
    
    return  self;
    
}

#pragma mark NSXMLParser delegate

- (void)parserDidStartDocument:(NSXMLParser *)parser{
	debug_NSLog(@"parsing");
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{
    debug_NSLog(@"began this element: %@", elementName);
    
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
		return;
	}
    
    
	if(([elementName isEqualToString:@"proceed"]) && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-tls"]) )
	{
		debug_NSLog(@"Got SartTLS procced");
		//trying to switch to TLS
        
        _startTLSProceed=YES;
        
		
//		NSDictionary *settings = [ [NSDictionary alloc ]
//								  initWithObjectsAndKeys:
//								  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
//								  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
//								  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
//                                  [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
//								  [NSNull null],kCFStreamSSLPeerName,
//                                  
//                                  kCFStreamSocketSecurityLevelSSLv3,
//                                  kCFStreamSSLLevel,
//                                  
//								  
//								  nil ];
//        
//		
//		
//        
//		if ( 	CFReadStreamSetProperty((__bridge CFReadStreamRef)iStream,
//										@"kCFStreamPropertySSLSettings", (__bridge CFTypeRef)settings) &&
//			CFWriteStreamSetProperty((__bridge CFWriteStreamRef)oStream,
//									 @"kCFStreamPropertySSLSettings", (__bridge CFTypeRef)settings)	 )
//			
//		{
//			debug_NSLog(@"Set TLS properties on streams.");
//			
//			
//		}
//		else
//		{
//			debug_NSLog(@"not sure.. Could not confirm Set TLS properties on streams.");
//			//fatal=true;
//		}
//		
//		
//        
//		
//		
//		NSString* xmpprequest;
//        if([domain length]>0)
//            
//            xmpprequest=[NSString stringWithFormat:
//                         @"<stream:stream to='%@' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>",domain];
//        else
//            xmpprequest=[NSString stringWithFormat:
//                         @"<stream:stream  xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>"];
//        
//		[self talk:xmpprequest];
//		loginstate=1; // reset everything
//		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(login:) name: @"XMPPMech" object:self];
//		
		return;
		
	}
    
	// state >1 at the end of sasl and then reset to 1 in bind. so if it is 1 then bind was already sent
//	if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"bind"])
//	   && (loginstate!=1) )
//	{
//		loginstate=1; //reset for new stream
//        
//        debug_NSLog(@"%@", self.sessionKey);
//        NSString* bindString=[NSString stringWithFormat:@"<iq id='%@' type='set' ><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><resource>%@</resource></bind></iq>", _sessionKey,resource];
//		[self talk:bindString];
//		
//        ;
//		return;
//    }
//	
//	
//    
//	
//	
//    
//	// first time it is read loginstate  will always be 1
//	
//	if(([State isEqualToString:@"Features"]) && [elementName isEqualToString:@"mechanisms"] && (loginstate<2))
//	{
//		loginstate++;
//		debug_NSLog(@"mechanisms xmlns:%@ ", [attributeDict objectForKey:@"xmlns"]);
//		if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
//		{
//			debug_NSLog(@"SASL supported");
//			SASLSupported=true;
//		}
//		
//		State=@"Mechanisms";
//		
//		;
//		return;
//		
//        
//	}
//	
//	if(([State isEqualToString:@"Mechanisms"]) && [elementName isEqualToString:@"mechanism"])
//	{
//		debug_NSLog(@"Reading mechanism"); 
//		State=@"Mechanism";
//		
//		;
//		return;
//		
//		
//	}
//	
	
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    
}


- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
	debug_NSLog(@"foudn ignorable whitespace: %@", whitespaceString);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	debug_NSLog(@"Error: line: %d , col: %d desc: %@ ",[parser lineNumber],
                [parser columnNumber], [parseError localizedDescription]);
	
   
}

@end
