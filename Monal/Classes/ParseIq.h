//
//  ParseIq.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>
#import "XMPPParser.h"

@interface ParseIq : XMPPParser
{
    
}

@property (nonatomic, assign, readonly) BOOL shouldSetBind;
@property (nonatomic, strong, readonly) NSString* jid;

@property (nonatomic, strong, readonly) NSString* queryXMLNS;
@property (nonatomic, strong, readonly) NSMutableArray* features;

@end
