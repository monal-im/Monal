//
//  ParseStream.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>

@interface ParseStream : NSObject <NSXMLParserDelegate>
{
    NSString* State;
    NSString* _messageBuffer; 
}


@property (nonatomic,readonly, assign) BOOL supportsLegacyAuth;
@property (nonatomic,readonly, assign) BOOL supportsUserReg;

//Auth mechanisms
@property (nonatomic,readonly, assign) BOOL supportsSASL;
@property (nonatomic,readonly, assign) BOOL SASLPlain;
@property (nonatomic,readonly, assign) BOOL SASLCRAM_MD5;
@property (nonatomic,readonly, assign) BOOL SASLDIGEST_MD5;

// xmpp state
@property (nonatomic,readonly, assign) BOOL callStartTLS;
@property (nonatomic,readonly, assign) BOOL startTLSProceed;

@property (nonatomic,readonly, assign) BOOL error;




- (id) initWithDictionary:(NSDictionary*) dictionary;
@end
