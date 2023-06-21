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
#import <KSCrash/KSCrashReportFilterAlert.h>
#import <KSCrash/NSError+SimpleConstructor.h>
#import <MessageUI/MessageUI.h>
#import "MLConstants.h"
#import "HelperTools.h"
#import "MLCrashReporter.h"

#define PART_SEPARATOR_FORMAT "\n\n-------- d049d576-9bf0-47dd-839f-dee6b07c1df9 -------- %@ -------- d049d576-9bf0-47dd-839f-dee6b07c1df9 --------\n\n"

@interface KSCrashReportFilterEmpty: NSObject <KSCrashReportFilter>
+(KSCrashReportFilterEmpty*) filter;
@end

@interface KSCrashReportFilterAddAuxInfo : NSObject <KSCrashReportFilter>
+(KSCrashReportFilterAddAuxInfo*) filter;
@end

@interface KSCrashReportFilterAddMLLogfile : NSObject <KSCrashReportFilter>
+(KSCrashReportFilterAddMLLogfile*) filter;
@end


@interface MLCrashReporter() <KSCrashReportFilter, MFMailComposeViewControllerDelegate>
@property (atomic, strong) UIViewController* viewController;
@property (atomic, strong) NSArray* _Nullable kscrashReports;
@property (atomic, strong) KSCrashReportFilterCompletion _Nullable kscrashCompletion;
@end


@implementation MLCrashReporter

+(void) reportPendingCrashesWithViewController:(UIViewController*) viewController
{
    //send out pending KSCrash reports
    KSCrash* handler = [KSCrash sharedInstance];
    handler.deleteBehaviorAfterSendAll = KSCDeleteAlways;
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
                        [KSCrashReportFilterAlert
                            filterWithTitle:NSLocalizedString(@"Crash Detected", @"Crash reporting")
                            message:NSLocalizedString(@"The app crashed last time it was launched. Send a crash report? This crash report will contain privacy related data. We will only use it to debug your crash and delete it afterwards!", @"Crash reporting")
                            yesAnswer:NSLocalizedString(@"Sure, send it!", @"Crash reporting")
                            noAnswer:NSLocalizedString(@"No, thanks", @"Crash reporting")
                        ],
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
                        [[self alloc] initWithViewController:viewController],           //this is the last filter sending out all stuff via mail
                        nil
                   ];
    [handler sendAllReportsWithCompletion:^(NSArray* reports, BOOL completed, NSError* error){
        if(completed)
            DDLogWarn(@"Sent %d reports", (int)[reports count]);
        else
            DDLogError(@"Failed to send reports: %@", error);
    }];
}

-(id) initWithViewController:(UIViewController*) viewController
{
    self = [super init];
    self.viewController = viewController;
    return self;
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(![MFMailComposeViewController canSendMail])
    {
        UIAlertController* alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Email Error", @"Crash report error dialog")
                                                                       message:NSLocalizedString(@"This device is not configured to send email.", @"Crash report error dialog")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Crash report error dialog")
                                                            style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alertController addAction:okAction];
        [self.viewController presentViewController:alertController animated:YES completion:NULL];

        kscrash_callCompletion(onCompletion, reports, NO,
                                 [NSError errorWithDomain:[[self class] description]
                                                     code:0
                                              description:NSLocalizedString(@"E-Mail not enabled on device", @"Crash report error dialog")]);
        return;
    }
    
    self.kscrashCompletion = onCompletion;
    self.kscrashReports = reports;

    MFMailComposeViewController* mailController = [[MFMailComposeViewController alloc] init];
    mailController.mailComposeDelegate = self;
    [mailController setToRecipients:@[@"info@monal-im.org"]];
    [mailController setSubject:@"Crash Reports"];
    [mailController setMessageBody:@"Monal crashed, last actions that led to this crash:\n" isHTML:NO];
    int i = 1;
    for(NSData* report in reports)
        if(![report isKindOfClass:[NSData class]])
            DDLogError(@"Report was of unsupported data type %@", [report class]);
        else
            [mailController addAttachmentData:report mimeType:@"binary" fileName:[NSString stringWithFormat:@"CrashReport-%d.txt.gz", i++]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.viewController presentViewController:mailController animated:YES completion:nil];
    });
}

-(void) mailComposeController:(__unused MFMailComposeViewController*) mailController didFinishWithResult:(MFMailComposeResult) result error:(NSError*) error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.viewController dismissViewControllerAnimated:YES completion:nil];

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

@implementation KSCrashReportFilterEmpty

+(KSCrashReportFilterEmpty*) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSUInteger i = 0; i < reports.count; i++)
        [filteredReports addObject:@""];
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterAddAuxInfo

+(KSCrashReportFilterAddAuxInfo*) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        NSMutableString* auxData = [NSMutableString new];
        
        //add user data to aux data
        for(NSString* userKey in report[@"user"])
            [auxData appendString:[NSString stringWithFormat:@"%@: %@\n", userKey, report[@"user"][userKey]]];
        
        //add crash_info_message and crash_info_message2 to aux data
        for(NSDictionary* binaryImage in report[@"binary_images"])
        {
            if(binaryImage[@"crash_info_message"] != nil)
                [auxData appendString:[NSString stringWithFormat:@"%@: %@\n", binaryImage[@"name"], binaryImage[@"crash_info_message"]]];
            if(binaryImage[@"crash_info_message2"] != nil)
                [auxData appendString:[NSString stringWithFormat:@"%@: %@\n", binaryImage[@"name"], binaryImage[@"crash_info_message2"]]];
        }
        
        [filteredReports addObject:auxData];
    }
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterAddMLLogfile

+(KSCrashReportFilterAddMLLogfile*) filter
{
    return [[self alloc] init];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
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
        [filteredReports addObject:[HelperTools hexadecimalString:logfileData]];
    }
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end
