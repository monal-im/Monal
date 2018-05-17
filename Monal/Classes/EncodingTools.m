//
//  EncodingTools.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#include <CommonCrypto/CommonDigest.h>
#import "EncodingTools.h"


@implementation EncodingTools

#pragma mark  Bae64


+ (NSString *)encodeBase64WithString:(NSString *)strData {
    
    NSData *data =[strData dataUsingEncoding:NSUTF8StringEncoding];
    
    return [data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    
}

+ (NSData*) dataWithBase64EncodedString:(NSString *)string
{
    return [[NSData alloc] initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
}


#pragma mark MD5

+ (NSData *) MD5:(NSString*)string {
    
    const char *cStr = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, strlen(cStr), result);
    /* NSString* toreturn= [NSString stringWithFormat: @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
     result[0], result[1], result[2], result[3],
     result[4], result[5], result[6], result[7],
     result[8], result[9], result[10], result[11],
     result[12], result[13], result[14], result[15]];
     
     DDLogVerbose(@" hash: %@ => %@",string, toreturn );
     */
    
    int size=sizeof(unsigned char)*CC_MD5_DIGEST_LENGTH;
    //  DDLogVerbose(@" hash: %s size:%d", result,size);
    
    NSData* data =[[NSData  alloc ] initWithBytes: (const void *)result length:size];
    
    
    return data;
}

+ (NSData *) DataMD5:(NSData*)datain {
    
    const char *cStr = [datain bytes];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, [datain length], result);
    /* NSString* toreturn= [NSString stringWithFormat: @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
     result[0], result[1], result[2], result[3],
     result[4], result[5], result[6], result[7],
     result[8], result[9], result[10], result[11],
     result[12], result[13], result[14], result[15]];
     */
    // DDLogVerbose(@"data %s hash: %s",cStr, result );
    
    int size=sizeof(unsigned char)*CC_MD5_DIGEST_LENGTH;
    NSData* data =[NSData dataWithBytes:result length:size];
    
    
    return data;
}


+ (NSString *)hexadecimalString:(NSData*) data
{
    /* Returns hexadecimal string of NSData. Empty string if data is empty.   */
    
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
    
    if (!dataBuffer)
        return [NSString string];
    
    NSUInteger          dataLength  = [data length];
    NSMutableString     *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (int i = 0; i < dataLength; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02x", (unsigned int)dataBuffer[i]]];
    
    return [NSString stringWithString:hexString];
}



@end
