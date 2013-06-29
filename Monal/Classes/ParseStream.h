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
}


@property (nonatomic,readonly, assign) BOOL supportsLegacyAuth;
@property (nonatomic,readonly, assign) BOOL supportsUserReg;

@property (nonatomic,readonly, assign) BOOL callStartTLS;
@property (nonatomic,readonly, assign) BOOL startTLSProceed;

@property (nonatomic,readonly, assign) BOOL error;


- (id) initWithDictionary:(NSDictionary*) dictionary;
@end
