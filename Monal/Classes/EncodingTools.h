//
//  EncodingTools.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

@interface EncodingTools : NSObject

+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t) cancelHandler;
+(NSString*) encodeRandomResource;
+(NSString*) encodeBase64WithString:(NSString*) strData;
+(NSString*) encodeBase64WithData:(NSData*) objData;
+(NSData*) dataWithBase64EncodedString:(NSString*) string;

+(NSData *) MD5:(NSString*)string ;
+ (NSData *) DataMD5:(NSData*)datain;
+ (NSString *)hexadecimalString:(NSData*) data;
+ (NSData *)dataWithHexString:(NSString *)hex;
+ (NSString *)signalHexKeyWithData:(NSData*) data;

@end
