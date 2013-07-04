//
//  XMPPParser.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPParser.h"

@implementation XMPPParser

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

@end
