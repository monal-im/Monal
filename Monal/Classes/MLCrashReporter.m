//
//  MLCrashReporter.m
//  Monal
//
//  Created by admin on 21.06.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <KSCrash/KSCrash.h>
#import <KSCrash/KSCrashReportFilterBasic.h>
#import <KSCrash/KSCrashReportFilterJSON.h>
#import <KSCrash/KSCrashReportFilterAppleFmt.h>
#import <KSCrash/KSCrashReportFilterGZip.h>
#import <KSCrash/KSCrashReportFields.h>
#import <KSCrash/NSError+SimpleConstructor.h>
#import <MessageUI/MessageUI.h>
#import "MLConstants.h"
#import "HelperTools.h"
#import "MonalAppDelegate.h"
#import "MLCrashReporter.h"

#define PART_SEPARATOR_FORMAT "\n\n-------- d049d576-9bf0-47dd-839f-dee6b07c1df9 -------- %@ -------- d049d576-9bf0-47dd-839f-dee6b07c1df9 --------\n\n"

@interface KSCrashReportFilterAlert: NSObject <KSCrashReportFilter>
+(instancetype) filter;
@end

@interface KSCrashReportFilterEmpty: NSObject <KSCrashReportFilter>
+(instancetype) filter;
@end

@interface KSCrashReportFilterAddAuxInfo : NSObject <KSCrashReportFilter>
+(instancetype) filter;
@end

@interface KSCrashReportFilterAddMLLogfile : NSObject <KSCrashReportFilter>
+(instancetype) filter;
@end


@interface MLCrashReporter() <KSCrashReportFilter, MFMailComposeViewControllerDelegate>
@property (atomic, strong) NSArray* _Nullable kscrashReports;
@property (atomic, strong) KSCrashReportFilterCompletion _Nullable kscrashCompletion;
@end


@implementation MLCrashReporter

+(void) reportPendingCrashes
{
    //send out pending KSCrash reports
    KSCrash* handler = [KSCrash sharedInstance];
    handler.deleteBehaviorAfterSendAll = KSCDeleteAlways;       //KSCDeleteNever
    id<KSCrashReportFilter> dummyFilter = [KSCrashReportFilterEmpty filter];
    NSString* dummyFilterName = @"dummy not printed";
    id<KSCrashReportFilter> auxInfoFilter = [KSCrashReportFilterAddAuxInfo filter];
    NSString* auxInfoName = @"AUX Info (*.txt)";
    id<KSCrashReportFilter> appleFilter = [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide];
    NSString* appleName = @"Apple Report (*.crash)";
    NSArray<id<KSCrashReportFilter>>* jsonFilter = @[[KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionPretty], [KSCrashReportFilterDataToString filter]];
    NSString* jsonName = @"JSON Report (*.json)";
    id<KSCrashReportFilter> logfileFilter = [KSCrashReportFilterAddMLLogfile filter];
    NSString* logfileName = @"Logfile (*.rawlog.gz)";
    handler.sink = [KSCrashReportFilterPipeline filterWithFilters:
                        [KSCrashReportFilterAlert filter],
                        [KSCrashReportFilterCombine filterWithFiltersAndKeys:
                            dummyFilter, dummyFilterName,       //this dummy is needed to make the filter framework print the title of our aux data
                            auxInfoFilter, auxInfoName,
                            appleFilter, appleName,
                            jsonFilter, jsonName,
                            logfileFilter, logfileName,
                            nil
                        ],
                        [KSCrashReportFilterConcatenate filterWithSeparatorFmt:@PART_SEPARATOR_FORMAT keys:
                            dummyFilterName,
                            auxInfoName,
                            appleName,
                            jsonName,
                            logfileName,
                            nil
                        ],
                        [KSCrashReportFilterStringToData filter],
                        [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                        [[self alloc] init],           //this is the last filter sending out all stuff via mail
                        nil
                   ];
    DDLogVerbose(@"Trying to send crash reports...");
    [handler sendAllReportsWithCompletion:^(NSArray* reports, BOOL completed, NSError* error){
        if(completed)
            DDLogWarn(@"Sent %d reports", (int)[reports count]);
        else
            DDLogError(@"Failed to send reports: %@", error);
    }];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(![MFMailComposeViewController canSendMail])
    {
#if TARGET_OS_SIMULATOR
        u_int32_t runid_raw = arc4random();
        NSString* runid = [HelperTools hexadecimalString:[NSData dataWithBytes:&runid_raw length:sizeof(runid_raw)]];
        int i = 1;
        for(NSData* report in reports)
            if(![report isKindOfClass:[NSData class]])
                DDLogError(@"Report was of unsupported data type %@", [report class]);
            else
            {
                NSString* path = [[HelperTools getContainerURLForPathComponents:@[[NSString stringWithFormat:@"CrashReport-%@-%d.mcrash.gz", runid, i++]]] path];
                DDLogWarn(@"Writing report %d to file: %@", i, path);
                [report writeToFile:path atomically:YES];
            }
        kscrash_callCompletion(onCompletion, reports, YES,
                                 [NSError errorWithDomain:[[self class] description]
                                                     code:0
                                              description:@"Crashreports written to simulator container..."]);
        return;
#else
        UIAlertController* alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Email Error", @"Crash report error dialog")
                                                                       message:NSLocalizedString(@"This device is not configured to send email.", @"Crash report error dialog")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Crash report error dialog")
                                                            style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alertController addAction:okAction];
        [[(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] getTopViewController] presentViewController:alertController animated:YES completion:NULL];

        kscrash_callCompletion(onCompletion, reports, NO,
                                 [NSError errorWithDomain:[[self class] description]
                                                     code:0
                                              description:NSLocalizedString(@"E-Mail not enabled on device", @"Crash report error dialog")]);
        return;
#endif
    }
    
    self.kscrashCompletion = onCompletion;
    self.kscrashReports = reports;

    DDLogVerbose(@"Preparing MFMailComposeViewController...");
    MFMailComposeViewController* mailController = [[MFMailComposeViewController alloc] init];
    mailController.mailComposeDelegate = self;
    [mailController setToRecipients:@[@"crash@monal-im.org"]];
    [mailController setSubject:@"Crash Reports"];
    [mailController setMessageBody:@"> Please fill in your last actions that led to this crash:\n" isHTML:NO];
    int i = 1;
    for(NSData* report in reports)
        if(![report isKindOfClass:[NSData class]])
            DDLogError(@"Report was of unsupported data type %@", [report class]);
        else
        {
            DDLogVerbose(@"Adding mail attachment...");
            [mailController addAttachmentData:report mimeType:@"binary" fileName:[NSString stringWithFormat:@"CrashReport-%d.mcrash.gz", i++]];
        }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Presenting MFMailComposeViewController...");
        [[(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] getTopViewController] presentViewController:mailController animated:YES completion:nil];
    });
}

-(void) mailComposeController:(__unused MFMailComposeViewController*) mailController didFinishWithResult:(MFMailComposeResult) result error:(NSError*) error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] getTopViewController] dismissViewControllerAnimated:YES completion:nil];

        if(self.kscrashCompletion == nil)
        {
            DDLogError(@"No kscrash completion given!");
            return;
        }
        
        switch(result)
        {
            case MFMailComposeResultSent:
                DDLogInfo(@"Crash report send result: MFMailComposeResultSent");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, YES, nil);
                break;
            case MFMailComposeResultSaved:
                DDLogInfo(@"Crash report send result: MFMailComposeResultSaved");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, YES, nil);
                break;
            case MFMailComposeResultCancelled:
                DDLogInfo(@"Crash report send result: MFMailComposeResultCancelled");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, NO,
                                        [NSError errorWithDomain:[[self class] description]
                                                            code:0
                                                    description:@"User cancelled"]);
                break;
            case MFMailComposeResultFailed:
                DDLogInfo(@"Crash report send result: MFMailComposeResultFailed");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, NO, error);
                break;
            default:
            {
                DDLogInfo(@"Crash report send result: unknown");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, NO,
                                        [NSError errorWithDomain:[[self class] description]
                                                            code:0
                                                    description:@"Unknown MFMailComposeResult: %d", result]);
            }
        }
        
        self.kscrashCompletion = nil;
        self.kscrashReports = nil;
    });
}

@end

@implementation KSCrashReportFilterAlert

+(instancetype) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSString* title = NSLocalizedString(@"Crash Detected", @"Crash reporting");
    NSString* message = NSLocalizedString(@"The app crashed last time it was launched. Send a crash report? This crash report will contain privacy related data. We will only use it to debug your crash and delete it afterwards!", @"Crash reporting");
    NSString* yesAnswer = NSLocalizedString(@"Sure, send it!", @"Crash reporting");
    NSString* noAnswer = NSLocalizedString(@"No, thanks", @"Crash reporting");
    
    DDLogVerbose(@"KSCrashReportFilterAlert started...");
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* yesAction = [UIAlertAction actionWithTitle:yesAnswer style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* _Nonnull action) {
            kscrash_callCompletion(onCompletion, reports, YES, nil);
        }];
        UIAlertAction* noAction = [UIAlertAction actionWithTitle:noAnswer style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction* _Nonnull action) {
            kscrash_callCompletion(onCompletion, reports, NO, nil);
        }];
        [alertController addAction:yesAction];
        [alertController addAction:noAction];
        [[(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] getTopViewController] presentViewController:alertController animated:YES completion:NULL];
    });
    DDLogVerbose(@"KSCrashReportFilterAlert finished...");
}

@end

@implementation KSCrashReportFilterEmpty

+(instancetype) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterEmpty started...");
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSUInteger i = 0; i < reports.count; i++)
        [filteredReports addObject:@""];
    DDLogVerbose(@"KSCrashReportFilterEmpty finished...");
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterAddAuxInfo

+(instancetype) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterAddAuxInfo started...");
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        NSMutableString* auxData = [NSMutableString new];
        
        //add user data to aux data
        for(NSString* userKey in report[@"user"])
            [auxData appendString:[NSString stringWithFormat:@"%@: %@\n", userKey, report[@"user"][userKey]]];
        
        //add crash_info_message and crash_info_message2 to aux data
        NSMutableString* crashInfos = [NSMutableString new];
        for(NSDictionary* binaryImage in report[@"binary_images"])
        {
            if(binaryImage[@"crash_info_message"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"message at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_message"]]];
            if(binaryImage[@"crash_info_message2"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"message2 at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_message2"]]];
            if(binaryImage[@"crash_info_signature"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"signature at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_signature"]]];
            if(binaryImage[@"crash_info_backtrace"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"backtrace at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_backtrace"]]];
        }
        if([crashInfos length] > 0)
            [auxData appendString:[NSString stringWithFormat:@"\nAvailable crash info messages:\n\n%@", crashInfos]];
        
        [filteredReports addObject:auxData];
    }
    DDLogVerbose(@"KSCrashReportFilterAddAuxInfo finished...");
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterAddMLLogfile

+(instancetype) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterAddMLLogfile started...");
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        NSString* logfileCopy = report[@"user"][@"logfileCopy"];
        NSData* logfileData = [NSData new];
        if(logfileCopy != nil)
        {
            DDLogDebug(@"Adding logfile copy of '%@' from '%@' to crash report...", report[@"user"][@"currentLogfile"], report[@"user"][@"logfileCopy"]);
            logfileData = [NSData dataWithContentsOfFile:logfileCopy];
            DDLogVerbose(@"NSData of logfile copy: %@", logfileData);
            NSError* error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:logfileCopy error:&error];
            if(error != nil)
                DDLogError(@"Failed to delete logfileCopy: %@", error);
            if(logfileData == nil)
                logfileData = [NSData new];
        }
        DDLogVerbose(@"Converting logfile data to hex...");
        [filteredReports addObject:[HelperTools hexadecimalString:logfileData]];
    }
    DDLogVerbose(@"KSCrashReportFilterAddMLLogfile finished...");
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end
