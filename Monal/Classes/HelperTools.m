//
//  HelperTools.m
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#include "hsluv.h"
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/mach_traps.h>
#include <os/proc.h>

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import "HelperTools.h"
#import "MLXMPPManager.h"
#import "MLPubSub.h"
#import "MLUDPLogger.h"
#import "MLHandler.h"
#import "MLXMLNode.h"
#import "XMPPStanza.h"
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"
#import "XMPPDataForm.h"
#import "xmpp.h"
#import "MLNotificationQueue.h"
#import "MLContact.h"
#import "MLMessage.h"

@import UserNotifications;
@import CoreImage;
@import CoreImage.CIFilterBuiltins;
@import UIKit;
@import AVFoundation;

static DDFileLogger* _fileLogger;

@interface xmpp()
-(void) dispatchOnReceiveQueue: (void (^)(void)) operation;
@end

@implementation HelperTools

void logException(NSException* exception)
{
    [DDLog flushLog];
    DDLogError(@"*****************\nCRASH(%@): %@\nUserInfo: %@\nStack Trace: %@", [exception name], [exception reason], [exception userInfo], [exception callStackSymbols]);
    [DDLog flushLog];
    usleep(1000000);
}

+(void) MLAssert:(BOOL) check withText:(NSString*) text andUserData:(id) userInfo andFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    if(!check)
    {
        NSString* fileStr = [NSString stringWithFormat:@"%s", file];
        NSArray* filePathComponents = [fileStr pathComponents];
        if([filePathComponents count]>1)
            fileStr = [NSString stringWithFormat:@"%@/%@", filePathComponents[[filePathComponents count]-2], filePathComponents[[filePathComponents count]-1]];
        DDLogError(@"Assertion triggered at %@:%d in %s", fileStr, line, func);
        @throw [NSException exceptionWithName:[NSString stringWithFormat:@"MLAssert triggered at %@:%d in %s", fileStr, line, func] reason:text userInfo:userInfo];
    }
}

+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere
{
    NSString* message;
    if(node)
        message = [HelperTools extractXMPPError:node withDescription:description];
    else
        message = description;
    DDLogError(@"Notifying user about %@ error: %@", isSevere ? @"SEVERE" : @"non-severe", message);
    [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:account userInfo:@{@"message": message, @"isSevere":@(isSevere)}];
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

+(NSString*) pushServer
{
#ifdef IS_ALPHA
    return @"alpha.push.monal-im.org";
#else
    return @"ios13push.monal.im";
#endif
}


+(NSData*) serializeObject:(id) obj
{
    NSError* error;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:obj requiringSecureCoding:YES error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    return data;
}

+(id) unserializeData:(NSData*) data
{
    NSError* error;
    id obj = [NSKeyedUnarchiver unarchivedObjectOfClasses:[[NSSet alloc] initWithArray:@[
        [NSData class],
        [NSMutableData class],
        [NSMutableDictionary class],
        [NSDictionary class],
        [NSMutableSet class],
        [NSSet class],
        [NSMutableArray class],
        [NSArray class],
        [NSNumber class],
        [NSString class],
        [NSDate class],
        [MLHandler class],
        [MLXMLNode class],
        [XMPPIQ class],
        [XMPPPresence class],
        [XMPPMessage class],
        [XMPPDataForm class],
        [MLContact class],
        [MLMessage class],
        [NSURL class],
    ]] fromData:data error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    return obj;
}

+(NSError* _Nullable) postUserNotificationRequest:(UNNotificationRequest*) request
{
    __block NSError* retval = nil;
    NSCondition* condition = [[NSCondition alloc] init];
    [condition lock];
    monal_void_block_t cancelTimeout = createTimer(1.0, (^{
        DDLogError(@"Waiting for notification center took more than 1.0 second, continuing anyways");
        [condition lock];
        [condition signal];
        [condition unlock];
    }));
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if(error)
            DDLogError(@"Error posting notification: %@", error);
        retval = error;
        [condition lock];
        [condition signal];
        [condition unlock];
    }];
    [condition wait];
    [condition unlock];
    cancelTimeout();
    return retval;
}

+(NSData*) resizeAvatarImage:(UIImage* _Nullable) image withCircularMask:(BOOL) circularMask toMaxBase64Size:(unsigned long) length
{
    if(!image)
        return [[NSData alloc] init];
    
    int destinationSize = 480;
    int epsilon = 8;
    UIImage* clippedImage = image;
    UIGraphicsImageRendererFormat* format = [[UIGraphicsImageRendererFormat alloc] init];
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    format.scale = 1.0;
    if(ABS(image.size.width - image.size.height) > epsilon)
    {
        //see this for different resizing techniques, memory consumption and other caveats:
        // - https://nshipster.com/image-resizing/
        // - https://www.advancedswift.com/crop-image/
        // - https://www.swiftjectivec.com/optimizing-images/
        CGFloat minSize = MIN(image.size.width, image.size.height);
        CGRect drawImageRect = CGRectMake(
            (image.size.width - minSize) / -2.0,
            (image.size.height - minSize) / -2.0,
            image.size.width,
            image.size.height
        );
        CGRect drawRect = CGRectMake(
            0,
            0,
            minSize,
            minSize
        );
        DDLogInfo(@"Clipping avatar image %@ to %lux%lu pixels", image, (unsigned long)drawImageRect.size.width, (unsigned long)drawImageRect.size.height);
        DDLogDebug(@"minSize: %.2f, drawImageRect: (%.2f, %.2f, %.2f, %.2f)", minSize,
            drawImageRect.origin.x,
            drawImageRect.origin.y,
            drawImageRect.size.width,
            drawImageRect.size.height
        );
        clippedImage = [[[UIGraphicsImageRenderer alloc] initWithSize:drawRect.size format:format] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull context __unused) {
            //not needed here, already done below
            //if(circularMask)
            //    [[UIBezierPath bezierPathWithOvalInRect:drawRect] addClip];
            [image drawInRect:drawImageRect];
        }];
        image = nil;     //make sure we free our memory as soon as possible
        DDLogInfo(@"Clipped image is now: %@", clippedImage);
    }
    
    //shrink image to a maximum of 480x480 pixel (AVMakeRectWithAspectRatioInsideRect() keeps the aspect ratio)
    //CGRect dimensions = AVMakeRectWithAspectRatioInsideRect(image.size, CGRectMake(0, 0, 480, 480));
    CGRect dimensions;
    if(clippedImage.size.width > destinationSize + epsilon)
    {
        dimensions = CGRectMake(0, 0, destinationSize, destinationSize);
        DDLogInfo(@"Now shrinking image to %lux%lu pixels", (unsigned long)dimensions.size.width, (unsigned long)dimensions.size.height);
    }
    else if(circularMask)
    {
        dimensions = CGRectMake(0, 0, clippedImage.size.width, clippedImage.size.height);
        DDLogInfo(@"Only masking image to a %lux%lu pixels circle", (unsigned long)dimensions.size.width, (unsigned long)dimensions.size.height);
    }
    else
    {
        dimensions = CGRectMake(0, 0, 0, 0);
        DDLogInfo(@"Not doing anything to image, everything is already perfect: %@", clippedImage);
    }
    
    //only shink/mask image if needed and requested (indicated by a dimension size > 0
    UIImage* resizedImage = clippedImage;
    if(dimensions.size.width > 0)
    {
        resizedImage = [[[UIGraphicsImageRenderer alloc] initWithSize:dimensions.size format:format] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull context __unused) {
            if(circularMask)
                [[UIBezierPath bezierPathWithOvalInRect:dimensions] addClip];
            [clippedImage drawInRect:dimensions];
        }];
        DDLogInfo(@"Shrinked/masked image is now: %@", resizedImage);
    }
    clippedImage = nil;     //make sure we free our memory as soon as possible
    
    //masked images MUST be of type png because jpeg does no carry any transparency information
    NSData* data = nil;
    if(circularMask)
    {
        data = UIImagePNGRepresentation(resizedImage);
        DDLogInfo(@"Returning new avatar png data with size %lu for image: %@", (unsigned long)data.length, resizedImage);
    }
    else
    {
        //now reduce quality until image data is smaller than provided size
        unsigned int i = 0;
        double qualityList[] = {0.96, 0.80, 0.64, 0.48, 0.32, 0.24, 0.16, 0.10, 0.09, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.02, 0.01};
        for(i = 0; (data == nil || (data.length * 1.5) > length) && i < sizeof(qualityList) / sizeof(qualityList[0]); i++)
        {
            DDLogDebug(@"Resizing new avatar to quality %f", qualityList[i]);
            data = UIImageJPEGRepresentation(resizedImage, qualityList[i]);
            DDLogDebug(@"New avatar size after changing quality: %lu", (unsigned long)data.length);
        }
        DDLogInfo(@"Returning new avatar jpeg data with size %lu and quality %f for image: %@", (unsigned long)data.length, qualityList[i-1], resizedImage);
    }
    return data;
}

+(double) report_memory
{
    struct task_basic_info info;
    mach_msg_type_number_t size = TASK_BASIC_INFO_COUNT;
    kern_return_t kerr = task_info(mach_task_self(),
                                    TASK_BASIC_INFO,
                                    (task_info_t)&info,
                                    &size);
    if(kerr == KERN_SUCCESS)
        return ((CGFloat)info.resident_size / 1048576);
    else
        DDLogDebug(@"Error with task_info(): %s", mach_error_string(kerr));
    return 1.0;     //dummy value
}

+(UIColor*) generateColorFromJid:(NSString*) jid
{
    //cache generated colors
    static NSMutableDictionary* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSMutableDictionary alloc] init];
    });
    if(cache[jid] != nil)
        return cache[jid];
    
    //XEP-0392 implementation
    NSData* hash = [self sha1:[jid dataUsingEncoding:NSUTF8StringEncoding]];
    uint16_t rawHue = CFSwapInt16LittleToHost(*(uint16_t*)[hash bytes]);
    double hue = (rawHue / 65536.0) * 360.0;
    double saturation = 100.0;
    double lightness = 50.0;
    
    double r, g, b;
    hsluv2rgb(hue, saturation, lightness, &r, &g, &b);
    return cache[jid] = [UIColor colorWithRed:r green:g blue:b alpha:1];
}

+(NSString*) bytesToHuman:(int64_t) bytes
{
    NSArray* suffixes = @[@"B", @"KiB", @"MiB", @"GiB", @"TiB", @"PiB", @"EiB"];
    NSString* prefix = @"";
    double size = bytes;
    if(size < 0)
    {
        prefix = @"-";
        size *= -1;
    }
    for(NSString* suffix in suffixes)
        if(size < 1024)
            return [NSString stringWithFormat:@"%@%.1F %@", prefix, size, suffix];
        else
            size /= 1024.0;
    return [NSString stringWithFormat:@"%lld B", bytes];
}

+(NSString*) stringFromToken:(NSData*) tokenIn
{
    unsigned char* tokenBytes = (unsigned char*)[tokenIn bytes];
    NSMutableString* token = [[NSMutableString alloc] init];
    NSUInteger counter = 0;
    while(counter < tokenIn.length)
    {
        [token appendString:[NSString stringWithFormat:@"%02x", (unsigned char)tokenBytes[counter]]];
        counter++;
    }
    return token;
}

+(void) configureFileProtection:(NSString*) protectionLevel forFile:(NSString*) file
{
#if TARGET_OS_IPHONE
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:file])
    {
        //DDLogVerbose(@"protecting file '%@'...", file);
        NSError* error;
        [fileManager setAttributes:@{NSFileProtectionKey: protectionLevel} ofItemAtPath:file error:&error];
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

+(void) configureFileProtectionFor:(NSString*) file
{
    [self configureFileProtection:NSFileProtectionCompleteUntilFirstUserAuthentication forFile:file];
}

+(NSDictionary<NSString*, NSString*>*) splitJid:(NSString*) jid
{
    //cache results
    static NSMutableDictionary* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSMutableDictionary alloc] init];
    });
    if(cache[jid] != nil)
        return cache[jid];
    
    NSMutableDictionary<NSString*, NSString*>* retval = [[NSMutableDictionary alloc] init];
    NSArray* parts = [jid componentsSeparatedByString:@"/"];
    
    retval[@"user"] = [[parts objectAtIndex:0] lowercaseString];        //intended to not break code that expects lowercase
    if([parts count] > 1 && [[parts objectAtIndex:1] isEqualToString:@""] == NO)
        retval[@"resource"] = [parts objectAtIndex:1];                  //resources are case sensitive
    parts = [retval[@"user"] componentsSeparatedByString:@"@"];
    if([parts count] > 1)
    {
        retval[@"node"] = [[parts objectAtIndex:0] lowercaseString];    //intended to not break code that expects lowercase
        retval[@"host"] = [[parts objectAtIndex:1] lowercaseString];    //intended to not break code that expects lowercase
    }
    else
        retval[@"host"] = [[parts objectAtIndex:0] lowercaseString];    //intended to not break code that expects lowercase
    
    //log sanity check errors (this checks 'host' and 'user'at once because without node host==user)
    if([retval[@"host"] isEqualToString:@""])
        DDLogError(@"jid '%@' has no host part!", jid);
    
    //sanitize retval
    if([retval[@"node"] isEqualToString:@""])
    {
        [retval removeObjectForKey:@"node"];
        retval[@"user"] = retval[@"host"];      //empty node means user==host
    }
    if([retval[@"resource"] isEqualToString:@""])
        [retval removeObjectForKey:@"resource"];
    
    return cache[jid] = [retval copy];          //return immutable copy
}

+(void) clearSyncErrorsOnAppForeground
{
    NSMutableDictionary* syncErrorsDisplayed = [NSMutableDictionary dictionaryWithDictionary:[[HelperTools defaultsDB] objectForKey:@"syncErrorsDisplayed"]];
    DDLogInfo(@"Clearing syncError notification states: %@", syncErrorsDisplayed);
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
        syncErrorsDisplayed[account.connectionProperties.identity.jid] = @NO;
    [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
}

+(void) updateSyncErrorsWithDeleteOnly:(BOOL) removeOnly andWaitForCompletion:(BOOL) waitForCompletion
{
    monal_void_block_t updateSyncErrors = ^{
        @synchronized(self) {
            NSMutableDictionary* syncErrorsDisplayed = [NSMutableDictionary dictionaryWithDictionary:[[HelperTools defaultsDB] objectForKey:@"syncErrorsDisplayed"]];
            DDLogInfo(@"Updating syncError notifications: %@", syncErrorsDisplayed);
            for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
            {
                //ignore already disconnected accounts (they are always "idle" but this does not reflect the real sync state)
                if(account.accountState < kStateReconnecting && !account.reconnectInProgress)
                    continue;
                NSString* syncErrorIdentifier = [NSString stringWithFormat:@"syncError::%@", account.connectionProperties.identity.jid];
                //dispatching this to the receive queue isn't neccessary anymore, see comments in account.idle
                if(account.idle)
                {
                    DDLogInfo(@"Removing syncError notification for %@ (now synced)...", account.connectionProperties.identity.jid);
                    [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[syncErrorIdentifier]];
                    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[syncErrorIdentifier]];
                    syncErrorsDisplayed[account.connectionProperties.identity.jid] = @NO;
                    [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
                }
                else if(!removeOnly && [self isNotInFocus])
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
                    //we don't know if and when apple will start the background process or when the next push will come in
                    //--> we need a sync error notification to make the user aware of possible issues
                    //BUT: we can delay it for some time and hope a background process/push is started in the meantime and removes the notification
                    //     before it gets displayed at all (we use 60 seconds here)
                    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:syncErrorIdentifier content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:60 repeats: NO]];
                    NSError* error = [self postUserNotificationRequest:request];
                    if(error)
                        DDLogError(@"Error posting syncError notification: %@", error);
                    else
                    {
                        syncErrorsDisplayed[account.connectionProperties.identity.jid] = @YES;
                        [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
                    }
                }
            }
        }
    };
    
    //dispatch async because we don't want to block the receive/parse/send queue invoking this check
    if(waitForCompletion)
        updateSyncErrors();
    else
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), updateSyncErrors);
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
            DDLogInfo(@"activity(%@): %lu, memory used / available: %.3fMiB / %.3fMiB", appex ? @"APPEX" : @"MAINAPP", counter, [self report_memory], (CGFloat)os_proc_available_memory() / 1048576);
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
    self.fileLogger.rollingFrequency = 60 * 60 * 48;    // 48 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize = 1024 * 1024 * 1024;
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

+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features andForms:(NSArray*) forms
{
    // see https://xmpp.org/extensions/xep-0115.html#ver
    NSMutableString* unhashed = [[NSMutableString alloc] init];
    
    //generate identities string (must be sorted according to XEP-0115)
    identities = [identities sortedArrayUsingSelector:@selector(compare:)];
    for(NSString* identity in identities)
        [unhashed appendString:[NSString stringWithFormat:@"%@<", [self _replaceLowerThanInString:identity]]];
    
    //append features string
    [unhashed appendString:[self generateStringOfFeatureSet:features]];
    
    //append forms string
    [unhashed appendString:[self generateStringOfCapsForms:forms]];
    
    NSString* hashedBase64 = [self encodeBase64WithData:[self sha1:[unhashed dataUsingEncoding:NSUTF8StringEncoding]]];
    DDLogVerbose(@"ver string: unhashed %@, hashed-64 %@", unhashed, hashedBase64);
    return hashedBase64;
}

+(NSString*) _replaceLowerThanInString:(NSString*) str
{
    NSMutableString* retval = [str mutableCopy];
    [retval replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, retval.length)];
    return [retval copy];       //make immutable
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
            @"jabber:x:oob",
            @"urn:xmpp:ping",
            @"urn:xmpp:receipts",
            @"urn:xmpp:idle:1",
            @"http://jabber.org/protocol/chatstates",
            @"jabber:iq:version",
            @"urn:xmpp:chat-markers:0",
            @"urn:xmpp:eme:0"
        ];
        featuresSet = [[NSSet alloc] initWithArray:featuresArray];
    });
    return featuresSet;
}

+(NSString*) generateStringOfFeatureSet:(NSSet*) features
{
    // this has to be sorted for the features hash to be correct, see https://xmpp.org/extensions/xep-0115.html#ver
    NSArray* featuresArray = [[features allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString* toreturn = [[NSMutableString alloc] init];
    for(NSString* feature in featuresArray)
    {
        [toreturn appendString:[self _replaceLowerThanInString:feature]];
        [toreturn appendString:@"<"];
    }
    return toreturn;
}

+(NSString*) generateStringOfCapsForms:(NSArray*) forms
{
    // this has to be sorted for the features hash to be correct, see https://xmpp.org/extensions/xep-0115.html#ver
    NSMutableString* toreturn = [[NSMutableString alloc] init];
    for(XMPPDataForm* form in [forms sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"formType" ascending:YES selector:@selector(compare:)]]])
    {
        [toreturn appendString:[self _replaceLowerThanInString:form.formType]];
        [toreturn appendString:@"<"];
        for(NSString* field in [[form allKeys] sortedArrayUsingSelector:@selector(compare:)])
        {
            [toreturn appendString:[self _replaceLowerThanInString:field]];
            [toreturn appendString:@"<"];
            for(NSString* value in [[form getField:field][@"allValues"] sortedArrayUsingSelector:@selector(compare:)])
            {
                [toreturn appendString:[self _replaceLowerThanInString:value]];
                [toreturn appendString:@"<"];
            }
        }
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
    unsigned long currentTimestamp = [HelperTools currentTimestampInSeconds].unsignedLongValue;

    unsigned long lastInteractionTime = 0;      //default is zero which corresponds to "online"

    // calculate timestamp and clamp it to be not in the future (but only if given)
    if(lastInteraction && [lastInteraction timeIntervalSince1970] != 0)
    {
        //NSDictionary does not support nil, so we're using timeSince1970 + 0 sometimes
        lastInteractionTime = MIN([HelperTools dateToNSNumberSeconds:lastInteraction].unsignedLongValue, currentTimestamp);
    }

    if(lastInteractionTime > 0) {
        NSString* timeString;

        long long diff = currentTimestamp - lastInteractionTime;
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
            diff /= 60.0;
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

//don't use this directly, but via createTimer() makro
+(monal_void_block_t) startQueuedTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func onQueue:(dispatch_queue_t _Nullable) queue
{
    if(queue == nil)
        queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    NSString* fileStr = [NSString stringWithFormat:@"%s", file];
    NSArray* filePathComponents = [fileStr pathComponents];
    if([filePathComponents count]>1)
        fileStr = [NSString stringWithFormat:@"%@/%@", filePathComponents[[filePathComponents count]-2], filePathComponents[[filePathComponents count]-1]];
    
    if(timeout<=0.001)
    {
        //DDLogVerbose(@"Timer timeout is smaller than 0.001, dispatching handler directly.");
        if(handler)
            dispatch_async(queue, ^{
                handler();
            });
        return ^{ };        //empty cancel block because this "timer" already triggered
    }
    
    NSString* uuid = [[NSUUID UUID] UUIDString];
    
    //DDLogDebug(@"setting up timer %@(%G)", uuid, timeout);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout*NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (uint64_t) (0.1 * NSEC_PER_SEC));      //leeway of 100ms
    
    dispatch_source_set_event_handler(timer, ^{
        DDLogDebug(@"timer %@ %@(%G) triggered (created at %@:%d in %s)", timer, uuid, timeout, fileStr, line, func);
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
    DDLogDebug(@"starting timer %@ %@(%G) (created at %@:%d in %s)", timer, uuid, timeout, fileStr, line, func);
    dispatch_resume(timer);
    
    //return block that can be used to cancel the timer
    return ^{
        DDLogDebug(@"cancel block for timer %@ %@(%G) called (created at %@:%d in %s)", timer, uuid, timeout, fileStr, line, func);
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

+(NSString*) hexadecimalString:(NSData*) data
{
    /* Returns hexadecimal string of NSData. Empty string if data is empty.   */
    
    const unsigned char* dataBuffer = (const unsigned char *)[data bytes];
    
    if (!dataBuffer)
        return [NSString string];
    
    NSUInteger dataLength  = [data length];
    NSMutableString* hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (unsigned int i = 0; i < dataLength; ++i)
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
    for (unsigned int i = 0; i < [hex length]; i += 2) {
        buf[0] = (unsigned char) [hex characterAtIndex:i];
        buf[1] = (unsigned char) [hex characterAtIndex:i+1];
        char* b2 = NULL;
        *bp++ = (unsigned char) strtol(buf, &b2, 16);
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
   
    unsigned int counter = 0;
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

+(NSString*) appBuildVersionInfo
{
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
#ifdef IS_ALPHA
        NSString* versionTxt = [NSString stringWithFormat:@"Alpha %@ (%s: %s UTC)", [infoDict objectForKey:@"CFBundleShortVersionString"], __DATE__, __TIME__];
#else
        NSString* versionTxt = [NSString stringWithFormat:@"%@ (%@)", [infoDict objectForKey:@"CFBundleShortVersionString"], [infoDict objectForKey:@"CFBundleVersion"]];
#endif
    return  versionTxt;
}

+(BOOL) deviceUsesSplitView
{
#if TARGET_OS_MACCATALYST
    return YES;
#else
    switch ([[UIDevice currentDevice] userInterfaceIdiom]) {
        case UIUserInterfaceIdiomPad:
            return YES;
            break;
        case UIUserInterfaceIdiomPhone:
            return NO;
        default:
            unreachable();
            return NO;
    }
#endif
}

+(NSNumber*) currentTimestampInSeconds
{
    return [HelperTools dateToNSNumberSeconds:[NSDate date]];
}

+(NSNumber*) dateToNSNumberSeconds:(NSDate*) date
{
    return [NSNumber numberWithUnsignedLong:(unsigned long)date.timeIntervalSince1970];
}

@end
