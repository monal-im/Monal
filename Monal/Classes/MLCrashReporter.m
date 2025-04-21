//
//  MLCrashReporter.m
//  Monal
//
//  Created by admin on 21.06.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <KSCrash/KSCrash.h>
#import <KSCrash/KSNSErrorHelper.h>
#import <KSCrash/KSCrashReport.h>
#import <KSCrash/KSCrashReportFilterBasic.h>
#import <KSCrash/KSCrashReportFilterJSON.h>
#import <KSCrash/KSCrashReportFilterStringify.h>
#import <KSCrash/KSCrashReportFilterAppleFmt.h>
#import <KSCrash/KSCrashReportFilterGZip.h>
#import <KSCrash/KSCrashReportFields.h>
#import <KSCrash/KSCrashReportFilterDemangle.h>
#import <KSCrash/KSCrashReportFilterDoctor.h>
#import <KSCrash/KSCrashReportFilterAlert.h>
#import <MessageUI/MessageUI.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import "MonalAppDelegate.h"
#import "MLCrashReporter.h"

#define PART_SEPARATOR_FORMAT "\n\n-------- d049d576-9bf0-47dd-839f-dee6b07c1df9 -------- %@ -------- d049d576-9bf0-47dd-839f-dee6b07c1df9 --------\n\n"

@interface KSCrashReportFilterMLEmpty: NSObject <KSCrashReportFilter>
@end

@interface KSCrashReportFilterMLAddAuxInfo : NSObject <KSCrashReportFilter>
@end

@interface KSCrashReportFilterMLAddMLLogfile : NSObject <KSCrashReportFilter>
@end

@interface KSCrashReportFilterMLAddProfraw : NSObject <KSCrashReportFilter>
@end


@interface MLCrashReporter() <KSCrashReportFilter, MFMailComposeViewControllerDelegate>
@property (atomic, strong) NSArray* _Nullable kscrashReports;
@property (atomic, strong) KSCrashReportFilterCompletion _Nullable kscrashCompletion;
@end


@implementation MLCrashReporter

+(void) reportPendingCrashes
{
    //send out pending KSCrash reports
    id<KSCrashReportFilter> alertFilter = [[KSCrashReportFilterAlert alloc]
        initWithTitle:NSLocalizedString(@"Crash Detected", @"Crash reporting")
        message:NSLocalizedString(@"The app crashed last time it was launched. Send a crash report? This crash report will likely contain privacy related data (messages, contacts etc.). We will only use it to debug your crash and delete it afterwards!", @"Crash reporting")
        yesAnswer:NSLocalizedString(@"Sure, send it!", @"Crash reporting")
        noAnswer:NSLocalizedString(@"No, thanks", @"Crash reporting")
    ];
    id<KSCrashReportFilter> dummyFilter = [KSCrashReportFilterMLEmpty new];
    NSString* dummyFilterName = @"dummy not printed";
    id<KSCrashReportFilter> auxInfoFilter = [KSCrashReportFilterMLAddAuxInfo new];
    NSString* auxInfoName = @"AUX Info (*.txt)";
    id<KSCrashReportFilter> appleFilter = [[KSCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide];
    NSString* appleName = @"Apple Report (*.crash)";
    id<KSCrashReportFilter> jsonFilter = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KSCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
        [KSCrashReportFilterStringify new]
    ]];
    NSString* jsonName = @"JSON Report (*.json)";
    id<KSCrashReportFilter> logfileFilter = [KSCrashReportFilterMLAddMLLogfile new];
    NSString* logfileName = @"Logfile (*.rawlog.gz)";
    id<KSCrashReportFilter> profrawFilter = [KSCrashReportFilterMLAddProfraw new];
    NSString* profrawName = @"Profile (*.profraw)";
    KSCrash.sharedInstance.reportStore.sink = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        alertFilter,
        [KSCrashReportFilterDemangle new],
        [KSCrashReportFilterDoctor new],
        [[KSCrashReportFilterCombine alloc] initWithFilters:@{
            dummyFilterName: dummyFilter,       //this dummy is needed to make the filter framework print the title of our aux data
            auxInfoName: auxInfoFilter,
            appleName: appleFilter,
            jsonName: jsonFilter,
            logfileName: logfileFilter,
            profrawName: profrawFilter,
        }],
        [[KSCrashReportFilterConcatenate alloc] initWithSeparatorFmt:@PART_SEPARATOR_FORMAT keys:@[
            dummyFilterName,
            auxInfoName,
            appleName,
            jsonName,
            logfileName,
            profrawName,
        ]],
        [KSCrashReportFilterStringToData new],
        [[KSCrashReportFilterGZipCompress alloc] initWithCompressionLevel:KSCrashReportCompressionLevelDefault],
        [self new],                             //add this class as filter to send out all stuff via mail
    ]];
    DDLogVerbose(@"Trying to send crash reports...");
    [KSCrash.sharedInstance.reportStore sendAllReportsWithCompletion:^(NSArray* reports, NSError* error) {
        if(error == nil)
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
        kscrash_callCompletion(onCompletion, reports, nil);
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

        kscrash_callCompletion(onCompletion, reports,
                                 [KSNSErrorHelper errorWithDomain:[[self class] description]
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
    [mailController setMessageBody:@"Please fill in your last actions that led to this crash:\n" isHTML:NO];
    int i = 1;
    for(id<KSCrashReport> report_ in reports)
    {
        if(![report_ isKindOfClass:[KSCrashReportData class]])
            DDLogError(@"Report was of unsupported data type %@", [report_ class]);
        else
        {
            DDLogVerbose(@"Adding mail attachment...");
            [mailController addAttachmentData:[report_ untypedValue] mimeType:@"binary" fileName:[NSString stringWithFormat:@"CrashReport-%d.mcrash.gz", i++]];
        }
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
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, nil);
                break;
            case MFMailComposeResultSaved:
                DDLogInfo(@"Crash report send result: MFMailComposeResultSaved");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, nil);
                break;
            case MFMailComposeResultCancelled:
                DDLogInfo(@"Crash report send result: MFMailComposeResultCancelled");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports,
                                        [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                            code:0
                                                    description:@"User cancelled"]);
                break;
            case MFMailComposeResultFailed:
                DDLogInfo(@"Crash report send result: MFMailComposeResultFailed");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports, error);
                break;
            default:
            {
                DDLogInfo(@"Crash report send result: unknown");
                kscrash_callCompletion(self.kscrashCompletion, self.kscrashReports,
                                        [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                            code:0
                                                    description:@"Unknown MFMailComposeResult: %d", result]);
            }
        }
        
        self.kscrashCompletion = nil;
        self.kscrashReports = nil;
    });
}

@end

@implementation KSCrashReportFilterMLEmpty

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLEmpty started...");
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSUInteger i = 0; i < reports.count; i++)
        [filteredReports addObject:[KSCrashReportString reportWithValue:@""]];
    DDLogVerbose(@"KSCrashReportFilterMLEmpty finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KSCrashReportFilterMLAddAuxInfo

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLAddAuxInfo started...");
    NSMutableArray<id<KSCrashReport>>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSDictionary* report = [report_ untypedValue];
        NSMutableString* auxData = [NSMutableString new];
        
        //add version of monal reporting this crash
        [auxData appendString:[NSString stringWithFormat:@"reporterVersion: %@\n", [HelperTools appBuildVersionInfoFor:MLVersionTypeLog]]];
        
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
        
        [filteredReports addObject:[KSCrashReportString reportWithValue:auxData]];
    }
    DDLogVerbose(@"KSCrashReportFilterMLAddAuxInfo finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KSCrashReportFilterMLAddMLLogfile

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLAddMLLogfile started...");
    NSMutableArray<id<KSCrashReport>>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSDictionary* report = [report_ untypedValue];
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
        [filteredReports addObject:[KSCrashReportString reportWithValue:[HelperTools hexadecimalString:logfileData]]];
    }
    DDLogVerbose(@"KSCrashReportFilterMLAddMLLogfile finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KSCrashReportFilterMLAddProfraw

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLAddProfraw started...");
    NSMutableArray<id<KSCrashReport>>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSDictionary* report = [report_ untypedValue];
        NSString* profileCopy = report[@"user"][@"profileCopy"];
        NSData* profileData = [NSData new];
        if(profileCopy != nil)
        {
            DDLogDebug(@"Adding profile copy of '%@' from '%@' to crash report...", report[@"user"][@"currentProfile"], report[@"user"][@"profileCopy"]);
            profileData = [NSData dataWithContentsOfFile:profileCopy];
            DDLogVerbose(@"NSData of profile copy: %@", profileData);
            NSError* error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:profileCopy error:&error];
            if(error != nil)
                DDLogError(@"Failed to delete profileCopy: %@", error);
            if(profileData == nil)
                profileData = [NSData new];
        }
        DDLogVerbose(@"Converting profile data to hex...");
        [filteredReports addObject:[KSCrashReportString reportWithValue:[HelperTools hexadecimalString:profileData]]];
    }
    DDLogVerbose(@"KSCrashReportFilterAddProfile finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
