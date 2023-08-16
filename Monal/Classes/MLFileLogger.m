//
//  MLFileLogger.m
//  monalxmpp
//
//  Created by Thilo Molitor on 18.06.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLFileLogger.h"
#import "HelperTools.h"

extern BOOL doesAppRunInBackground(void);
@interface DDFileLogger ()
-(BOOL) lt_shouldLogFileBeArchived:(DDLogFileInfo*) mostRecentLogFileInfo;
@end

@interface MLFileLogger () {
    BOOL _archiveAllowed;
}
@end

@implementation MLFileLogger

//overwrite constructor to make sure archiveAllowed is NO when creating this instance
-(instancetype) initWithLogFileManager:(id <DDLogFileManager>) aLogFileManager completionQueue:(nullable dispatch_queue_t) dispatchQueue
{
    self = [super initWithLogFileManager:aLogFileManager completionQueue:dispatchQueue];
    self.archiveAllowed = NO;
    return self;
}

-(BOOL) archiveAllowed
{
    //reading an atomic bool does not need to be synchronized
    return self->_archiveAllowed;
}

-(void) setArchiveAllowed:(BOOL) archiveAllowed
{
    //this must be done on the same queue as lt_shouldLogFileBeArchived is running on to prevent race conditions
    dispatch_queue_t globalLoggingQueue = [DDLog loggingQueue];
    dispatch_async(globalLoggingQueue, ^{
        dispatch_async(self.loggerQueue, ^{
            NSLog(@"Setting archiveAllowed = %@", bool2str(archiveAllowed));
            self->_archiveAllowed = archiveAllowed;
        });
    });
}
    
//patch DDFileLogger to think that this logfile can be reused
-(BOOL) lt_shouldLogFileBeArchived:(DDLogFileInfo*) mostRecentLogFileInfo
{
    //just hand over to official implementation once everything is properly configured
    if(self.archiveAllowed)
    {
        NSLog(@"lt_shouldLogFileBeArchived: handing over to super implementation");
        return [super lt_shouldLogFileBeArchived:mostRecentLogFileInfo];
    }
    
    NSLog(@"lt_shouldLogFileBeArchived: running patched implementation, archiveAllowed==NO");
    
    NSAssert([self isOnInternalLoggerQueue], @"lt_ methods should be on logger queue.");

    //this is our change (but the file protection check below is still needed)
//     if ([self shouldArchiveRecentLogFileInfo:mostRecentLogFileInfo]) {
//         return YES;
//     } else if (_maximumFileSize > 0 && mostRecentLogFileInfo.fileSize >= _maximumFileSize) {
//         return YES;
//     } else if (_rollingFrequency > 0.0 && mostRecentLogFileInfo.age >= _rollingFrequency) {
//         return YES;
//     }

    //this has still to be active, to rotate the logfile if the file protection is wrong (should never happen with our configuration)
#if TARGET_OS_IPHONE
    // When creating log file on iOS we're setting NSFileProtectionKey attribute to NSFileProtectionCompleteUnlessOpen.
    //
    // But in case if app is able to launch from background we need to have an ability to open log file any time we
    // want (even if device is locked). Thats why that attribute have to be changed to
    // NSFileProtectionCompleteUntilFirstUserAuthentication.
    //
    // If previous log was created when app wasn't running in background, but now it is - we archive it and create
    // a new one.
    //
    // If user has overwritten to NSFileProtectionNone there is no need to create a new one.
    NSFileProtectionType key = mostRecentLogFileInfo.fileAttributes[NSFileProtectionKey];
    BOOL isUntilFirstAuth = [key isEqualToString:NSFileProtectionCompleteUntilFirstUserAuthentication];
    BOOL isNone = [key isEqualToString:NSFileProtectionNone];

    if (key != nil && !isUntilFirstAuth && !isNone) {
        NSLog(@"File protection type not sufficient: %@", key);
#ifdef is_ALPHA
        unreachable(@"File protection type not sufficient", mostRecentLogFileInfo.fileAttributes);
#endif
        return YES;
    }
#endif

    return NO;
}

-(NSData*) lt_dataForMessage:(DDLogMessage*) logMessage
{
    static uint64_t counter = 0;
    
    //copy assertion from super implementation
    NSAssert([self isOnInternalLoggerQueue], @"logMessage should only be executed on internal queue.");
    
    //encode log message
    NSError* error;
    NSData* rawData = [HelperTools convertLogmessageToJsonData:logMessage usingFormatter:_logFormatter counter:&counter andError:&error];
    if(error != nil || rawData == nil)
    {
        NSLog(@"Error jsonifying log message: %@, logMessage: %@", error, logMessage);
        return [NSData new];        //return empty data, e.g. write nothing
    }
    
    //add 32bit length prefix
    NSAssert(rawData.length < (NSUInteger)1<<30, @"LogMessage is longer than 1<<30 bytes!");
    uint32_t length = CFSwapInt32HostToBig((uint32_t)rawData.length);
    NSMutableData* data = [[NSMutableData alloc] initWithBytes:&length length:sizeof(length)];
    [data appendData:rawData];
    
    //return length_prefix + json_encoded_data
    return data;
}

@end
