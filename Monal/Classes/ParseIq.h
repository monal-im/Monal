//
//  ParseIq.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>
#import "XMPPParser.h"
#import "MLXMPPConstants.h" 

@interface ParseIq : XMPPParser
{
    
}

@property (nonatomic, assign, readonly) BOOL discoInfo;
@property (nonatomic, assign, readonly) BOOL discoItems;
@property (nonatomic, assign, readonly) BOOL roster;
@property (nonatomic, assign, readonly) BOOL ping;
@property (nonatomic, assign, readonly) BOOL legacyAuth;
@property (nonatomic, assign, readonly) BOOL httpUpload;
@property (nonatomic, assign, readonly) BOOL registration;

@property (nonatomic, assign, readonly) BOOL shouldSetBind;
@property (nonatomic, strong, readonly) NSString* jid;

@property (nonatomic, strong, readonly) NSString* queryXMLNS;
@property (nonatomic, strong, readonly) NSString* queryNode;
@property (nonatomic, strong, readonly) NSMutableSet* features;
@property (nonatomic, strong, readonly) NSMutableArray* items;
@property (nonatomic, strong, readonly) NSString* errorMessage;

// vcard releated

@property (nonatomic, assign, readonly) BOOL vCard;
@property (nonatomic, strong, readonly) NSString* fullName;
@property (nonatomic, strong, readonly) NSString* URL;
@property (nonatomic, strong, readonly) NSString* photoType;
@property (nonatomic, strong, readonly) NSString* photoBinValue;


//http upload
@property (nonatomic, strong, readonly) NSString* getURL;
@property (nonatomic, strong, readonly) NSString* putURL;

//Misc requests
@property (nonatomic, assign, readonly) BOOL version;
@property (nonatomic, assign, readonly) BOOL last;


//Jingle
@property (nonatomic, strong, readonly) NSDictionary* jingleSession;
@property (nonatomic, strong, readonly) NSMutableArray* jinglePayloadTypes;
@property (nonatomic, strong, readonly) NSMutableArray* jingleTransportCandidates;

//mam2
@property (nonatomic, strong, readonly) NSString* mam2default;
@property (nonatomic, assign, readonly) BOOL mam2fin;
@property (nonatomic, strong, readonly) NSString* mam2Last;

//omemo
@property (nonatomic, strong, readonly) NSMutableArray* preKeys; //Array with dic of signalprekey, key id
@property (nonatomic, strong, readonly) NSString* signedPreKeyPublic;
@property (nonatomic, strong, readonly) NSString* signedPreKeyId;
@property (nonatomic, strong, readonly) NSString* signedPreKeySignature;
@property (nonatomic, strong, readonly) NSString* identityKey;
@property (nonatomic, strong, readonly) NSString* deviceid; //sending device id
@property (nonatomic, strong, readonly) NSMutableArray* omemoDevices; //array of device ids

//registration
@property (nonatomic, strong, readonly) NSData* captchaData;
@property (nonatomic, strong) NSMutableDictionary *hiddenFormFields;

//Roster
@property (nonatomic, strong, readonly) NSString* rosterVersion;

@end
