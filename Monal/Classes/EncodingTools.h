//
//  EncodingTools.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>

@interface EncodingTools : NSObject

+ (NSString *)encodeBase64WithString:(NSString *)strData;
+ (NSString *)encodeBase64WithData:(NSData *)objData;
+ (NSData*) dataWithBase64EncodedString:(NSString *)string;

+ (NSData *) MD5:(NSString*)string ;
+ (NSData *) DataMD5:(NSData*)datain;
+ (NSString *)hexadecimalString:(NSData*) data;

@end
