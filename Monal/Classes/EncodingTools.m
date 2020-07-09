//
//  EncodingTools.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#include <CommonCrypto/CommonDigest.h>
#import "EncodingTools.h"
@import os.log;

@implementation EncodingTools


+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler
{
    return [self startTimer:timeout withHandler:handler andCancelHandler:nil];
}

+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t) cancelHandler
{
    if(timeout<=0.001)
    {
        DDLogWarn(@"Timer timeout is smaller than 0.001, calling handler directly.");
        if(handler)
            handler();
        return ^{ };        //empty cancel block because this "timer" already triggered
    }
    
    NSString* uuid = [[NSUUID UUID] UUIDString];
    
    DDLogDebug(@"setting up timer %@(%G)", uuid, timeout);
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q_background);
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout*NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        DDLogDebug(@"timer %@ %@(%G) triggered", timer, uuid, timeout);
        dispatch_source_cancel(timer);
        if(handler)
            handler();
    });
    
    dispatch_source_set_cancel_handler(timer, ^{
        //DDLogDebug(@"timer %@ %@(%G) cancelled", timer, uuid, timeout);
        if(cancelHandler)
            cancelHandler();
    });
    
    //start timer
    DDLogDebug(@"starting timer %@ %@(%G)", timer, uuid, timeout);
    dispatch_resume(timer);
    
    //return block that can be used to cancel the timer
    return ^{
        DDLogDebug(@"cancel block for timer %@ %@(%G) called", timer, uuid, timeout);
        if(!dispatch_source_testcancel(timer))
            dispatch_source_cancel(timer);
    };
}

+(NSString*) encodeRandomResource
{
    u_int32_t i=arc4random();
#if TARGET_OS_IPHONE
    NSString* resource=[NSString stringWithFormat:@"Monal-iOS.%@", [EncodingTools hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#else
    NSString* resource=[NSString stringWithFormat:@"Monal-macOS.%@", [EncodingTools hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#endif
    return resource;
}

#pragma mark  Bae64

+(NSString*) encodeBase64WithString:(NSString*) strData
{
    NSData *data =[strData dataUsingEncoding:NSUTF8StringEncoding];
    return [EncodingTools encodeBase64WithData:data];
}

+(NSString*) encodeBase64WithData:(NSData*) objData
{
   return [objData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
}

+(NSData*) dataWithBase64EncodedString:(NSString*) string
{
    return [[NSData alloc] initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

#pragma mark MD5

+(NSData*) MD5:(NSString*) string
{
    
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


+ (NSData *)dataWithHexString:(NSString *)hex
{
    char buf[3];
    buf[2] = '\0';
    
    if( [hex length] % 2 !=00) {
        NSLog(@"Hex strings should have an even number of digits");
        return nil;
    }
    unsigned char *bytes = malloc([hex length]/2);
    unsigned char *bp = bytes;
    for (CFIndex i = 0; i < [hex length]; i += 2) {
        buf[0] = [hex characterAtIndex:i];
        buf[1] = [hex characterAtIndex:i+1];
        char *b2 = NULL;
        *bp++ = strtol(buf, &b2, 16);
        if(b2 != buf + 2) {
            NSLog(@"String should be all hex digits");;
            return nil;
        }
    }
    
    return [NSData dataWithBytesNoCopy:bytes length:[hex length]/2 freeWhenDone:YES];
}


+ (NSString *)signalHexKeyWithData:(NSData*) data
{
    NSString *hex = [EncodingTools hexadecimalString:data];
    
    //remove 05 cipher info
    hex = [hex substringWithRange:NSMakeRange(2, hex.length-2)];
    NSMutableString *output = [hex mutableCopy];
   
    int counter =0;
    while(counter<= hex.length)
    {
        counter+=8;
        [output insertString:@" " atIndex:counter];
        counter++;
       
    }
    
    return output.uppercaseString;
}


@end
