//
//  HelperTools.m
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#include <CommonCrypto/CommonDigest.h>
#import "HelperTools.h"
#import "DataLayer.h"

@implementation HelperTools


+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features
{
    // see https://xmpp.org/extensions/xep-0115.html#ver
    NSMutableString* unhashed = [[NSMutableString alloc] init];
    NSData* hashed;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    
    //generate identities string
    for(NSString* identity in identities)
        [unhashed appendString:[NSString stringWithFormat:@"%@<", identity]];
    //append features string
    [unhashed appendString:[self generateStringOfFeatureSet:features]];
    
    NSData *stringBytes = [unhashed dataUsingEncoding: NSUTF8StringEncoding];
    if(CC_SHA1([stringBytes bytes], (UInt32)[stringBytes length], digest))
        hashed = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    NSString* hashedBase64 = [self encodeBase64WithData:hashed];
    
    DDLogVerbose(@"ver string: unhashed %@, hashed %@, hashed-64 %@", unhashed, hashed, hashedBase64);
    return hashedBase64;
}

+(NSString*) getOwnCapsHash
{
    NSString* client = [NSString stringWithFormat:@"client/phone//Monal %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    return [self getEntityCapsHashForIdentities:@[client] andFeatures:[self getOwnFeatureSet]];
}

+(NSSet*) getOwnFeatureSet
{
    static NSSet* featuresSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray* featuresArray = @[
            @"eu.siacs.conversations.axolotl.devicelist+notify",
            @"http://jabber.org/protocol/caps",
            @"http://jabber.org/protocol/disco#info",
            @"http://jabber.org/protocol/disco#items",
            @"http://jabber.org/protocol/muc",
            @"urn:xmpp:jingle:1",
            @"urn:xmpp:jingle:apps:rtp:1",
            @"urn:xmpp:jingle:apps:rtp:audio",
            @"urn:xmpp:jingle:transports:raw-udp:0",
            @"urn:xmpp:jingle:transports:raw-udp:1",
            @"urn:xmpp:receipts",
            @"jabber:x:oob",
            @"urn:xmpp:ping",
            @"urn:xmpp:receipts",
            @"urn:xmpp:idle:1",
            @"http://jabber.org/protocol/chatstates"
        ];
        featuresSet = [[NSSet alloc] initWithArray:featuresArray];
    });
    return featuresSet;
}

+(NSString*) generateStringOfFeatureSet:(NSSet*) features
{
    // this has to be sorted for the features hash to be correct, see https://xmpp.org/extensions/xep-0115.html#ver
    NSArray* featuresArray = [[features allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableString* toreturn = [[NSMutableString alloc] init];
    for(NSString* feature in featuresArray)
    {
        [toreturn appendString:feature];
        [toreturn appendString:@"<"];
    }
    return toreturn;
}

/*
 * create string containing the info when a user was seen the last time
 * return nil if no timestamp was found in the db
 */
+(NSString* _Nullable) formatLastInteraction:(NSDate*) lastInteraction
{
    // get current timestamp
    unsigned long currentTimestamp = [[NSDate date] timeIntervalSince1970];

    unsigned long lastInteractionTime = 0;      //default is zero which corresponds to "online"

    // calculate timestamp and clamp it to be not in the future (but only if given)
    if(lastInteraction && lastInteraction!=[NSNull null])       //NSDictionary does not support nil, so we're using NSNull sometimes
        lastInteractionTime = MIN([lastInteraction timeIntervalSince1970], currentTimestamp);

    if(lastInteractionTime > 0) {
        NSString* timeString;

        unsigned long diff = currentTimestamp - lastInteractionTime;
        if(diff < 60)
        {
            // less than one minute
            timeString = NSLocalizedString(@"Just seen", @"");
        }
        else if(diff < 120)
        {
            // less than two minutes
            timeString = NSLocalizedString(@"Last seen: 1 minute ago", @"");
        }
        else if(diff < 3600)
        {
            // less than one hour
            timeString = NSLocalizedString(@"Last seen: %d minutes ago", @"");
            diff /= 60;
        }
        else if(diff < 7200)
        {
            // less than 2 hours
            timeString = NSLocalizedString(@"Last seen: 1 hour ago", @"");
        }
        else if(diff < 86400)
        {
            // less than 24 hours
            timeString = NSLocalizedString(@"Last seen: %d hours ago", @"");
            diff /= 3600;
        }
        else if(diff < 86400 * 2)
        {
            // less than 2 days
            timeString = NSLocalizedString(@"Last seen: 1 day ago", @"");
        }
        else
        {
            // more than 2 days
            timeString = NSLocalizedString(@"Last seen: %d days ago", @"");
            diff /= 86400;
        }

        NSString* lastSeen = [NSString stringWithFormat:timeString, diff];
        return [NSString stringWithFormat:@"%@", lastSeen];
    } else {
        return NSLocalizedString(@"Online", @"");
    }
}

+(NSDate*) parseDateTimeString:(NSString*) datetime
{
    static NSDateFormatter* rfc3339DateFormatter;
    static NSDateFormatter* rfc3339DateFormatter2;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        rfc3339DateFormatter2 = [[NSDateFormatter alloc] init];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSSSSXXXXX"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        
        [rfc3339DateFormatter2 setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter2 setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        [rfc3339DateFormatter2 setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"];
    });
    
    NSDate* retval = [rfc3339DateFormatter dateFromString:datetime];
    if(!retval)
        retval = [rfc3339DateFormatter2 dateFromString:datetime];
    return retval;
}

+(NSString*) generateDateTimeString:(NSDate*) datetime
{
    static NSDateFormatter* rfc3339DateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        NSDateFormatter* rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    });
    
    return [rfc3339DateFormatter stringFromDate:datetime];
}

+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler
{
    return [self startTimer:timeout withHandler:handler andCancelHandler:nil];
}

+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t) cancelHandler
{
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    if(timeout<=0.001)
    {
        DDLogWarn(@"Timer timeout is smaller than 0.001, dispatching handler directly.");
        if(handler)
            dispatch_async(q_background, ^{
                handler();
            });
        return ^{ };        //empty cancel block because this "timer" already triggered
    }
    
    NSString* uuid = [[NSUUID UUID] UUIDString];
    
    //DDLogDebug(@"setting up timer %@(%G)", uuid, timeout);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q_background);
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout*NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              0ull * NSEC_PER_SEC);
    
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
    NSString* resource=[NSString stringWithFormat:@"Monal-iOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#else
    NSString* resource=[NSString stringWithFormat:@"Monal-macOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#endif
    return resource;
}

#pragma mark  Base64

+(NSString*) encodeBase64WithString:(NSString*) strData
{
    NSData *data =[strData dataUsingEncoding:NSUTF8StringEncoding];
    return [self encodeBase64WithData:data];
}

+(NSString*) encodeBase64WithData:(NSData*) objData
{
   return [objData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
}

+(NSData*) dataWithBase64EncodedString:(NSString*) string
{
    return [[NSData alloc] initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
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
    NSString *hex = [self hexadecimalString:data];
    
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
