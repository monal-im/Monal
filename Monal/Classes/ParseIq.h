//
//  ParseIq.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>
#import "XMPPParser.h"
#import "XMPPIQ.h" // for the constants

@interface ParseIq : XMPPParser
{
    
}

@property (nonatomic, assign, readonly) BOOL discoInfo;

@property (nonatomic, assign, readonly) BOOL shouldSetBind;
@property (nonatomic, strong, readonly) NSString* jid;

@property (nonatomic, strong, readonly) NSString* queryXMLNS;
@property (nonatomic, strong, readonly) NSMutableArray* features;

// vcard releated

@property (nonatomic, assign, readonly) BOOL vCard;
@property (nonatomic, strong, readonly) NSString* fullName;
@property (nonatomic, strong, readonly) NSString* URL;
@property (nonatomic, strong, readonly) NSString* photoType;
@property (nonatomic, strong, readonly) NSString* photoBinValue;

@end
