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
@property (nonatomic, assign, readonly) BOOL discoItems;
@property (nonatomic, assign, readonly) BOOL roster;
@property (nonatomic, assign, readonly) BOOL ping;
@property (nonatomic, assign, readonly) BOOL legacyAuth;

@property (nonatomic, assign, readonly) BOOL shouldSetBind;
@property (nonatomic, strong, readonly) NSString* jid;

@property (nonatomic, strong, readonly) NSString* queryXMLNS;
@property (nonatomic, strong, readonly) NSString* queryNode;
@property (nonatomic, strong, readonly) NSMutableSet* features;
@property (nonatomic, strong, readonly) NSMutableArray* items;

// vcard releated

@property (nonatomic, assign, readonly) BOOL vCard;
@property (nonatomic, strong, readonly) NSString* fullName;
@property (nonatomic, strong, readonly) NSString* URL;
@property (nonatomic, strong, readonly) NSString* photoType;
@property (nonatomic, strong, readonly) NSString* photoBinValue;


//Misc requests
@property (nonatomic, assign, readonly) BOOL time;
@property (nonatomic, assign, readonly) BOOL version;
@property (nonatomic, assign, readonly) BOOL last;

//discovered services
@property (nonatomic, strong, readonly) NSString* conferenceServer;

//Jingle
@property (nonatomic, strong, readonly) NSDictionary* jingleSession;
@property (nonatomic, strong, readonly) NSMutableArray* jinglePayloadTypes;
@property (nonatomic, strong, readonly) NSMutableArray* jingleTransportCandidates;

@end
