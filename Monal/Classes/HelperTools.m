//
//  HelperTools.m
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#include <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import "HelperTools.h"
#import "MLXMPPManager.h"
#import "MLPubSub.h"
#import "MLUDPLogger.h"
#import "XMPPStanza.h"
#import "xmpp.h"

@import UserNotifications;
@import CoreImage;
@import CoreImage.CIFilterBuiltins;

static DDFileLogger* _fileLogger;

@implementation HelperTools

void logException(NSException* exception)
{
    [DDLog flushLog];
    DDLogError(@"*****************\nCRASH(%@): %@\nUserInfo: %@\nStack Trace: %@", [exception name], [exception reason], [exception userInfo], [exception callStackSymbols]);
    [DDLog flushLog];
    usleep(1000000);
}

+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere
{
    NSString* message;
    if(node)
        message = [HelperTools extractXMPPError:node withDescription:description];
    else
        message = description;
    [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:account userInfo:@{@"message": message, @"isSevere":@(isSevere)}];
}

+(NSDictionary*) pushServer
{
    if (@available(iOS 13.0, *))        // for ios 13 onwards
        return @{
            @"jid": @"ios13push.monal.im",
        };
    else                                // for ios 12
        return @{
            @"jid": @"push.monal.im",
        };
}

+(NSString*) stringFromToken:(NSData*) tokenIn
{
    unsigned char* tokenBytes = (unsigned char*)[tokenIn bytes];
    NSMutableString* token = [[NSMutableString alloc] init];
    NSInteger counter = 0;
    while(counter < tokenIn.length)
    {
        [token appendString:[NSString stringWithFormat:@"%02x", (unsigned char)tokenBytes[counter]]];
        counter++;
    }
    return token;
}

+(NSString*) extractXMPPError:(XMPPStanza*) stanza withDescription:(NSString*) description
{
    if(description == nil || [description isEqualToString:@""])
        description = @"XMPP Error";
    NSString* errorReason = [stanza findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"];
    NSString* errorText = [stanza findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"];
    NSString* message = [NSString stringWithFormat:@"%@: %@", description, errorReason];
    if(errorText && ![errorText isEqualToString:@""])
        message = [NSString stringWithFormat:@"%@: %@ (%@)", description, errorReason, errorText];
    return message;
}

+(void) configureFileProtectionFor:(NSString*) file
{
#if TARGET_OS_IPHONE
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:file])
    {
        //DDLogVerbose(@"protecting file '%@'...", file);
        NSError* error;
        [fileManager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:file error:&error];
        if(error)
        {
            DDLogError(@"Error configuring file protection level for: %@", file);
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
        }
        else
            ;//DDLogVerbose(@"file '%@' now protected", file);
    }
    else
        ;//DDLogVerbose(@"file '%@' does not exist!", file);
#endif
}

+(NSDictionary<NSString*, NSString*>*) splitJid:(NSString*) jid
{
    NSMutableDictionary<NSString*, NSString*>* retval = [[NSMutableDictionary alloc] init];
    NSArray* parts = [jid componentsSeparatedByString:@"/"];
    
    retval[@"user"] = [[parts objectAtIndex:0] lowercaseString];        //intended to not break code that expects lowercase
    if([parts count]>1 && ![[parts objectAtIndex:1] isEqualToString:@""])
        retval[@"resource"] = [parts objectAtIndex:1];                  //resources are case sensitive
    parts = [retval[@"user"] componentsSeparatedByString:@"@"];
    if([parts count]>1)
    {
        retval[@"node"] = [[parts objectAtIndex:0] lowercaseString];    //intended to not break code that expects lowercase
        retval[@"host"] = [[parts objectAtIndex:1] lowercaseString];    //intended to not break code that expects lowercase
    }
    else
        retval[@"host"] = [[parts objectAtIndex:0] lowercaseString];    //intended to not break code that expects lowercase
    
    //log sanity check errors
    if([retval[@"host"] isEqualToString:@""])
        DDLogError(@"jid '%@' has no host part!", jid);
    
    return retval;
}

+(void) updateSyncErrorsWithDeleteOnly:(BOOL) removeOnly
{
    @synchronized(self) {
        NSMutableDictionary* syncErrorsDisplayed = [NSMutableDictionary dictionaryWithDictionary:[[HelperTools defaultsDB] objectForKey:@"syncErrorsDisplayed"]];
        DDLogInfo(@"Updating syncError notifications: %@", syncErrorsDisplayed);
        for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
        {
            NSString* syncErrorIdentifier = [NSString stringWithFormat:@"syncError::%@", account.connectionProperties.identity.jid];
            if(account.idle)
            {
                DDLogInfo(@"Removing syncError notification for %@ (now synced)...", account.connectionProperties.identity.jid);
                [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[syncErrorIdentifier]];
                syncErrorsDisplayed[account.connectionProperties.identity.jid] = @NO;
                [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
            }
            else if(!removeOnly)
            {
                if([syncErrorsDisplayed[account.connectionProperties.identity.jid] boolValue])
                {
                    DDLogWarn(@"NOT posting syncError notification for %@ (already did so since last app foreground)...", account.connectionProperties.identity.jid);
                    continue;
                }
                DDLogWarn(@"Posting syncError notification for %@...", account.connectionProperties.identity.jid);
                UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
                content.title = NSLocalizedString(@"Could not synchronize", @"");
                content.subtitle = account.connectionProperties.identity.jid;
                content.body = NSLocalizedString(@"Please open the app to retry", @"");
                content.sound = [UNNotificationSound defaultSound];
                content.categoryIdentifier = @"simple";
                UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
                UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:syncErrorIdentifier content:content trigger:nil];
                [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                    if(error)
                        DDLogError(@"Error posting syncError notification: %@", error);
                    else
                    {
                        syncErrorsDisplayed[account.connectionProperties.identity.jid] = @YES;
                        [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
                    }
                }];
            }
        }
    }
}

+(BOOL) isInBackground
{
    __block BOOL inBackground = NO;
    if([HelperTools isAppExtension])
        inBackground = YES;
    else
        inBackground = [[MLXMPPManager sharedInstance] isBackgrounded];
    /*
    {
        [HelperTools dispatchSyncReentrant:^{
            if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
                inBackground = YES;
        } onQueue:dispatch_get_main_queue()];
    }
    */
    return inBackground;
}

+(BOOL) isNotInFocus
{
    __block BOOL isNotInFocus = NO;
    isNotInFocus |= [HelperTools isAppExtension];
    isNotInFocus |= [[MLXMPPManager sharedInstance] isBackgrounded];
    isNotInFocus |= [[MLXMPPManager sharedInstance] isNotInFocus];

    return isNotInFocus;
}

+(void) dispatchSyncReentrant:(monal_void_block_t) block onQueue:(dispatch_queue_t) queue
{
    if(!queue)
        queue = dispatch_get_main_queue();
    
    //apple docs say that enqueueing blocks for synchronous execution will execute this blocks in the thread the enqueueing came from
    //(e.g. the tread we are already in).
    //so when dispatching synchronously from main queue/thread to some "other queue" and from that queue back to the main queue this means:
    //the block queued for execution in the "other queue" will be executed in the main thread
    //this holds true even if multiple synchronous queues sit in between the main thread and this dispatchSyncReentrant:onQueue:(main_queue) call
    
    //directly call block:
    //IF: the destination queue is equal to our current queue
    //OR IF: the destination queue is the main queue and we are already in the main thread (but not the main queue)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    dispatch_queue_t current_queue = dispatch_get_current_queue();
#pragma clang diagnostic pop
    if(current_queue == queue || (queue == dispatch_get_main_queue() && [NSThread isMainThread]))
        block();
    else
        dispatch_sync(queue, block);
}

+(void) activityLog
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        BOOL appex = [HelperTools isAppExtension];
        unsigned long counter = 1;
        while(counter++)
        {
            DDLogInfo(@"activity(%@): %lu", appex ? @"APPEX" : @"MAINAPP", counter);
            [NSThread sleepForTimeInterval:1];
        }
    });
}

+(NSUserDefaults*) defaultsDB
{
    static NSUserDefaults* db;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        db = [[NSUserDefaults alloc] initWithSuiteName:kAppGroup];
    });
    return db;
}

+(DDFileLogger*) fileLogger
{
    return _fileLogger;
}

+(void) setFileLogger:(DDFileLogger*) fileLogger
{
    _fileLogger = fileLogger;
}

+(void) configureLogging
{
    //create log formatter
    MLLogFormatter* formatter = [[MLLogFormatter alloc] init];
    
    //console logger (this one will *not* log own additional (and duplicated) informations like DDOSLogger would)
#ifdef TARGET_IPHONE_SIMULATOR
    [[DDTTYLogger sharedInstance] setLogFormatter:formatter];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
#else
    [[DDOSLogger sharedInstance] setLogFormatter:formatter];
    [DDLog addLogger:[DDOSLogger sharedInstance]];
#endif
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    DDLogInfo(@"Logfile dir: %@", [containerUrl path]);
    
    //file logger
    id<DDLogFileManager> logFileManager = [[MLLogFileManager alloc] initWithLogsDirectory:[containerUrl path]];
    self.fileLogger = [[DDFileLogger alloc] initWithLogFileManager:logFileManager];
    [self.fileLogger setLogFormatter:formatter];
    self.fileLogger.rollingFrequency = 60 * 60 * 24;    // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3;
    self.fileLogger.maximumFileSize = 1024 * 1024 * 64;
    [DDLog addLogger:self.fileLogger];
    
    //network logger
    MLUDPLogger* udpLogger = [[MLUDPLogger alloc] init];
    [udpLogger setLogFormatter:formatter];
    [DDLog addLogger:udpLogger];
    
    //log version info as early as possible
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    DDLogInfo(@"Starting: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
    [DDLog flushLog];
    
    //for debugging when upgrading the app
    NSArray* directoryContents = [fileManager contentsOfDirectoryAtPath:[containerUrl path] error:nil];
    for(NSString* file in directoryContents)
        DDLogVerbose(@"File %@/%@", [containerUrl path], file);
}

+(BOOL) isAppExtension
{
    //dispatch once seems to corrupt this check (nearly always return mainapp even if in appex) --> don't use dispatch once
    return [[[NSBundle mainBundle] executablePath] containsString:@".appex/"];
}

+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features
{
    // see https://xmpp.org/extensions/xep-0115.html#ver
    NSMutableString* unhashed = [[NSMutableString alloc] init];
    
    //generate identities string
    for(NSString* identity in identities)
        [unhashed appendString:[NSString stringWithFormat:@"%@<", identity]];
    
    //append features string
    [unhashed appendString:[self generateStringOfFeatureSet:features]];
    
    NSString* hashedBase64 = [self encodeBase64WithData:[self sha1:[unhashed dataUsingEncoding:NSUTF8StringEncoding]]];
    DDLogVerbose(@"ver string: unhashed %@, hashed-64 %@", unhashed, hashedBase64);
    return hashedBase64;
}

+(NSSet*) getOwnFeatureSet
{
    static NSSet* featuresSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray* featuresArray = @[
            @"http://jabber.org/protocol/caps",
            @"http://jabber.org/protocol/disco#info",
            @"http://jabber.org/protocol/disco#items",
            @"http://jabber.org/protocol/muc",
            @"urn:xmpp:jingle:1",
            @"urn:xmpp:jingle:apps:rtp:1",
            @"urn:xmpp:jingle:apps:rtp:audio",
            @"urn:xmpp:jingle:transports:raw-udp:0",
            @"urn:xmpp:jingle:transports:raw-udp:1",
            @"jabber:x:oob",
            @"urn:xmpp:ping",
            @"urn:xmpp:receipts",
            @"urn:xmpp:idle:1",
            @"http://jabber.org/protocol/chatstates",
            @"jabber:iq:version",
            @"urn:xmpp:chat-markers:0"
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
    if(lastInteraction && [lastInteraction timeIntervalSince1970] != 0)       //NSDictionary does not support nil, so we're using timeSince1970 + 0 sometimes
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
        rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    });
    
    return [rfc3339DateFormatter stringFromDate:datetime];
}

+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    return [self startTimer:timeout withHandler:handler andCancelHandler:nil andFile:file andLine:line andFunc:func];
}

+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    NSString* fileStr = [NSString stringWithFormat:@"%s", file];
    NSString* funcStr = [NSString stringWithFormat:@"%s", func];
    NSArray* filePathComponents = [fileStr pathComponents];
    NSString* fileName = fileStr;
    if([filePathComponents count]>1)
        fileName = [NSString stringWithFormat:@"%@/%@", filePathComponents[[filePathComponents count]-2], filePathComponents[[filePathComponents count]-1]];
    
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    if(timeout<=0.001)
    {
        //DDLogVerbose(@"Timer timeout is smaller than 0.001, dispatching handler directly.");
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
        DDLogDebug(@"timer %@ %@(%G) triggered (created at %@:%d in %@)", timer, uuid, timeout, fileName, line, funcStr);
        dispatch_source_cancel(timer);
        if(handler)
            handler();
    });
    
    dispatch_source_set_cancel_handler(timer, ^{
        //DDLogDebug(@"timer %@ %@(%G) cancelled (created at %@:%d)", timer, uuid, timeout, fileName, line);
        if(cancelHandler)
            cancelHandler();
    });
    
    //start timer
    DDLogDebug(@"starting timer %@ %@(%G) (created at %@:%d in %@)", timer, uuid, timeout, fileName, line, funcStr);
    dispatch_resume(timer);
    
    //return block that can be used to cancel the timer
    return ^{
        DDLogDebug(@"cancel block for timer %@ %@(%G) called (created at %@:%d in %@)", timer, uuid, timeout, fileName, line, funcStr);
        if(!dispatch_source_testcancel(timer))
            dispatch_source_cancel(timer);
    };
}

+(NSString*) encodeRandomResource
{
    u_int32_t i=arc4random();
#if TARGET_OS_MACCATALYST
    NSString* resource=[NSString stringWithFormat:@"Monal-macOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#else
    NSString* resource=[NSString stringWithFormat:@"Monal-iOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#endif
    return resource;
}

#pragma mark Hashes

+(NSData*) sha1:(NSData*) data
{
    if(!data)
        return nil;
    NSData* hashed;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    if(CC_SHA1([data bytes], (UInt32)[data length], digest))
        hashed = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    return hashed;
}

+(NSString*) stringSha1:(NSString*) data
{
    return [self hexadecimalString:[self sha1:[data dataUsingEncoding:NSUTF8StringEncoding]]];
}

+(NSData*) sha256:(NSData*) data
{
    if(!data)
        return nil;
    NSData* hashed;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if(CC_SHA256([data bytes], (UInt32)[data length], digest))
        hashed = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return hashed;
}

+(NSString*) stringSha256:(NSString*) data
{
    return [self hexadecimalString:[self sha256:[data dataUsingEncoding:NSUTF8StringEncoding]]];
}

+(NSData*) sha256HmacForKey:(NSData*) key andData:(NSData*) data
{
    if(!key || !data)
        return nil;
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CCHmac(kCCHmacAlgSHA256, [key bytes], (UInt32)[key length], [data bytes], (UInt32)[data length], digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+(NSString*) stringSha256HmacForKey:(NSString*) key andData:(NSString*) data
{
    if(!key || !data)
        return nil;
	return [self hexadecimalString:[self sha256HmacForKey:[key dataUsingEncoding:NSUTF8StringEncoding] andData:[data dataUsingEncoding:NSUTF8StringEncoding]]];
}


#pragma mark Base64

+(NSString*) encodeBase64WithString:(NSString*) strData
{
    NSData* data = [strData dataUsingEncoding:NSUTF8StringEncoding];
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
    
    const unsigned char* dataBuffer = (const unsigned char *)[data bytes];
    
    if (!dataBuffer)
        return [NSString string];
    
    NSUInteger dataLength  = [data length];
    NSMutableString* hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (int i = 0; i < dataLength; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02x", (unsigned int)dataBuffer[i]]];
    
    return [NSString stringWithString:hexString];
}


+(NSData*) dataWithHexString:(NSString*) hex
{
    char buf[3];
    buf[2] = '\0';
    
    if([hex length] % 2 != 00) {
        DDLogError(@"Hex strings should have an even number of digits");
        return [[NSData alloc] init];
    }
    unsigned char* bytes = malloc([hex length] / 2);
    unsigned char* bp = bytes;
    for (CFIndex i = 0; i < [hex length]; i += 2) {
        buf[0] = [hex characterAtIndex:i];
        buf[1] = [hex characterAtIndex:i+1];
        char* b2 = NULL;
        *bp++ = strtol(buf, &b2, 16);
        if(b2 != buf + 2) {
            DDLogError(@"String should be all hex digits");
            free(bytes);
            return [[NSData alloc] init];
        }
    }
    return [NSData dataWithBytesNoCopy:bytes length:[hex length]/2 freeWhenDone:YES];
}


+(NSString *)signalHexKeyWithData:(NSData*) data
{
    NSString* hex = [self hexadecimalString:data];
    
    //remove 05 cipher info
    hex = [hex substringWithRange:NSMakeRange(2, hex.length - 2)];

    return hex;
}

+(NSString *)signalHexKeyWithSpacesWithData:(NSData*) data
{
    NSMutableString* hex = [[self signalHexKeyWithData:data] mutableCopy];
   
    int counter = 0;
    while(counter <= (hex.length - 2))
    {
        counter+=8;
        [hex insertString:@" " atIndex:counter];
        counter++;
    }
    return hex.uppercaseString;
}


+(UIView*) MLCustomViewHeaderWithTitle:(NSString*) title
{
    UIView* tempView = [[UIView alloc]initWithFrame:CGRectMake(0, 200, 300, 244)];
    tempView.backgroundColor = [UIColor clearColor];

    UILabel* tempLabel = [[UILabel alloc]initWithFrame:CGRectMake(15, 0, 300, 44)];
    tempLabel.backgroundColor = [UIColor clearColor];
    tempLabel.shadowColor = [UIColor blackColor];
    tempLabel.shadowOffset = CGSizeMake(0, 2);
    tempLabel.textColor = [UIColor whiteColor]; //here you can change the text color of header.
    tempLabel.font = [UIFont boldSystemFontOfSize:17.0f];
    tempLabel.text = title;

    [tempView addSubview:tempLabel];

    tempLabel.textColor = [UIColor darkGrayColor];
    tempLabel.text =  tempLabel.text.uppercaseString;
    tempLabel.shadowColor = [UIColor clearColor];
    tempLabel.font = [UIFont systemFontOfSize:[UIFont systemFontSize]];

    return tempView;
}

+(CIImage*) createQRCodeFromString:(NSString*) input
{
    NSData* inputAsUTF8 = [input dataUsingEncoding:NSUTF8StringEncoding];

    CIFilter<CIQRCodeGenerator>* qrCode = [CIFilter QRCodeGenerator];
    [qrCode setValue:inputAsUTF8 forKey:@"message"];
    [qrCode setValue:@"L" forKey:@"correctionLevel"];

    return qrCode.outputImage;
}


@end
