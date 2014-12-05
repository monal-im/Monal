//
//  ParsePresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/6/13.
//
//

#import "ParsePresence.h"

static const int ddLogLevel = LOG_LEVEL_INFO;

@implementation ParsePresence


- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    if([elementName isEqualToString:@"presence"])
    {
        [super parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
        DDLogVerbose(@"Presence from %@", _user);
		DDLogVerbose(@"Presence type %@", _type);
        
        if([_type isEqualToString:@"error"])
		{
            //we are done, parse next element
            return;
			
		}
    }
    
    if([elementName isEqualToString:@"show"])
    {
        _messageBuffer=nil;
    }
    
    if(self.MUC) {
        if([elementName isEqualToString:@"status"])
        {
            if(!self.statusCodes) self.statusCodes=[[NSMutableArray alloc] init];
            NSString * code= [attributeDict objectForKey:@"code"];
            if(code) {
                [self.statusCodes addObject:[attributeDict objectForKey:@"code"]];
            }
        }
    }
    else {
        if([elementName isEqualToString:@"status"])
        {
            _messageBuffer=nil;
        }
    }
    
    NSString *namespace = nil;
    NSArray *parts =[elementName componentsSeparatedByString:@":"];
    if([parts count]>1) {
     namespace=[NSString stringWithFormat:@"%@",[parts objectAtIndex:0]];
    } else
    {
        namespace =@"";
    }
    
    if([elementName isEqualToString:[NSString stringWithFormat:@"%@:x",namespace]] || [elementName isEqualToString:@"x"] )
    {
        if([[attributeDict objectForKey:[NSString stringWithFormat:@"xmlns:%@",namespace]] isEqualToString:@"http://jabber.org/protocol/muc#user"]
           || [[attributeDict objectForKey:@"xmlns" ] isEqualToString:@"http://jabber.org/protocol/muc#user"])
        {
            self.MUC=YES;
            return;
        }
    }
    
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if(_messageBuffer)
    {
        if([elementName isEqualToString:@"show"])
        {
            _show=_messageBuffer;
            if(_show==nil)
                _show=@"";
            
        }
        
        
        if([elementName isEqualToString:@"status"])
        {
            _status=_messageBuffer;
            if(_status==nil)
                _status=@"";
            
            
        }
        
        
        if([elementName isEqualToString:@"photo"])
        {
            _photoHash=_messageBuffer;
            if(!_photoHash)
                _photoHash=@"";
        }
    }
}

@end
