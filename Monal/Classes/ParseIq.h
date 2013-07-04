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

@property (nonatomic, assign) BOOL shouldSetBind;
@property (nonatomic, strong) NSString* jid;


@end
