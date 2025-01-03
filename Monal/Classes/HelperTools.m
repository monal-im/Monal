//
//  HelperTools.m
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#include <stdio.h>
#include <assert.h>
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/mach_traps.h>
#include <os/proc.h>
#include <objc/runtime.h> 
#include <objc/message.h>
#include <objc/objc-exception.h>
#import <sys/qos.h>
#import <BackgroundTasks/BackgroundTasks.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <MapKit/MapKit.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <KSCrash/KSCrash.h>
#import <KSCrash/KSCrashC.h>
//can not be imported, use extern declaration instead
//#import <KSCrash/Recording/KSCrashReportStore.h>
extern int64_t kscrs_getNextCrashReport(char* crashReportPathBuffer);
#import <monalxmpp/monalxmpp-Swift.h>
#import "hsluv.h"
#import "HelperTools.h"
#import "MLXMPPManager.h"
#import "MLPubSub.h"
#import "MLUDPLogger.h"
#import "MLHandler.h"
#import "MLBasePaser.h"
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
#import "MLFiletransfer.h"
#import "DataLayer.h"
#import "OmemoState.h"
#import "MLUDPLogger.h"
#import "MLStreamRedirect.h"
#import "commithash.h"
#import "MLContactSoftwareVersionInfo.h"
#import "IPC.h"
#import "MLDelayableTimer.h"
#import "Quicksy_Country.h"

@import UserNotifications;
@import CoreImage;
@import CoreImage.CIFilterBuiltins;
@import UIKit;
@import AVFoundation;
@import UniformTypeIdentifiers;
@import QuickLookThumbnailing;

@interface KSCrash()
@property(nonatomic,readwrite,retain) NSString* basePath;
@end

@interface MLDelayableTimer()
-(void) invalidate;
@end

@interface NSUserDefaults (SerializeNSObject)
-(id) swizzled_objectForKey:(NSString*) defaultName;
-(void) swizzled_setObject:(id) value forKey:(NSString*) defaultName;
@end

//make method visible
@interface DDLog()
-(void) queueLogMessage:(DDLogMessage*) logMessage asynchronously:(BOOL) asyncFlag;
@end

@interface DDLog (AllowQueueFreeze)
-(void) swizzled_queueLogMessage:(DDLogMessage*) logMessage asynchronously:(BOOL) asyncFlag;
@end

static char* _crashBundleName = "UnifiedReport";
static NSString* _processID;
static DDFileLogger* _fileLogger = nil;
static uint64_t _nextCrashId = 0;
static char _origLogfilePath[1024] = "";
static char _logfilePath[1024] = "";
static char _origProfilePath[1024] = "";
static char _profilePath[1024] = "";
static NSObject* _isAppExtensionLock = nil;
static NSObject* _suspensionHandling_lock = nil;
static BOOL _suspensionHandling_isSuspended = NO;
static NSMutableDictionary* _versionInfoCache;
static MLStreamRedirect* _stdoutRedirector = nil;
static MLStreamRedirect* _stderrRedirector = nil;
static volatile void (*_oldExceptionHandler)(NSException*) = NULL;
#if TARGET_OS_MACCATALYST
static objc_exception_preprocessor _oldExceptionPreprocessor = NULL;
#endif

//shamelessly stolen from utils.ip in conversations source
static NSRegularExpression* IPV4;
static NSRegularExpression* IPV6_HEX4DECCOMPRESSED;
static NSRegularExpression* IPV6_6HEX4DEC;
static NSRegularExpression* IPV6_HEXCOMPRESSED;
static NSRegularExpression* IPV6;

//add own crash info (used by rust panic handler)
//see https://alastairs-place.net/blog/2013/01/10/interesting-os-x-crash-report-tidbits/
//and kscrash sources (KSDynamicLinker.c)
#pragma pack(8)
static struct {
    unsigned version;
    const char* message;
    const char* signature;
    const char* backtrace;
    const char* message2;
    void* reserved;
    void* reserved2;
    void* reserved3; // First introduced in version 5
} _crash_info __attribute__((section("__DATA, __crash_info"))) = { 5, 0, 0, 0, 0, 0, 0, 0 };
#pragma pack()


void exitLogging(void)
{
    DDLogInfo(@"exit() was called...");
    [HelperTools flushLogsWithTimeout:0.250];
    return;
}

// see: https://developer.apple.com/library/archive/qa/qa1361/_index.html
// Returns true if the current process is being debugged (either 
// running under the debugger or has a debugger attached post facto).
bool isDebugerActive(void)
{
    int                 junk;
    int                 mib[4];
    struct kinfo_proc   info;
    size_t              size;

    // Initialize the flags so that, if sysctl fails for some bizarre 
    // reason, we get a predictable result.
    info.kp_proc.p_flag = 0;

    // Initialize mib, which tells sysctl the info we want, in this case
    // we're looking for information about a specific process ID.
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();

    // Call sysctl
    size = sizeof(info);
    junk = sysctl(mib, sizeof(mib) / sizeof(*mib), &info, &size, NULL, 0);
    assert(junk == 0);

    // We're being debugged if the P_TRACED flag is set.
    return ( (info.kp_proc.p_flag & P_TRACED) != 0 );
}

//see https://stackoverflow.com/a/2180788
int asyncSafeCopyFile(const char* from, const char* to)
{
    int fd_to, fd_from;
    char buf[1024];
    ssize_t nread;
    int saved_errno;

    fd_from = open(from, O_RDONLY);
    if (fd_from < 0)
        return -1;

    fd_to = open(to, O_WRONLY | O_CREAT | O_EXCL, 0660);
    if (fd_to < 0)
        goto out_error;

    while((nread = read(fd_from, buf, sizeof buf)) > 0)
    {
        char *out_ptr = buf;
        ssize_t nwritten;

        do {
            nwritten = write(fd_to, out_ptr, nread);

            if (nwritten >= 0)
            {
                nread -= nwritten;
                out_ptr += nwritten;
            }
            else if (errno != EINTR)
            {
                goto out_error;
            }
        } while (nread > 0);
    }

    if (nread == 0)
    {
        if (close(fd_to) < 0)
        {
            fd_to = -1;
            goto out_error;
        }
        close(fd_from);

        /* Success! */
        return 0;
    }

out_error:
    saved_errno = errno;

    close(fd_from);
    if (fd_to >= 0)
        close(fd_to);

    errno = saved_errno;
    return -1;
}

static void addFilePathWithSize(const KSCrashReportWriter* writer, char* name, char* filePath)
{
    struct stat st;
    char name_size[64];
    strncpy(name_size, name, 64);
    name_size[63] = '\0';
    strncat(name_size, "_size", 64);
    name_size[63] = '\0';
    
    writer->addStringElement(writer, name, filePath);
    stat(filePath, &st);
    writer->addIntegerElement(writer, name_size, st.st_size);
}

static void crash_callback(const KSCrashReportWriter* writer)
{
    //copy current logfile
    int logfileCopyRetval = asyncSafeCopyFile(_origLogfilePath, _logfilePath);
    int errnoLogfileCopy = errno;
    writer->addStringElement(writer, "logfileCopied", "YES");
    writer->addIntegerElement(writer, "logfileCopyResult", logfileCopyRetval);
    writer->addIntegerElement(writer, "logfileCopyErrno", errnoLogfileCopy);
    addFilePathWithSize(writer, "logfileCopy", _logfilePath);
    //this comes last to make sure we see size differences if the logfile got written during crash data collection (could be other processes)
    addFilePathWithSize(writer, "currentLogfile", _origLogfilePath);
    
    //copy current profiling file (see https://leodido.dev/demystifying-profraw/)
    int profileCopyRetval = asyncSafeCopyFile(_origProfilePath, _profilePath);
    int errnoProfileCopy = errno;
    writer->addStringElement(writer, "profileCopied", "YES");
    writer->addIntegerElement(writer, "profileCopyResult", profileCopyRetval);
    writer->addIntegerElement(writer, "profileCopyErrno", errnoProfileCopy);
    addFilePathWithSize(writer, "profileCopy", _profilePath);
    //this comes last to make sure we see size differences if the logfile got written during crash data collection (could be other processes)
    addFilePathWithSize(writer, "currentProfile", _origProfilePath);
}

void logException(NSException* exception)
{
#if TARGET_OS_MACCATALYST
    NSString* prefix = @"POSSIBLE_CRASH";
#else
    NSString* prefix = @"CRASH";
#endif
    //log error and flush all logs
    DDLogWarn(@"Crash pending!!!");
    [DDLog flushLog];
    DDLogError(@"*****************\n%@(%@): %@\nUserInfo: %@\nStack Trace: %@", prefix, [exception name], [exception reason], [exception userInfo], [exception callStackSymbols]);
    [DDLog flushLog];
    DDLogWarn(@"Crash logged!!!");
    [HelperTools flushLogsWithTimeout:0.250];
}

void uncaughtExceptionHandler(NSException* exception)
{
    logException(exception);

    //don't report that crash through KSCrash if the debugger is active
//     if(isDebugerActive())
//     {
//         DDLogError(@"Not reporting crash through KSCrash: debugger is active!");
//         return;
//     }
    
    //make sure this crash will be recorded by kscrash using the NSException rather than the c++ exception thrown by the objc runtime
    //this will make sure that the stacktrace matches the objc exception rather than being a top level c++ stacktrace
    KSCrash.sharedInstance.uncaughtExceptionHandler(exception);
}

//this function will only be in use under macos alpha builds to log every exception (even when catched with @try-@catch constructs)
#if TARGET_OS_MACCATALYST
static id preprocess(id exception)
{
    id preprocessed = exception;
    if(_oldExceptionPreprocessor != NULL)
        preprocessed = _oldExceptionPreprocessor(exception);
    logException(preprocessed);
    return preprocessed;
}
#endif

void swizzle(Class c, SEL orig, SEL new)
{
    Method origMethod = class_getInstanceMethod(c, orig);
    Method newMethod = class_getInstanceMethod(c, new);
    if(class_addMethod(c, orig, method_getImplementation(newMethod), method_getTypeEncoding(newMethod)))
        class_replaceMethod(c, new, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    else
        method_exchangeImplementations(origMethod, newMethod);
}

static void notification_center_logging(CFNotificationCenterRef center, void* observer, CFStringRef name, const void* object, CFDictionaryRef userInfo)
{
    DDLogDebug(@"NSNotification %@ with %@: %@", name, object, userInfo);
}

@implementation WeakContainer
-(id) initWithObj:(id) obj
{
    self = [super init];
    self.obj = obj;
    return self;
}
@end

@implementation DDLogMessage(TaggedMessage)
@dynamic ml_isDirect;
-(void) setMl_isDirect:(BOOL) value
{
    objc_setAssociatedObject(self, @selector(ml_isDirect), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
-(BOOL) ml_isDirect
{
    return ((NSNumber*)objc_getAssociatedObject(self, @selector(ml_isDirect))).boolValue;
}
@end

@implementation NSUserDefaults (SerializeNSObject)
-(id) swizzled_objectForKey:(NSString*) defaultName
{
    //this will call the original not this one, because of swizzling!
    id data = [self swizzled_objectForKey:defaultName];
    //always unserialize this: every real NSData should be serialized to NSData (e.g. an NSData containing a serialized NSData)
    //and therefore any exception thrown by unserialize of not serialized data should never happen as it is an implementation error in Monal
    if([data isKindOfClass:[NSData class]])
    {
        @try {
            return [HelperTools unserializeData:data];
        } @catch (NSException* exception) {
            NSMutableDictionary* userInfo = [NSMutableDictionary dictionaryWithDictionary:nilDefault(exception.userInfo, @{})];
            [userInfo addEntriesFromDictionary:@{@"userDefaultsName":defaultName}];
            @throw [NSException exceptionWithName:exception.name reason:exception.reason userInfo:userInfo];
        }
    }
    return data;
}

-(void) swizzled_setObject:(id) value forKey:(NSString*) defaultName
{
    id toSave = value;
    //these are the default datatypes/class clusters already handled by NSUserDefaults
    //(NSData gets a special handling by us and is therefore not listed here)
    if(
        [value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSDate class]] ||
        [value isKindOfClass:[NSURL class]] ||
        [value isKindOfClass:[NSDictionary class]] ||
        [value isKindOfClass:[NSMutableDictionary class]] ||
        [value isKindOfClass:[NSArray class]] ||
        [value isKindOfClass:[NSMutableArray class]] ||
        value == nil
    )
        ;       //do nothing, already handled by original NSUserDefaults method
    //every NSData should be double serialized (see swizzled_objectForKey: above for a detailed explanation)
    //everything else will just be (single) serialized to NSData
    else
        toSave = [HelperTools serializeObject:value];
    return [self swizzled_setObject:toSave forKey:defaultName];
}

//see https://stackoverflow.com/a/13326633 and https://fek.io/blog/method-swizzling-in-obj-c-and-swift/
+(void) load
{
    if(self == NSUserDefaults.self)
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            swizzle([self class], @selector(objectForKey:), @selector(swizzled_objectForKey:));
            swizzle([self class], @selector(setObject:forKey:), @selector(swizzled_setObject:forKey:));
        });
    }
}
@end

@implementation DDLog (AllowQueueFreeze)

-(void) swizzled_queueLogMessage:(DDLogMessage*) logMessage asynchronously:(BOOL) asyncFlag
{
    //make sure this method remains performant even when checking for udp logging presence
    static BOOL udpLoggerEnabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        udpLoggerEnabled = [[HelperTools defaultsDB] boolForKey:@"udpLoggerEnabled"];
    });
    
    //use udp logger to log all messages, even if the loggging queue is in suspended state
    //this hopefully enables us to catch strange bugs sometimes hanging and then watchdog-killing the app when resuming from resumption
    if(udpLoggerEnabled && _suspensionHandling_isSuspended)
    {
        //this marks a message as already directly logged to allow the udp logger to later ignore the queued log request for the same message
        logMessage.ml_isDirect = YES;
        //make sure all udp log messages are still logged chronologically and prevent race conditions with our static counter var
        dispatch_async([MLUDPLogger getCurrentInstance].loggerQueue, ^{
            [MLUDPLogger directlyWriteLogMessage:logMessage];
        });
    }
    
    //don't do sync logging for any message (usually ERROR), while the global logging queue is suspended
    //don't use _suspensionHandling_lock here because that can introduce deadlocks
    //(for example if we have log statements in our MLLogFileManager code rotating the logfile and creating a new one)
    return [self swizzled_queueLogMessage:logMessage asynchronously:_suspensionHandling_isSuspended ? YES : asyncFlag];
}

//see https://stackoverflow.com/a/13326633 and https://fek.io/blog/method-swizzling-in-obj-c-and-swift/
+(void) load
{
    if(self == DDLog.self)
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            swizzle([self class], @selector(queueLogMessage:asynchronously:), @selector(swizzled_queueLogMessage:asynchronously:));
        });
    }
}

@end

@implementation HelperTools

+(void) initialize
{
    _suspensionHandling_lock = [NSObject new];
    _suspensionHandling_isSuspended = NO;
    _isAppExtensionLock = [NSObject new];
    _versionInfoCache = [NSMutableDictionary new];
    
    u_int32_t i = arc4random();
    _processID = [self hexadecimalString:[NSData dataWithBytes:&i length:sizeof(i)]];
    
    //shamelessly stolen from utils.ip in conversations source
    IPV4 = [NSRegularExpression regularExpressionWithPattern:@"\\A(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)(\\.(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)){3}\\z" options:0 error:nil];
    IPV6_HEX4DECCOMPRESSED = [NSRegularExpression regularExpressionWithPattern:@"\\A((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) ::((?:[0-9A-Fa-f]{1,4}:)*)(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)(\\.(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)){3}\\z" options:0 error:nil];
    IPV6_6HEX4DEC = [NSRegularExpression regularExpressionWithPattern:@"\\A((?:[0-9A-Fa-f]{1,4}:){6,6})(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)(\\.(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)){3}\\z" options:0 error:nil];
    IPV6_HEXCOMPRESSED = [NSRegularExpression regularExpressionWithPattern:@"\\A((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)::((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)\\z" options:0 error:nil];
    IPV6 = [NSRegularExpression regularExpressionWithPattern:@"\\A(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\\z" options:0 error:nil];
}

+(void) installExceptionHandler
{
    //only install our exception handler if not yet installed
    _oldExceptionHandler = (volatile void (*)(NSException*))NSGetUncaughtExceptionHandler();
    if((void*)_oldExceptionHandler != (void*)uncaughtExceptionHandler)
    {
        DDLogVerbose(@"Replaced unhandled exception handler, old handler: %p, new handler: %p", NSGetUncaughtExceptionHandler(), &uncaughtExceptionHandler);
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler);
    }
    
#if TARGET_OS_MACCATALYST
    //this is needed for catalyst because catalyst apps are based on NSApplication which will swallow exceptions on the main thread and just continue
    //see: https://stackoverflow.com/questions/3336278/why-is-raising-an-nsexception-not-bringing-down-my-application
    //obj exception handling explanation: https://stackoverflow.com/a/28391007/3528174
    //objc exception implementation: https://opensource.apple.com/source/objc4/objc4-818.2/runtime/objc-exception.mm.auto.html
    //objc exception header: https://opensource.apple.com/source/objc4/objc4-818.2/runtime/objc-exception.h.auto.html
    //example C++ exception ABI: https://github.com/nicolasbrailo/cpp_exception_handling_abi/tree/master/abi_v12
    
    //this will log the exception
    if(_oldExceptionPreprocessor == NULL)
        _oldExceptionPreprocessor = objc_setExceptionPreprocessor(preprocess);
    
    //this will stop the swallowing
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"NSApplicationCrashOnExceptions": @YES}];
#endif
}

+(void) __attribute__((noreturn)) MLAssertWithText:(NSString*) text andUserData:(id) userInfo andFile:(const char* const) file andLine:(int) line andFunc:(const char* const) func
{
    NSString* fileStr = [self sanitizeFilePath:file];
    DDLogError(@"Assertion triggered at %@:%d in %s", fileStr, line, func);
    @throw [NSException exceptionWithName:[NSString stringWithFormat:@"MLAssert triggered at %@:%d in %s with reason '%@' and userInfo: %@", fileStr, line, func, text, userInfo] reason:text userInfo:userInfo];
}

+(void) __attribute__((noreturn)) handleRustPanicWithText:(NSString*) text andBacktrace:(NSString*) backtrace
{
    NSString* abort_msg = [NSString stringWithFormat:@"RUST_PANIC: %@", text];
    
    //set crash_info_message in DATA section of our binary image
    //see https://alastairs-place.net/blog/2013/01/10/interesting-os-x-crash-report-tidbits/
    _crash_info.message = abort_msg.UTF8String;
    _crash_info.signature = abort_msg.UTF8String;       //use signature for apple crash reporter which does not handle message field
    _crash_info.backtrace = backtrace.UTF8String;
    
    //log error and flush all logs
    [DDLog flushLog];
    DDLogError(@"*****************\n%@\n%@", abort_msg, backtrace);
    [DDLog flushLog];
    [HelperTools flushLogsWithTimeout:0.250];
    
    //now abort everything
    abort();
}

+(void) __attribute__((noreturn)) throwExceptionWithName:(NSString*) name reason:(NSString*) reason userInfo:(NSDictionary* _Nullable) userInfo
{
    @throw [NSException exceptionWithName:name reason:reason userInfo:userInfo];
}

+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere andDisableAccount:(BOOL) disableAccount
{
    [self postError:description withNode:node andAccount:account andIsSevere:isSevere];
    
    //disconnect and reset state (including pipelined auth etc.)
    //this has to be done before disabling the account to not trigger an assertion
    [[MLXMPPManager sharedInstance] disconnectAccount:account.accountID withExplicitLogout:YES];

    //make sure we don't try this again even when the mainapp/appex gets restarted
    NSMutableDictionary* accountDic = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountID] copyItems:YES];
    accountDic[kEnabled] = @NO;
    [[DataLayer sharedInstance] updateAccounWithDictionary:accountDic];    
}

+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere
{
    NSString* message = description;
    if(node)
        message = [HelperTools extractXMPPError:node withDescription:description];
    DDLogError(@"Notifying user about %@ error: %@", isSevere ? @"SEVERE" : @"non-severe", message);
    [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:account userInfo:@{@"message": message, @"isSevere":@(isSevere)}];
}

+(void) showErrorOnAlpha:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp* _Nullable) account andFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    NSString* fileStr = [self sanitizeFilePath:file];
    NSString* message = description;
    if(node)
        message = [self extractXMPPError:node withDescription:description];
#ifdef IS_ALPHA
    DDLogError(@"Notifying alpha user about error on account %@ at %@:%d in %s: %@", account, fileStr, line, func, message);
    if(account != nil)
        [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:account userInfo:@{@"message": message, @"isSevere":@YES}];
    else
    {
        UNMutableNotificationContent* content = [UNMutableNotificationContent new];
        content.title = @"Global Error";
        content.body = message;
        content.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:nil];
        NSError* error = [self postUserNotificationRequest:request];
        if(error)
            DDLogError(@"Error posting global alpha xmppError notification: %@", error);
    }
#else
    DDLogWarn(@"Ignoring alpha-only error at %@:%d in %s: %@", fileStr, line, func, message);
#endif
}

+(NSString*) extractXMPPError:(XMPPStanza*) stanza withDescription:(NSString*) description
{
    if(description == nil || [description isEqualToString:@""])
        description = @"XMPP Error";
    NSMutableString* message = [description mutableCopy];
    NSString* errorReason = [stanza findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}!text$"];
    if(errorReason && ![errorReason isEqualToString:@""])
        [message appendString:[NSString stringWithFormat:@": %@", errorReason]];
    NSString* errorText = [stanza findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"];
    if(errorText && ![errorText isEqualToString:@""])
        [message appendString:[NSString stringWithFormat:@" (%@)", errorText]];
    return message;
}

+(void) initSystem
{
    BOOL enableDefaultLogAndCrashFramework = YES;
#if TARGET_OS_SIMULATOR
    // Automatically switch between the debug technique of TMolitor and FAltheide
    enableDefaultLogAndCrashFramework = [[HelperTools defaultsDB] boolForKey:@"udpLoggerEnabled"];
#endif
    if(enableDefaultLogAndCrashFramework)
    {
        [self configureLogging];
        [self installExceptionHandler];
        //don't install KSCrash if the debugger is active
        //if(!isDebugerActive())
            //[self installCrashHandler];
//         else
//             DDLogWarn(@"Not installing crash handler: debugger is active!");
        [self installExceptionHandler];
    }
    else
        [self configureXcodeLogging];
    
    //enable logging of all NSNotifications only on debug builds or if the debug menu was activated
#ifdef DEBUG
    BOOL enableNotificationObserver = YES;
#else
    BOOL enableNotificationObserver = [[HelperTools defaultsDB] boolForKey:@"showLogInSettings"];
#endif
    if(enableNotificationObserver)
    {
        //see https://stackoverflow.com/a/3738387
        CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
            NULL,
            notification_center_logging,
            NULL,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    
    atexit(exitLogging);
    
    //set right path for llvm default.profraw file
    NSString* profrawFilePath = [[HelperTools getContainerURLForPathComponents:@[@"default.profraw"]] path];
    setenv("LLVM_PROFILE_FILE", profrawFilePath.UTF8String, 1);
    
    [SwiftHelpers initSwiftHelpers];
    [self activityLog];
}

+(void) configureDefaultAudioSession
{
    AVAudioSession* audioSession = [AVAudioSession sharedInstance];
    NSError* error;
    DDLogDebug(@"configuring default audio session...");
    AVAudioSessionCategoryOptions options = 0;
    options |= AVAudioSessionCategoryOptionMixWithOthers;
    //options |= AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers;
    //options |= AVAudioSessionCategoryOptionAllowBluetooth;
    //options |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    //options |= AVAudioSessionCategoryOptionAllowAirPlay;
    [audioSession setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:options error:&error];
    if(error != nil)
        DDLogError(@"failed to configure audio session: %@", error);
    [audioSession setActive:YES withOptions:0 error:&error];
    if(error != nil)
        DDLogError(@"error activating audio session: %@", error);
    DDLogVerbose(@"current audio route: %@", audioSession.currentRoute);
}

+(NSDictionary<NSString*, NSString*>*) getInvalidPushServers
{
    return @{
        @"ios13push.monal.im": nilWrapper([[[UIDevice currentDevice] identifierForVendor] UUIDString]),
        @"push.monal.im": nilWrapper([[[UIDevice currentDevice] identifierForVendor] UUIDString]),
        @"us.prod.push.monal-im.org": nilWrapper(nil),
    };
}

+(NSString*) getSelectedPushServerBasedOnLocale
{
#ifdef IS_ALPHA
    return @"alpha.push.monal-im.org";
#else
    return @"eu.prod.push.monal-im.org";
    /*
    if([[[NSLocale currentLocale] countryCode] isEqualToString:@"US"])
    {
        return @"us.prod.push.monal-im.org";
    }
    else
    {
        return @"eu.prod.push.monal-im.org";
    }
    */
#endif
}

+(NSDictionary<NSString*, NSString*>*) getAvailablePushServers
{
    return @{
        //@"us.prod.push.monal-im.org": @"US",
        @"eu.prod.push.monal-im.org": @"Europe",
        @"alpha.push.monal-im.org": @"Alpha/Debug (more Logging)",
#ifdef IS_ALPHA
        @"disabled.push.monal-im.org": @"Disabled - Alpha Test",
#endif
    };
}

+(NSArray<NSString*>*) getFailoverStunServers
{
    return @[
#ifdef IS_ALPHA
        @"stuns:alpha.turn.monal-im.org:443",
        @"stuns:alpha.turn.monal-im.org:3478",
#else
        @"stuns:eu.prod.turn.monal-im.org:443",
        @"stuns:eu.prod.turn.monal-im.org:3478",
#endif
    ];
}

//this wrapper is needed, because MLChatImageCell can't import our monalxmpp-Swift bridging header, but importing HelperTools is okay
+(AnyPromise*) renderUIImageFromSVGURL:(NSURL* _Nullable) url
{
    return [SwiftHelpers _renderUIImageFromSVGURL:url];
}

//this wrapper is needed, because MLChatImageCell can't import our monalxmpp-Swift bridging header, but importing HelperTools is okay
+(AnyPromise*) renderUIImageFromSVGData:(NSData* _Nullable) data
{
    return [SwiftHelpers _renderUIImageFromSVGData:data];
}

+(void) busyWaitForOperationQueue:(NSOperationQueue*) queue
{
    //apparently setting someQueue.suspended = YES does return before the queue is actually suspended
    //--> busy wait for someQueue.suspended == YES
    int busyWaitCounter = 0;
    NSTimeInterval waitTime = 0.0;
    NSDate* startTime = [NSDate date];
    while([queue isSuspended] != YES)
    {
        busyWaitCounter++;
        waitTime = [[NSDate date] timeIntervalSinceDate:startTime];
        MLAssert(waitTime <= 4.0, @"Busy wait for queue freeze took longer than 4.0 seconds!", (@{@"queue": queue, @"name": queue.name}));
        
    }
    if(busyWaitCounter > 0)
        DDLogWarn(@"busyWaitFor:%@ --> busyWaitCounter=%d, waitTime=%f", queue.name, busyWaitCounter, waitTime);
}

+(id) getObjcDefinedValue:(MLDefinedIdentifier) identifier
{
    switch(identifier)
    {
        case MLDefinedIdentifier_kAppGroup: return kAppGroup; break;
        case MLDefinedIdentifier_kMonalOpenURL: return kMonalOpenURL; break;
        case MLDefinedIdentifier_kBackgroundProcessingTask: return kBackgroundProcessingTask; break;
        case MLDefinedIdentifier_kBackgroundRefreshingTask: return kBackgroundRefreshingTask; break;
        case MLDefinedIdentifier_kMonalKeychainName: return kMonalKeychainName; break;
        case MLDefinedIdentifier_kMucTypeGroup: return kMucTypeGroup; break;
        case MLDefinedIdentifier_kMucRoleModerator: return kMucRoleModerator; break;
        case MLDefinedIdentifier_kMucRoleNone: return kMucRoleNone; break;
        case MLDefinedIdentifier_kMucRoleParticipant: return kMucRoleParticipant; break;
        case MLDefinedIdentifier_kMucRoleVisitor: return kMucRoleVisitor; break;
        case MLDefinedIdentifier_kMucAffiliationOwner: return kMucAffiliationOwner; break;
        case MLDefinedIdentifier_kMucAffiliationAdmin: return kMucAffiliationAdmin; break;
        case MLDefinedIdentifier_kMucAffiliationMember: return kMucAffiliationMember; break;
        case MLDefinedIdentifier_kMucAffiliationOutcast: return kMucAffiliationOutcast; break;
        case MLDefinedIdentifier_kMucAffiliationNone: return kMucAffiliationNone; break;
        case MLDefinedIdentifier_kMucActionShowProfile: return kMucActionShowProfile; break;
        case MLDefinedIdentifier_kMucActionReinvite: return kMucActionReinvite; break;
        case MLDefinedIdentifier_kMucTypeChannel: return kMucTypeChannel; break;
        case MLDefinedIdentifier_SHORT_PING: return @(SHORT_PING); break;
        case MLDefinedIdentifier_LONG_PING: return @(LONG_PING); break;
        case MLDefinedIdentifier_MUC_PING: return @(MUC_PING); break;
        case MLDefinedIdentifier_BGFETCH_DEFAULT_INTERVAL: return @(BGFETCH_DEFAULT_INTERVAL); break;
        default:
            unreachable(@"unknown MLDefinedIdentifier!");
    }
}

+(NSRunLoop*) getExtraRunloopWithIdentifier:(MLRunLoopIdentifier) identifier
{
    static NSMutableDictionary* runloops = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runloops = [NSMutableDictionary new];
    });
    
    //every identifier has its own thread qos class
    __block NSQualityOfService qos;
    __block char* name;
    switch(identifier)
    {
        case MLRunLoopIdentifierNetwork: qos = NSQualityOfServiceBackground; name = "im.monal.runloop.networking"; break;
        case MLRunLoopIdentifierTimer: qos = NSQualityOfServiceBackground; name = "im.monal.runloop.timer"; break;
        default: unreachable(@"unknown runloop identifier!");
    }
    
    @synchronized(runloops) {
        if(runloops[@(identifier)] == nil)
        {
            NSCondition* condition = [NSCondition new];
            [condition lock];
            NSThread* newRunloopThread = [[NSThread alloc] initWithBlock:^{
                //we don't need an @synchronized block around this because the @synchronized block of the outer thread
                //waits until we signal our condition (e.g. no other thread can race with us)
                NSRunLoop* localLoop = runloops[@(identifier)] = [NSRunLoop currentRunLoop];
                [condition lock];
                [condition signal];
                [condition unlock];
                while(YES)
                {
                    [localLoop run];
                    usleep(10000);          //sleep 10ms if we ever return from our runloop to not consume too much cpu
                }
            }];
            //configure and start thread
            [newRunloopThread setName:[NSString stringWithFormat:@"%s", name]];
            //newRunloopThread.threadPriority = 1.0;
            newRunloopThread.qualityOfService = qos;
            [newRunloopThread start];
            //wait for the new thread to create a new runloop, it will immediately spin the runloop after signalling this condition
            [condition wait];
            [condition unlock];
        }
        return runloops[@(identifier)];
    }
}

+(NSError* _Nullable) hardLinkOrCopyFile:(NSString*) from to:(NSString*) to
{
    NSError* error = nil;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    DDLogVerbose(@"Trying to hardlink file '%@' to '%@'...", from, to);
    [fileManager linkItemAtPath:from toPath:to error:&error];
    if(error)
    {
        DDLogWarn(@"Hardlinking failed, trying normal copy operation: %@", error);
        error = nil;
        [fileManager copyItemAtPath:from toPath:to error:&error];
        if(error)
        {
            DDLogWarn(@"File copy failed, too: %@", error);
            return error;
        }
    }
    return nil;
}

+(NSString*) getQueueThreadLabelFor:(DDLogMessage*) logMessage
{
    NSString* queueThreadLabel = logMessage.threadName;
    if(![queueThreadLabel length])
        queueThreadLabel = logMessage.queueLabel;
    if([@"com.apple.main-thread" isEqualToString:queueThreadLabel])
        queueThreadLabel = @"main";
    if(![queueThreadLabel length])
        queueThreadLabel = logMessage.threadID;

    //remove already appended " (QOS: XXX)" because we want to append the QOS part ourselves
    NSRange range = [queueThreadLabel rangeOfString:@" (QOS: "];
    if(range.length > 0)
        queueThreadLabel = [queueThreadLabel substringWithRange:NSMakeRange(0, range.location)];
    
    return queueThreadLabel;
}

+(NSURL*) getFailoverTurnApiServer
{
    NSString* turnApiServer;
#ifdef IS_ALPHA
    turnApiServer = @"https://alpha.turn.monal-im.org";
#else
    turnApiServer = @"https://eu.prod.turn.monal-im.org";
#endif
    return [NSURL URLWithString:turnApiServer];
}

+(BOOL) shouldProvideVoip
{
    BOOL shouldProvideVoip = NO;
#if TARGET_OS_MACCATALYST
#ifdef IS_ALPHA
    shouldProvideVoip = YES;
#endif
#else
#ifdef IS_QUICKSY
    NSLocale* userLocale = [NSLocale currentLocale];
    shouldProvideVoip = !([userLocale.countryCode containsString: @"CN"] || [userLocale.countryCode containsString: @"CHN"]);
#else
    shouldProvideVoip = YES;
#endif
#endif
    return shouldProvideVoip;
}
    
+(BOOL) isSandboxAPNS
{
#if TARGET_OS_SIMULATOR
    DDLogVerbose(@"APNS environment is: sandbox");
    return YES;
#else
    // check if were are sandbox or production
    NSString* embeddedProvPath;
#if TARGET_OS_MACCATALYST
    NSString* bundleURL = [[NSBundle mainBundle] bundleURL].absoluteString;
    embeddedProvPath = [[[bundleURL componentsSeparatedByString:@"file://"] objectAtIndex:1] stringByAppendingString:@"Contents/embedded.provisionprofile"];
#else
    embeddedProvPath = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
#endif
    DDLogVerbose(@"Loading embedded provision plist at: %@", embeddedProvPath);
    NSError* loadingError;
    NSString* embeddedProvStr = [NSString stringWithContentsOfFile:embeddedProvPath encoding:NSISOLatin1StringEncoding error:&loadingError];
    if(embeddedProvStr == nil)
    {
        // fallback to production
        DDLogWarn(@"Could not read embedded provision (should be production install): %@", loadingError);
        DDLogVerbose(@"APNS environment is: production");
        return NO;
    }
    NSScanner* plistScanner = [NSScanner scannerWithString:embeddedProvStr];
    [plistScanner scanUpToString:@"<plist" intoString:nil];
    NSString* plistStr;
    [plistScanner scanUpToString:@"</plist>" intoString:&plistStr];
    plistStr = [NSString stringWithFormat:@"%@</plist>", plistStr];
    DDLogVerbose(@"Extracted bundle plist string: %@", plistStr);

    NSError* plistError;
    NSPropertyListFormat format;
    NSDictionary* plist = [NSPropertyListSerialization propertyListWithData:[plistStr dataUsingEncoding:NSISOLatin1StringEncoding] options:NSPropertyListImmutable format:&format error:&plistError];
    DDLogVerbose(@"Parsed plist: %@", plist);
    if(plistError != nil)
    {
        // fallback to production
        DDLogWarn(@"Could not parse embedded provision as plist: %@", plistError);
        DDLogVerbose(@"APNS environment is: production");
        return NO;
    }
    if(plist[@"com.apple.developer.aps-environment"] && [@"production" isEqualToString:plist[@"com.apple.developer.aps-environment"]] == NO)
    {
        // sandbox
        DDLogWarn(@"aps-environmnet is set to: %@", plist[@"com.apple.developer.aps-environment"]);
        DDLogVerbose(@"APNS environment is: sandbox");
        return YES;
    }
    if(plist[@"Entitlements"] && [@"production" isEqualToString:plist[@"Entitlements"][@"aps-environment"]] == NO)
    {
        // sandbox
        DDLogWarn(@"aps-environmnet is set to: %@", plist[@"Entitlements"][@"aps-environment"]);
        DDLogVerbose(@"APNS environment is: sandbox");
        return YES;
    }
    // production
    DDLogVerbose(@"APNS environment is: production");
    return NO;
#endif
}

+(int) compareIOcted:(NSData*) data1 with:(NSData*) data2
{
    int result = memcmp(data1.bytes, data2.bytes, min(data1.length, data2.length));
    if(result == 0 && data1.length < data2.length)
        return -1;
    else if(result == 0 && data1.length > data2.length)
        return 1;
    return result;
}

+(NSURL*) getContainerURLForPathComponents:(NSArray*) components
{
    static NSURL* containerUrl;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        containerUrl = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    });
    MLAssert(containerUrl != nil, @"Container URL should never be nil!");
    NSURL* retval = containerUrl;
    for(NSString* component in components)
        retval = [retval URLByAppendingPathComponent:component];
    return retval;
}

+(NSURL*) getSharedDocumentsURLForPathComponents:(NSArray*) components
{
    NSURL* sharedUrl = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    for(NSString* component in components)
        sharedUrl = [sharedUrl URLByAppendingPathComponent:component];
    NSURLComponents* urlComponents = [NSURLComponents componentsWithURL:sharedUrl resolvingAgainstBaseURL:NO];
    urlComponents.scheme = @"shareddocuments";
    return urlComponents.URL;
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
        [OmemoState class],
        [MLContactSoftwareVersionInfo class],
        [Quicksy_Country class],
        [NSUUID class],
        [MLPromise class],
        [NSError class],
    ]] fromData:data error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    return obj;
}

+(NSError* _Nullable) postUserNotificationRequest:(UNNotificationRequest*) request
{
    __block NSError* retval = nil;
    NSCondition* condition = [NSCondition new];
    [condition lock];
    monal_void_block_t cancelTimeout = createTimer(1.0, (^{
        DDLogError(@"Waiting for notification center took more than 1.0 second, continuing anyways");
        [condition lock];
        [condition signal];
        [condition unlock];
    }));
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError* _Nullable error) {
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

+(void) createAVURLAssetFromFile:(NSString*) file havingMimeType:(NSString*) mimeType andFileExtension:(NSString* _Nullable) fileExtension withCompletionHandler:(void(^)(AVURLAsset* _Nullable)) completion
{
    NSURL* fileUrl = [NSURL fileURLWithPath:file];
    if(@available(iOS 17.0, macCatalyst 17.0, *))
    {
        //generate an AVURLAsset using the modern ios 17 method to attach a mime type to an AVURLAsset
        return completion([AVURLAsset URLAssetWithURL:fileUrl options:@{AVURLAssetOverrideMIMETypeKey: mimeType}]);
    }
    
    //TODO: instead of this symlink method hack, we *maybe* could use the AVURLAssetOutOfBandMIMETypeKey in place of
    //TODO: AVURLAssetOverrideMIMETypeKey on ios 16, BUT: that symbol isn't public and may be catched by apple review
    //TODO: (but it makes our code way cleaner than using this symlink stuff)
    DDLogDebug(@"Generating thumbnail with symlink method...");
    if(fileExtension == nil)
    {
        //this will return nil if the mime type isn't known by apple
        fileExtension = [[UTType typeWithMIMEType:mimeType] preferredFilenameExtension];
        //--> bail out if this is still nil
        if(fileExtension == nil)
        {
            DDLogWarn(@"Could not get file extension for file, not creating AVURLAsset...");
            return completion(nil);
        }
    }
    
    NSURL* symlinkUrl = [self getContainerURLForPathComponents:@[
        @"documentCache",
        [NSString stringWithFormat:@"tmp.avurlasset_symlink.%@.%@", fileUrl.lastPathComponent, fileExtension]
    ]];
    NSError* error = nil;
    if([[NSFileManager defaultManager] fileExistsAtPath:symlinkUrl.path])
        [[NSFileManager defaultManager] removeItemAtURL:symlinkUrl error:&error];
    if(error != nil)
    {
        DDLogError(@"Could not delete old leftover symlink file at '%@': %@", symlinkUrl, error);
        return completion(nil);
    }
    [[NSFileManager defaultManager] createSymbolicLinkAtURL:symlinkUrl withDestinationURL:fileUrl error:&error];
    if(error != nil)
    {
        DDLogError(@"Could not create symlink file '%@' pointing to '%@': %@", symlinkUrl, fileUrl, error);
        return completion(nil);
    }
    
    //create the AVURLAsset and invoke the callback using it
    completion([AVURLAsset URLAssetWithURL:fileUrl options:@{}]);
    
    //remove file afterwards and just log errors if removal of symlink fails
    [[NSFileManager defaultManager] removeItemAtURL:symlinkUrl error:&error];
    if(error != nil)
        DDLogError(@"Could not clean up symlink file '%@' pointing to '%@': %@", symlinkUrl, fileUrl, error);
}

+(AnyPromise*) generateVideoThumbnailFromFile:(NSString*) file havingMimeType:(NSString*) mimeType andFileExtension:(NSString* _Nullable) fileExtension
{
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [self createAVURLAssetFromFile:file havingMimeType:mimeType andFileExtension:fileExtension withCompletionHandler:^(AVURLAsset* asset) {
            if(asset == nil)
                return resolve([NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: @"Could not create AVURLAsset"}]);
            
            AVAssetImageGenerator* imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            imageGenerator.appliesPreferredTrackTransform=TRUE;
            CMTime time = CMTimeMakeWithSeconds(1, 600);

            [imageGenerator generateCGImageAsynchronouslyForTime:time completionHandler:^(CGImageRef image, CMTime actualTime, NSError* error) {
                if(error != nil)
                {
                    DDLogError(@"Error generating thumbnail: %@", error);
                    return resolve(error);
                }
                return resolve([UIImage imageWithCGImage:image]);
            }];  
        }];
    }];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcompletion-handler"
+(void) addUploadItemPreviewForItem:(NSURL* _Nullable) url provider:(NSItemProvider* _Nullable) provider andPayload:(NSMutableDictionary*) payload withCompletionHandler:(void(^)(NSMutableDictionary* _Nullable)) completion
{
    void (^useProvider)() = ^() {
        if(provider == nil)
        {
            DDLogWarn(@"Can not creating preview image via item provider, no provider present: using generic doc image instead");
            payload[@"preview"] = [UIImage systemImageNamed:@"doc"];
            [url stopAccessingSecurityScopedResource];
            return completion(payload);
        }
        else
            [provider loadPreviewImageWithOptions:nil completionHandler:^(UIImage*  _Nullable previewImage, NSError* _Null_unspecified error) {
                if(error != nil || previewImage == nil)
                {
                    if(url == nil)
                    {
                        DDLogWarn(@"Error creating preview image via item provider, using generic doc image instead: %@", error);
                        payload[@"preview"] = [UIImage systemImageNamed:@"doc"];
                    }
                }
                else
                {
                    DDLogVerbose(@"Managed to generate thumbnail for url=%@ using loadPreviewImageWithOptions: %@", url, previewImage);
                    payload[@"preview"] = previewImage;
                }
                [url stopAccessingSecurityScopedResource];
                return completion(payload);
            }];
    };
    if(url != nil)
    {
        DDLogVerbose(@"Generating thumbnail for url=%@", url);
        QLThumbnailGenerationRequest* request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:url size:CGSizeMake(64, 64) scale:1.0 representationTypes:QLThumbnailGenerationRequestRepresentationTypeThumbnail];
        NSURL* tmpURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory: YES];
        tmpURL = [tmpURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [QLThumbnailGenerator.sharedGenerator saveBestRepresentationForRequest:request toFileAtURL:tmpURL withContentType:UTTypePNG.identifier completionHandler:^(NSError *error) {
            if(error == nil)
            {
                UIImage* result = [UIImage imageWithContentsOfFile:[url path]];
                [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];      //remove temporary file, we don't need it anymore
                if(result != nil)
                {
                    payload[@"preview"] = result;
                    DDLogVerbose(@"Managed to generate thumbnail for url=%@ using QLThumbnailGenerator: %@", url, result);
                    [url stopAccessingSecurityScopedResource];
                    return completion(payload);     //don't fall through on success
                }
            }
            //if we fall through to this point, either the thumbnail generation or the imageWithContentsOfFile above failed
            //--> try something else
            DDLogVerbose(@"Extracting thumbnail using imageWithContentsOfFile failed, retrying with imageWithContentsOfFile: %@", error);
            UIImage* result = [UIImage imageWithContentsOfFile:[url path]];
            if(result != nil)
            {
                payload[@"preview"] = result;
                DDLogVerbose(@"Managed to generate thumbnail for url=%@ using imageWithContentsOfFile: %@", url, result);
                [url stopAccessingSecurityScopedResource];
                return completion(payload);
            }
            else
            {
                DDLogVerbose(@"Thumbnail generation not successful - reverting to generic image for file: %@", error);
                UIDocumentInteractionController* imgCtrl = [UIDocumentInteractionController interactionControllerWithURL:url];
                if(imgCtrl != nil && imgCtrl.icons.count > 0)
                {
                    payload[@"preview"] = imgCtrl.icons.firstObject;
                    DDLogVerbose(@"Managed to generate thumbnail for url=%@ using generic image for file: %@", url, imgCtrl.icons.firstObject);
                    [url stopAccessingSecurityScopedResource];
                    return completion(payload);
                }
            }
            
            //try to generate video thumbnail
            [self generateVideoThumbnailFromFile:url.path havingMimeType:[UTType typeWithFilenameExtension:url.pathExtension].preferredMIMEType andFileExtension:url.pathExtension].then(^(UIImage* image) {
                payload[@"preview"] = image;
                DDLogVerbose(@"Managed to generate thumbnail for url=%@ using generateVideoThumbnailFromFile: %@", url, image);
                [url stopAccessingSecurityScopedResource];
                return completion(payload);
            }).catch(^(NSError* error) {
                DDLogError(@"Could not create video thumbnail, using provider as last resort: %@", error);
                
                //last resort
                useProvider();
            });
        }];
    }
    else
        useProvider();
}
#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcompletion-handler"
+(void) handleUploadItemProvider:(NSItemProvider*) provider withCompletionHandler:(void(^)(NSMutableDictionary* _Nullable)) completion
{
    NSMutableDictionary* payload = [NSMutableDictionary new];
    //for a list of types, see UTCoreTypes.h in MobileCoreServices framework
    DDLogInfo(@"ShareProvider: %@", provider.registeredTypeIdentifiers);
    if(provider.suggestedName != nil)
        payload[@"filename"] = provider.suggestedName;
    
    void (^prepareFile)(NSURL*) = ^(NSURL* item) {
        NSError* error;
        [item startAccessingSecurityScopedResource];
        [[NSFileCoordinator new] coordinateReadingItemAtURL:item options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL* _Nonnull newURL) {
            DDLogDebug(@"NSFileCoordinator called accessor: %@", newURL);
            payload[@"data"] = [MLFiletransfer prepareFileUpload:newURL];
            //we can not use newURL here, because it will fall out of scope while the preview is rendered in another thread
            return [HelperTools addUploadItemPreviewForItem:item provider:provider andPayload:payload withCompletionHandler:completion];
        }];
        if(error != nil)
        {
            DDLogError(@"Error preparing file coordinator: %@", error);
            payload[@"error"] = error;
            [item stopAccessingSecurityScopedResource];
            return completion(payload);
        }
    };
    
    if([provider hasItemConformingToTypeIdentifier:@"com.apple.mapkit.map-item"])
    {
        // convert map item to geo:
        [provider loadItemForTypeIdentifier:@"com.apple.mapkit.map-item" options:nil completionHandler:^(NSData*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            NSError* err;
            MKMapItem* mapItem = [NSKeyedUnarchiver unarchivedObjectOfClass:[MKMapItem class] fromData:item error:&err];
            if(err != nil || mapItem == nil)
            {
                DDLogError(@"Error extracting mapkit item: %@", err);
                payload[@"error"] = err;
                return completion(payload);
            }
            else
            {
                DDLogInfo(@"Got mapkit item: %@", item);
                payload[@"type"] = @"geo";
                payload[@"data"] = [NSString stringWithFormat:@"geo:%f,%f", mapItem.placemark.coordinate.latitude, mapItem.placemark.coordinate.longitude];
                return [HelperTools addUploadItemPreviewForItem:nil provider:provider andPayload:payload withCompletionHandler:completion];
            }
        }];
    }
    //the apple-private autoloop gif type has a bug that does not allow to load this as normal gif --> try audiovisual content below
    else if([provider hasItemConformingToTypeIdentifier:UTTypeGIF.identifier] && ![provider hasItemConformingToTypeIdentifier:@"com.apple.private.auto-loop-gif"])
    {
        /*
        [provider loadDataRepresentationForTypeIdentifier:UTTypeGIF.identifier completionHandler:^(NSData* data, NSError* error) {
            if(error != nil || data == nil)
            {
                DDLogError(@"Error extracting gif image from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got gif image data: %@", data);
            payload[@"type"] = @"file";
            payload[@"data"] = [MLFiletransfer prepareDataUpload:data withFileExtension:@"gif"];
            return [HelperTools addUploadItemPreviewForItem:nil provider:provider andPayload:payload withCompletionHandler:completion];
        }];
        */
        [provider loadInPlaceFileRepresentationForTypeIdentifier:UTTypeGIF.identifier completionHandler:^(NSURL*  _Nullable item, BOOL isInPlace, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting gif image from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got %@ gif image item: %@", isInPlace ? @"(in place)" : @"(copied)", item);
            payload[@"type"] = @"file";
            return prepareFile(item);
        }];
    }
    else if([provider hasItemConformingToTypeIdentifier:UTTypeAudiovisualContent.identifier])
    {
        [provider loadItemForTypeIdentifier:UTTypeAudiovisualContent.identifier options:nil completionHandler:^(NSURL*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got audiovisual item: %@", item);
            payload[@"type"] = @"audiovisual";
            return prepareFile(item);
        }];
    }
    else if([provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier])
    {
        [provider loadItemForTypeIdentifier:UTTypeImage.identifier options:nil completionHandler:^(NSURL*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                //for example: image shared directly from screenshots
                DDLogWarn(@"Got error, retrying with UIImage: %@", error);
                [provider loadItemForTypeIdentifier:UTTypeImage.identifier options:nil completionHandler:^(UIImage*  _Nullable item, NSError* _Null_unspecified error) {
                    if(error != nil || item == nil)
                    {
                        DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                        payload[@"error"] = error;
                        return completion(payload);
                    }
                    DDLogInfo(@"Got memory image item: %@", item);
                    payload[@"type"] = @"image";
                    if(![[HelperTools defaultsDB] boolForKey:@"uploadImagesOriginal"])
                    {
                        //use prepareUIImageUpload to resize the image to the configured quality
                        payload[@"data"] = [MLFiletransfer prepareUIImageUpload:item];
                    }
                    else
                        payload[@"data"] = [MLFiletransfer prepareDataUpload:UIImagePNGRepresentation(item) withFileExtension:@"png"];
                    payload[@"preview"] = item;
                    return completion(payload);
                }];
            }
            else
            {
                DDLogInfo(@"Got image item: %@", item);
                payload[@"type"] = @"image";
                if(![[HelperTools defaultsDB] boolForKey:@"uploadImagesOriginal"])
                {
                    [item startAccessingSecurityScopedResource];
                    [[NSFileCoordinator new] coordinateReadingItemAtURL:item options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL* _Nonnull newURL) {
                        DDLogDebug(@"NSFileCoordinator called accessor for image: %@", newURL);
                        UIImage* image = [UIImage imageWithContentsOfFile:[newURL path]];
                        DDLogDebug(@"Created UIImage: %@", image);
                        //use prepareUIImageUpload to resize the image to the configured quality (instead of just uploading the raw image file)
                        payload[@"data"] = [MLFiletransfer prepareUIImageUpload:image];
                        //we can not use newURL here, because it will fall out of scope while the preview is rendered in another thread
                        return [HelperTools addUploadItemPreviewForItem:item provider:provider andPayload:payload withCompletionHandler:completion];
                    }];
                }
                else
                    return prepareFile(item);
                if(error != nil)
                {
                    DDLogError(@"Error preparing file coordinator: %@", error);
                    payload[@"error"] = error;
                    [item stopAccessingSecurityScopedResource];
                    return completion(payload);
                }
            }
        }];
    }
    /*else if([provider hasItemConformingToTypeIdentifier:(NSString*)])
    {
    }
    else if([provider hasItemConformingToTypeIdentifier:(NSString*)])
    {
    }*/
    else if([provider hasItemConformingToTypeIdentifier:UTTypeContact.identifier])
    {
        [provider loadItemForTypeIdentifier:UTTypeContact.identifier options:nil completionHandler:^(NSURL*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got contact item: %@", item);
            payload[@"type"] = @"contact";
            return prepareFile(item);
        }];
    }
    else if([provider hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier])
    {
        [provider loadItemForTypeIdentifier:UTTypeFileURL.identifier options:nil completionHandler:^(NSURL*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got file url item: %@", item);
            payload[@"type"] = @"file";
            return prepareFile(item);
        }];
    }
    else if([provider hasItemConformingToTypeIdentifier:(NSString*)@"com.apple.finder.node"])
    {
        [provider loadItemForTypeIdentifier:UTTypeItem.identifier options:nil completionHandler:^(id <NSSecureCoding> item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            if([(NSObject*)item isKindOfClass:[NSURL class]])
            {
                DDLogInfo(@"Got finder file url item: %@", item);
                payload[@"type"] = @"file";
                return prepareFile((NSURL*)item);
            }
            else
            {
                DDLogError(@"Could not extract finder item");
                payload[@"error"] = NSLocalizedString(@"Could not access Finder item!", @"");
                return completion(payload);
            }
        }];
    }
    else if([provider hasItemConformingToTypeIdentifier:UTTypeURL.identifier])
    {
        [provider loadItemForTypeIdentifier:UTTypeURL.identifier options:nil completionHandler:^(NSURL*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got internet url item: %@", item);
            payload[@"type"] = @"url";
            payload[@"data"] = item.absoluteString;
            return [HelperTools addUploadItemPreviewForItem:nil provider:provider andPayload:payload withCompletionHandler:completion];
        }];
    }
    else if([provider hasItemConformingToTypeIdentifier:UTTypePlainText.identifier])
    {
        [provider loadItemForTypeIdentifier:UTTypePlainText.identifier options:nil completionHandler:^(NSString*  _Nullable item, NSError* _Null_unspecified error) {
            if(error != nil || item == nil)
            {
                DDLogError(@"Error extracting item from NSItemProvider: %@", error);
                payload[@"error"] = error;
                return completion(payload);
            }
            DDLogInfo(@"Got direct text item: %@", item);
            payload[@"type"] = @"text";
            payload[@"data"] = item;
            return [HelperTools addUploadItemPreviewForItem:nil provider:provider andPayload:payload withCompletionHandler:completion];
        }];
    }
    else
        return completion(nil);
}
#pragma clang diagnostic pop

//see https://gist.github.com/giaesp/7704753
+(UIImage* _Nullable) rotateImage:(UIImage* _Nullable) image byRadians:(CGFloat) rotation
{
    if(image == nil)
        return nil;
    
    //Calculate Destination Size
    CGAffineTransform t = CGAffineTransformMakeRotation(rotation);
    CGRect sizeRect = (CGRect) {.size = image.size};
    CGRect destRect = CGRectApplyAffineTransform(sizeRect, t);
    
    return [[[UIGraphicsImageRenderer alloc] initWithSize:destRect.size] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        
        //Move the origin to the middle of the image to apply the transformation
        CGContextTranslateCTM(context, destRect.size.width / 2.0f, destRect.size.height / 2.0f);
        CGContextRotateCTM(context, rotation);
        
        //Draw the original image into the transformed context
        [image drawInRect:CGRectMake(-image.size.width / 2.0f, -image.size.height / 2.0f, image.size.width, image.size.height)];
    }];
}

+(UIImage* _Nullable) mirrorImageOnXAxis:(UIImage* _Nullable) image
{
    if(image == nil)
        return nil;
    
    return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        
        //Move the origin to the middle of the image to apply the transformation
        CGContextTranslateCTM(context, image.size.width / 2, image.size.height / 2);
        
        //Apply the y-axis mirroring transform
        CGContextScaleCTM(context, 1.0, -1.0);
        
        //Move the origin back to the bottom left corner
        CGContextTranslateCTM(context, -image.size.width / 2, -image.size.height / 2);
        
        //Draw the original image into the transformed context
        [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    }];
}

+(UIImage* _Nullable) mirrorImageOnYAxis:(UIImage* _Nullable) image
{
    if(image == nil)
        return nil;
    
    return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        
        //Move the origin to the middle of the image to apply the transformation
        CGContextTranslateCTM(context, image.size.width / 2, image.size.height / 2);
        
        //Apply the y-axis mirroring transform
        CGContextScaleCTM(context, -1.0, 1.0);
        
        //Move the origin back to the bottom left corner
        CGContextTranslateCTM(context, -image.size.width / 2, -image.size.height / 2);
        
        //Draw the original image into the transformed context
        [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    }];
}

+(UIImage*) imageWithNotificationBadgeForImage:(UIImage*) image
{
    UIImage* badge = [[UIImage systemImageNamed:@"circle.fill"] imageWithTintColor:UIColor.redColor];

    CGRect imgSize = CGRectMake(0, 0, image.size.width, image.size.height);
    CGRect dotSize = CGRectMake(image.size.width - 7, 0, 7, 7);
    
    return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        [image drawInRect:imgSize];
        [badge drawInRect:dotSize blendMode:kCGBlendModeNormal alpha:1.0];
    }];
}

+(UIImageView*) buttonWithNotificationBadgeForImage:(UIImage*) image hasNotification:(bool) hasNotification withTapHandler: (UITapGestureRecognizer*) handler
{
    UIImageView* result;
    if(hasNotification)
        result = [[UIImageView alloc] initWithImage:[self imageWithNotificationBadgeForImage:image]];
    else
        result = [[UIImageView alloc] initWithImage: image];

    [result addGestureRecognizer:handler];
    return result;
}

+(NSData*) resizeAvatarImage:(UIImage* _Nullable) image withCircularMask:(BOOL) circularMask toMaxBase64Size:(unsigned long) length
{
    if(!image)
        return [NSData new];
    
    int destinationSize = 480;
    int epsilon = 8;
    UIImage* clippedImage = image;
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat new];
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
        cache = [NSMutableDictionary new];
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
    NSMutableString* token = [NSMutableString new];
    NSUInteger counter = 0;
    while(counter < tokenIn.length)
    {
        [token appendString:[NSString stringWithFormat:@"%02x", (unsigned char)tokenBytes[counter]]];
        counter++;
    }
    return token;
}

//proxy to not have full IPC class accessible from UI
+(NSString* _Nullable) exportIPCDatabase
{
    return [[IPC sharedInstance] exportDB];
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
    static NSCache* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
    });
    @synchronized(cache) {
        if([cache objectForKey:jid] != nil)
            return [cache objectForKey:jid];
    }
    
    NSMutableDictionary<NSString*, NSString*>* retval = [NSMutableDictionary new];
    NSArray* parts = [self splitString:jid withSeparator:@"/" andMaxSize:2];
    
    retval[@"user"] = [[parts objectAtIndex:0] lowercaseString];        //intended to not break code that expects lowercase
    if([parts count] > 1 && [[parts objectAtIndex:1] isEqualToString:@""] == NO)
        retval[@"resource"] = [parts objectAtIndex:1];                  //resources are case sensitive
    //there should never be more than one @ char, but just in case: split only at the first one
    parts = [self splitString:retval[@"user"] withSeparator:@"@" andMaxSize:2];
    if([parts count] > 1)
    {
        retval[@"node"] = [[parts objectAtIndex:0] lowercaseString];    //intended to not break code that expects lowercase
        retval[@"host"] = [[parts objectAtIndex:1] lowercaseString];    //intended to not break code that expects lowercase
    }
    else
        retval[@"host"] = [[parts objectAtIndex:0] lowercaseString];    //intended to not break code that expects lowercase
    
    //don't assert to not have a dos vector here, but still log the error
    if([retval[@"host"] isEqualToString:@""])
        DDLogError(@"jid has no host part: %@", jid);
    //assert on sanity check errors (this checks 'host' and 'user' at once because without node host==user)
    //MLAssert(![retval[@"host"] isEqualToString:@""], @"jid has no host part!", @{@"jid": jid});
    
    //sanitize retval
    if([retval[@"node"] isEqualToString:@""])
    {
        [retval removeObjectForKey:@"node"];
        retval[@"user"] = retval[@"host"];      //empty node means user==host
    }
    if([retval[@"resource"] isEqualToString:@""])
        [retval removeObjectForKey:@"resource"];
    
    //cache and return immutable copy
    @synchronized(cache) {
        [cache setObject:[retval copy] forKey:jid];
    }
    return [retval copy];
}

+(BOOL) isContactBlacklistedForEncryption:(MLContact*) contact
{
    BOOL blacklisted = NO;
    //cheogram.com does not support OMEMO encryption as it is a PSTN gateway
    blacklisted = [@"cheogram.com" isEqualToString:[self splitJid:contact.contactJid][@"host"]];
    if(blacklisted)
        DDLogWarn(@"Jid blacklisted for encryption: %@", contact);
    return blacklisted;
}

+(void) removeAllShareInteractionsForAccountID:(NSNumber*) accountID
{
    DDLogInfo(@"Removing share interaction for all contacts on account id %@", accountID);
    for(MLContact* contact in [[DataLayer sharedInstance] contactList])
        if(contact.accountID.intValue == accountID.intValue)
            [contact removeShareInteractions];
}

+(void) scheduleBackgroundTask:(BOOL) force
{
    DDLogInfo(@"Scheduling new BackgroundTask with force=%s...", force ? "yes" : "no");
    [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
        NSError* error;
        if(force)
        {
            //don't cancel existing task because that could delay our next execution
//             //cancel existing task (if any)
//             [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundProcessingTask];
            //new task
            BGProcessingTaskRequest* processingRequest = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBackgroundProcessingTask];
            //do the same like the corona warn app from germany which leads to this hint: https://developer.apple.com/forums/thread/134031
            processingRequest.earliestBeginDate = nil;
            processingRequest.requiresNetworkConnectivity = YES;
            processingRequest.requiresExternalPower = NO;
            if(![[BGTaskScheduler sharedScheduler] submitTaskRequest:processingRequest error:&error])
            {
                // Errorcodes https://stackoverflow.com/a/58224050/872051
                DDLogError(@"Failed to submit BGTask request %@: %@", processingRequest, error);
            }
            else
                DDLogVerbose(@"Success submitting BGTask request %@", processingRequest);
        }
        else
        {
            //cancel existing task (if any)
            [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundRefreshingTask];
            //new task
            BGAppRefreshTaskRequest* refreshingRequest = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:kBackgroundRefreshingTask];
            //on ios<17 do the same like the corona warn app from germany which leads to this hint: https://developer.apple.com/forums/thread/134031
//             if(@available(iOS 17.0, macCatalyst 17.0, *))
//                 refreshingRequest.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:BGFETCH_DEFAULT_INTERVAL];
//             else
                refreshingRequest.earliestBeginDate = nil;
            if(![[BGTaskScheduler sharedScheduler] submitTaskRequest:refreshingRequest error:&error])
            {
                // Errorcodes https://stackoverflow.com/a/58224050/872051
                DDLogError(@"Failed to submit BGTask request %@: %@", refreshingRequest, error);
            }
            else
                DDLogVerbose(@"Success submitting BGTask request %@", refreshingRequest);
        }
    }];
}

+(void) clearSyncErrorsOnAppForeground
{
    NSMutableDictionary* syncErrorsDisplayed = [NSMutableDictionary dictionaryWithDictionary:[[HelperTools defaultsDB] objectForKey:@"syncErrorsDisplayed"]];
    DDLogInfo(@"Clearing syncError notification states: %@", syncErrorsDisplayed);
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
    {
        syncErrorsDisplayed[account.connectionProperties.identity.jid] = @NO;
        //also remove pending or delivered sync error notifications
        //this will delay the delivery of such notifications until 60 seconds after the app moved into the background
        //rather than being delivered  60 seconds after our first sync attempt failed (wether it was in the appex or mainapp)
        NSString* syncErrorIdentifier = [NSString stringWithFormat:@"syncError::%@", account.connectionProperties.identity.jid];
        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[syncErrorIdentifier]];
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[syncErrorIdentifier]];
    }
    [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
}

+(void) removePendingSyncErrorNotifications
{
    NSMutableDictionary* syncErrorsDisplayed = [NSMutableDictionary dictionaryWithDictionary:[[HelperTools defaultsDB] objectForKey:@"syncErrorsDisplayed"]];
    DDLogInfo(@"Removing pending syncError notifications, current state: %@", syncErrorsDisplayed);
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
    {
        NSString* syncErrorIdentifier = [NSString stringWithFormat:@"syncError::%@", account.connectionProperties.identity.jid];
        [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
            for(UNNotificationRequest* request in requests)
                if([request.identifier isEqualToString:syncErrorIdentifier])
                {
                    //remove pending but not yet delivered sync error notifications and reset state to "not displayed yet"
                    //this will delay the delivery of such notifications until 60 seconds after our last sync attempt failed
                    //rather than being delivered 60 seconds after our first sync attempt failed
                    //--> better UX
                    syncErrorsDisplayed[account.connectionProperties.identity.jid] = @NO;
                    [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[syncErrorIdentifier]];
                }
        }];
    }
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
                NSString* syncErrorIdentifier = [NSString stringWithFormat:@"syncError::%@", account.connectionProperties.identity.jid];
                //dispatching this to the receive queue isn't neccessary anymore, see comments in account.idle
                if(account.idle)
                {
                    //but only do so, if we have connectivity, otherwise just ignore it (the old sync error should still be displayed)
                    if([[MLXMPPManager sharedInstance] hasConnectivity])
                    {
                        DDLogInfo(@"Removing syncError notification for %@ (now synced)...", account.connectionProperties.identity.jid);
                        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[syncErrorIdentifier]];
                        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[syncErrorIdentifier]];
                        syncErrorsDisplayed[account.connectionProperties.identity.jid] = @NO;
                        [[HelperTools defaultsDB] setObject:syncErrorsDisplayed forKey:@"syncErrorsDisplayed"];
                    }
                }
                else if(!removeOnly && [self isNotInFocus])
                {
                    if([syncErrorsDisplayed[account.connectionProperties.identity.jid] boolValue])
                    {
                        DDLogWarn(@"NOT posting syncError notification for %@ (already did so since last app foreground)...", account.connectionProperties.identity.jid);
                        continue;
                    }
                    //we always want to post sync errors if we are in the appex (because an incoming push means the server has
                    //*possibly* queued some messages for us)
                    //if we are in the main app we only want to post sync errors if we are in one of these states:
                    //1. we are NOT doing a full reconnect and the smacks queue does not contain some unacked message stanzas having a body
                    //--> (briefly) opening the app while not having an internet connection does not generate sync errors (if no
                    //outgoing message is pending)
                    //2. we are doing a full reconnect --> we always want to post sync erros because we have to rejoin mucs,
                    //set up push etc. and we *really* want to be sure all of these get a chance to complete
                    //NOTE: this conditions are all swapped and ANDed because we want to continue the loop here instead of posting a sync error
                    if(![self isAppExtension] && !account.isDoingFullReconnect && ![account shouldTriggerSyncErrorForImportantUnackedOutgoingStanzas])
                    {
                        DDLogWarn(@"NOT posting syncError notification for %@ (we are not in the appex, no important stanzas are unacked and we are not doing a full reconnect)...", account.connectionProperties.identity.jid);
                        DDLogDebug(@"[self isAppExtension] == %@, account.isDoingFullReconnect == %@, [account shouldTriggerSyncErrorForImportantUnackedOutgoingStanzas] == %@", bool2str([self isAppExtension]), bool2str(account.isDoingFullReconnect), bool2str([account shouldTriggerSyncErrorForImportantUnackedOutgoingStanzas]));
                        continue;
                    }
                    DDLogWarn(@"Posting syncError notification for %@...", account.connectionProperties.identity.jid);
                    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
                    content.title = NSLocalizedString(@"Could not synchronize", @"");
                    content.subtitle = account.connectionProperties.identity.jid;
                    content.body = NSLocalizedString(@"Some messages might wait to be retrieved or sent. Please open the app to retry.", @"");
                    content.sound = [UNNotificationSound defaultSound];
                    content.categoryIdentifier = @"simple";
                    //we don't know if and when apple will start the background process or when the next push will come in
                    //--> we need a sync error notification to make the user aware of possible issues
                    //BUT: we can delay it for some time and hope a background process/push that removes the notification before it
                    //is displayed at all is started in the meantime (we use 60 seconds here)
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
        [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
            if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
                inBackground = YES;
        }];
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

+(void) dispatchAsync:(BOOL) async reentrantOnQueue:(dispatch_queue_t _Nullable) queue withBlock:(monal_void_block_t) block
{
    dispatch_queue_t main_queue = dispatch_get_main_queue();
    if(!queue)
        queue = main_queue;
    
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
    if(queue == main_queue && [NSThread isMainThread])
        block();
    else if(current_queue == queue)
        block();
    else
    {
        if(async)
            dispatch_async(queue, block);
        else
            dispatch_sync(queue, block);
    }
}

+(void) activityLog
{
    BOOL log_activity = NO;
#ifdef DEBUG
    log_activity = YES;
#else
    log_activity = [[HelperTools defaultsDB] boolForKey:@"showLogInSettings"];
#endif
    if(log_activity)
    {
        dispatch_async(dispatch_queue_create_with_target("im.monal.activityLog", DISPATCH_QUEUE_SERIAL, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)), ^{
            unsigned long counter = 1;
            while(counter++)
            {
                DDLogInfo(@"activity: %lu, memory used / available: %.3fMiB / %.3fMiB", counter, [self report_memory], (CGFloat)os_proc_available_memory() / 1048576);
                [NSThread sleepForTimeInterval:1];
            }
        });
    }
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

+(NSData* _Nullable) convertLogmessageToJsonData:(DDLogMessage*) logMessage counter:(uint64_t*) counter andError:(NSError** _Nullable) error
{
    static NSDateFormatter* dateFormatter = nil;
    static NSString* (^qos2name)(NSUInteger) = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss:SSS"];
        [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [dateFormatter setCalendar:[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]];
        
        qos2name = ^(NSUInteger qos) {
            switch ((qos_class_t) qos) {
                case QOS_CLASS_USER_INTERACTIVE: return @"QOS_CLASS_USER_INTERACTIVE";
                case QOS_CLASS_USER_INITIATED:   return @"QOS_CLASS_USER_INITIATED";
                case QOS_CLASS_DEFAULT:          return @"QOS_CLASS_DEFAULT";
                case QOS_CLASS_UTILITY:          return @"QOS_CLASS_UTILITY";
                case QOS_CLASS_BACKGROUND:       return @"QOS_CLASS_BACKGROUND";
                default:                         return [NSString stringWithFormat:@"QOS_UNKNOWN(%lu)", (unsigned long)qos];
            }
        };
    });
    
    //construct json dictionary
    (*counter)++;
    NSDictionary* tag = @{
        @"queueThreadLabel": nilWrapper([self getQueueThreadLabelFor:logMessage]),
        @"processType": [self isAppExtension] ? @"appex" : @"mainapp",
        @"processName": nilWrapper([[[NSBundle mainBundle] executablePath] lastPathComponent]),
        @"counter": @(*counter),
        @"processID": nilWrapper(_processID),
        @"qosName": nilWrapper(qos2name(logMessage.qos)),
        @"loggingQueueSuspended": @(_suspensionHandling_isSuspended),
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        @"tag": nilWrapper(logMessage.tag),
#pragma clang diagnostic pop
    };
    NSDictionary* msgDict = @{
        @"messageFormat": nilWrapper(logMessage.messageFormat),
        @"message": nilWrapper(logMessage.message),
        @"level": @(logMessage.level),
        @"flag": @(logMessage.flag),
        @"context": @(logMessage.context),
        @"file": nilWrapper(logMessage.file),
        @"fileName": nilWrapper(logMessage.fileName),
        @"function": nilWrapper(logMessage.function),
        @"line": @(logMessage.line),
        @"representedObject": nilWrapper(logMessage.representedObject),
        @"tag": nilWrapper(tag),
        @"options": @(logMessage.options),
        @"timestamp": [dateFormatter stringFromDate:logMessage.timestamp],
        @"threadID": nilWrapper(logMessage.threadID),
        @"threadName": nilWrapper(logMessage.threadName),
        @"queueLabel": nilWrapper(logMessage.queueLabel),
        @"qos": @(logMessage.qos),
    };
    
    //encode json into NSData
    NSError* writeError = nil; 
    NSData* rawData = [NSJSONSerialization dataWithJSONObject:msgDict options:NSJSONWritingSortedKeys error:&writeError];
    if(writeError)
    {
        if(error != nil)
            *error = writeError;
        return nil;
    }
    return rawData;
}

+(void) flushLogsWithTimeout:(double) timeout
{
    [_stderrRedirector flushWithTimeout:timeout];
    [_stdoutRedirector flushWithTimeout:timeout];
    [DDLog flushLog];
    [MLUDPLogger flushWithTimeout:timeout];
}

+(BOOL) isAppSuspended
{
    @synchronized(_suspensionHandling_lock) {
        return _suspensionHandling_isSuspended;
    }
}

+(void) signalSuspension
{
    @synchronized(_suspensionHandling_lock) {
        if(!_suspensionHandling_isSuspended)
        {
            DDLogVerbose(@"Suspending logger queue...");
            [HelperTools flushLogsWithTimeout:0.100];
            dispatch_suspend([DDLog loggingQueue]);
            _suspensionHandling_isSuspended = YES;
            
            DDLogVerbose(@"Posting kMonalFrozen notification now...");
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFrozen object:nil];
        }
    }
}

+(void) signalResumption
{
    @synchronized(_suspensionHandling_lock) {
        if(_suspensionHandling_isSuspended)
        {
            DDLogVerbose(@"Resuming logger queue...");
            dispatch_resume([DDLog loggingQueue]);
            _suspensionHandling_isSuspended = NO;
            
            DDLogVerbose(@"Posting kMonalUnfrozen notification now...");
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalUnfrozen object:nil];
        }
    }
}

+(void) configureXcodeLogging
{
    //only start console logger
    [DDLog addLogger:[DDOSLogger sharedInstance]];
}

+(void) configureLogging
{
    NSError* error;
    
    //network logger (start as early as possible)
    MLUDPLogger* udpLogger = [MLUDPLogger new];
    [DDLog addLogger:udpLogger];
    
    //redirect stderr containing NSLog() messages
    _stderrRedirector = [[MLStreamRedirect alloc] initWithStream:stderr];
    NSLog(@"stderr redirection complete...");
    
    //redirect stdout for good measure
    _stdoutRedirector = [[MLStreamRedirect alloc] initWithStream:stdout];
    printf("stdout redirection complete...");
    
    //redirect apple system logs, too
    /*
    OSLogStore* osLogStore = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:&error];
    if(error)
        DDLogError(@"Failed to open os log store: %@", error);
    else
    {
        dispatch_async(, ^{
            [osLogStore entriesEnumeratorAndReturnError:&error];
        });
    }
    */
    
    NSString* containerUrl = [[HelperTools getContainerURLForPathComponents:@[]] path];
    DDLogInfo(@"Logfile dir: %@", containerUrl);
    
    //file logger
    id<DDLogFileManager> logFileManager = [[MLLogFileManager alloc] initWithLogsDirectory:containerUrl defaultFileProtectionLevel:NSFileProtectionCompleteUntilFirstUserAuthentication];
    logFileManager.maximumNumberOfLogFiles = 4;
    logFileManager.logFilesDiskQuota = 512 * 1024 * 1024;
    self.fileLogger = [[DDFileLogger alloc] initWithLogFileManager:logFileManager];
    self.fileLogger.doNotReuseLogFiles = NO;
    self.fileLogger.rollingFrequency = 60 * 60 * 48;    // 48 hour rolling
    self.fileLogger.maximumFileSize = 128 * 1024 * 1024;
    [DDLog addLogger:self.fileLogger];
    
    DDLogDebug(@"Sorted logfiles: %@", [logFileManager sortedLogFileInfos]);
    DDLogDebug(@"Current logfile: %@", self.fileLogger.currentLogFileInfo.filePath);
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.fileLogger.currentLogFileInfo.filePath error:&error];
    if(error)
        DDLogError(@"File attributes error: %@", error);
    else
        DDLogDebug(@"File attributes: %@", attrs);
    
    //log version info as early as possible
    DDLogInfo(@"Starting: %@", [self appBuildVersionInfoFor:MLVersionTypeLog]);
    [DDLog flushLog];
    
    DDLogVerbose(@"QOS level: %@ = %d", @"QOS_CLASS_USER_INTERACTIVE", QOS_CLASS_USER_INTERACTIVE);
    DDLogVerbose(@"QOS level: %@ = %d", @"QOS_CLASS_USER_INITIATED", QOS_CLASS_USER_INITIATED);
    DDLogVerbose(@"QOS level: %@ = %d", @"QOS_CLASS_DEFAULT", QOS_CLASS_DEFAULT);
    DDLogVerbose(@"QOS level: %@ = %d", @"QOS_CLASS_UTILITY", QOS_CLASS_UTILITY);
    DDLogVerbose(@"QOS level: %@ = %d", @"QOS_CLASS_BACKGROUND", QOS_CLASS_BACKGROUND);
    
    //remove old ascii based logfiles
    for(NSString* file in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:containerUrl error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self LIKE %@", @"Monal *.log"]])
    {
        DDLogWarn(@"Removing old ascii logfile: %@/%@", containerUrl, file);
        [[NSFileManager defaultManager] removeItemAtPath:[containerUrl stringByAppendingPathComponent:file] error:nil];
    }
    
    //for debugging when upgrading the app
    NSArray* directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:containerUrl error:nil];
    for(NSString* file in directoryContents)
        DDLogVerbose(@"File %@/%@", containerUrl, file);
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsUrl = [paths objectAtIndex:0];
    documentsUrl = [documentsUrl stringByAppendingPathComponent:@".."];
    documentsUrl = [documentsUrl stringByAppendingPathComponent:@"Library"];
    directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsUrl error:nil];
    for(NSString* file in directoryContents)
        DDLogVerbose(@"App File %@/%@", documentsUrl, file);
    documentsUrl = [paths objectAtIndex:0];
    documentsUrl = [documentsUrl stringByAppendingPathComponent:@".."];
    documentsUrl = [documentsUrl stringByAppendingPathComponent:@"SystemData"];
    directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsUrl error:nil];
    for(NSString* file in directoryContents)
        DDLogVerbose(@"App File %@/%@", documentsUrl, file);
}

+(int) pendingCrashreportCount
{
    KSCrash* handler = [KSCrash sharedInstance];
    return handler.reportCount;
}

+(void) cleanupRawlogCrashcopies
{
    NSError* error;
    KSCrash* handler = [KSCrash sharedInstance];
    NSSet* reportIds = [NSSet setWithArray:[handler reportIDs]];
    NSString* reportpath = [[HelperTools getContainerURLForPathComponents:@[@"CrashReports", @"Reports"]] path];
    NSArray* directoryContentsReports = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:reportpath error:&error];
    if(error != nil)
    {
        DDLogError(@"Failed to get directory contents while cleaning up rawlog crashcopies...");
        return;
    }
    DDLogInfo(@"Current crash report ids: %@", reportIds);
    
    //parts taken from https://github.com/kstenerud/KSCrash/blob/9e72c018a0ba455a89cf5770dea6e1d5258744b6/Source/KSCrash/Recording/KSCrashReportStore.c#L75
    char scanFormat[100];
    snprintf(scanFormat, sizeof(scanFormat), "%s-log-%%" PRIx64 ".rawlog", _crashBundleName);
    for(NSString* filename in [directoryContentsReports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF LIKE %@", [NSString stringWithFormat:@"%s-log-*.rawlog", _crashBundleName]]])
    {
        NSString* file = [NSString stringWithFormat:@"%@/%@", reportpath, filename];
        int64_t reportID = 0;
        sscanf(filename.UTF8String, scanFormat, &reportID);
        DDLogVerbose(@"Checking crash report id: %@", @(reportID));
        if(reportID == 0)
        {
            DDLogError(@"Could not extract crash report id from '%@', ignoring file!", file);
            continue;
        }
        if(![reportIds containsObject:@(reportID)])
        {
            DDLogInfo(@"Deleting orphan rawlog copy at '%@'...", file);
            [[NSFileManager defaultManager] removeItemAtPath:file error:&error];
            if(error != nil)
                DDLogError(@"Error cleaning up orphan rawlog copy at '%@', ignoring file!", file);
        }
    }
}

+(void) installCrashHandler
{
    
    DDLogVerbose(@"KSCrash installing handler with callback: %p", crash_callback);
    KSCrash* handler = [KSCrash sharedInstance];
    handler.basePath = [[HelperTools getContainerURLForPathComponents:@[@"CrashReports"]] path];
    handler.monitoring = KSCrashMonitorTypeProductionSafe;      //KSCrashMonitorTypeAll
    handler.onCrash = crash_callback;
    //this can trigger crashes on macos < 13 (e.g. mac catalyst < 16) (and possibly ios < 16)
#if !TARGET_OS_MACCATALYST
    [handler enableSwapOfCxaThrow];
#endif
    handler.searchQueueNames = NO;      //this is not async safe and can crash :(
    handler.introspectMemory = YES;
    handler.addConsoleLogToReport = YES;
    handler.printPreviousLog = NO;     //debug kscrash itself?
    handler.demangleLanguages = KSCrashDemangleLanguageAll;
    handler.maxReportCount = 4;
    handler.deadlockWatchdogInterval = 0;       // no main thread watchdog
    handler.userInfo = @{
        @"isAppex": bool2str([self isAppExtension]),
        @"processName": [[[NSBundle mainBundle] executablePath] lastPathComponent],
        @"bundleName": nilWrapper([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"]),
        @"appVersion": [self appBuildVersionInfoFor:MLVersionTypeLog],
    };
    //we can not use [KSCrash install] because this uses the bundle names to store our crash reports which are different
    //in appex and mainapp use the lowlevel C api with dummy bundle name "UnifiedReport" instead
    handler.monitoring = kscrash_install(_crashBundleName, handler.basePath.UTF8String);
    if(handler.monitoring == KSCrashMonitorTypeNone)
        DDLogError(@"Failed to install KSCrash monitors, crash reporting is disabled now!");
    else
        DDLogInfo(@"Crash monitoring active now: %d", handler.monitoring);
    
    //KSCrash increments the id by one every new crash --> the next id used by kscrash will be this one
    _nextCrashId = kscrs_getNextCrashReport(NULL) + 1;
    
    [HelperTools updateCurrentLogfilePath:self.fileLogger.currentLogFileInfo.filePath];
    
    //store data globally for later retrieval by our crash_callback() (_origProfilePath and _profilePath)
    NSString* profrawFilePath = [[HelperTools getContainerURLForPathComponents:@[@"default.profraw"]] path];
    strncpy(_origProfilePath, profrawFilePath.UTF8String, sizeof(_profilePath)-1);
    _origProfilePath[sizeof(_origProfilePath)-1] = '\0';
    //use the same id for our logfile copy as for the main report (allows to delete all logfile copies for which no crash report exists)
    snprintf(_profilePath, sizeof(_profilePath)-1, "%s/Reports/%s-profile-%016llx.profraw", handler.basePath.UTF8String, _crashBundleName, _nextCrashId);
    _profilePath[sizeof(_profilePath)-1] = '\0';
    DDLogVerbose(@"KSCrash: _origProfilePath=%s, _profilePath=%s", _origProfilePath, _profilePath);
    
    //clean up orphan rawlog copies
    [self cleanupRawlogCrashcopies];
    
    NSArray* directoryContentsData = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[HelperTools getContainerURLForPathComponents:@[@"CrashReports", @"Data"]] path] error:nil];
    DDLogDebug(@"KSCrash data files: %@", directoryContentsData);
    NSArray* directoryContentsReports = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[HelperTools getContainerURLForPathComponents:@[@"CrashReports", @"Reports"]] path] error:nil];
    DDLogDebug(@"KSCrash report files: %@", directoryContentsReports);
    
    //[[KSCrash sharedInstance] reportUserException:@"test" reason:@"dummy test" language:@"dylang" lineOfCode:nil stackTrace:nil logAllThreads:NO terminateProgram:YES];
}

+(void) updateCurrentLogfilePath:(NSString*) logfilePath
{
    KSCrash* handler = [KSCrash sharedInstance];
    
    //store data globally for later retrieval by our crash_callback() (_origLogfilePath and _logfilePath)
    strncpy(_origLogfilePath, logfilePath.UTF8String, sizeof(_logfilePath)-1);
    _origLogfilePath[sizeof(_origLogfilePath)-1] = '\0';
    //use the same id for our logfile copy as for the main report (allows to delete all logfile copies for which no crash report exists)
    snprintf(_logfilePath, sizeof(_logfilePath)-1, "%s/Reports/%s-log-%016llx.rawlog", handler.basePath.UTF8String, _crashBundleName, _nextCrashId);
    _logfilePath[sizeof(_logfilePath)-1] = '\0';
    DDLogVerbose(@"KSCrash: _origLogfilePath=%s, _logfilePath=%s", _origLogfilePath, _logfilePath);
}

+(BOOL) isAppExtension
{
    //dispatch once seems to corrupt this check (nearly always return mainapp even if in appex) --> don't use dispatch once
    static BOOL result = NO;
    static BOOL calculated = NO;
    @synchronized(_isAppExtensionLock) {
        if(calculated)
            return result;
        result = [[[NSBundle mainBundle] executablePath] containsString:@".appex/"];
        calculated = YES;
        return result;
    }
}

+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features andForms:(NSArray*) forms
{
    // see https://xmpp.org/extensions/xep-0115.html#ver
    NSMutableString* unhashed = [NSMutableString new];
    
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
        NSMutableArray* featuresArray = [@[
            @"http://jabber.org/protocol/caps",
            @"http://jabber.org/protocol/disco#info",
            @"jabber:x:conference",
            @"jabber:x:oob",
            @"urn:xmpp:ping",
            @"urn:xmpp:eme:0",
            @"urn:xmpp:message-retract:1",
            @"urn:xmpp:message-correct:0",
            
            
        ] mutableCopy];
        if([[HelperTools defaultsDB] boolForKey: @"SendLastUserInteraction"])
            [featuresArray addObject:@"urn:xmpp:idle:1"];
        if([[HelperTools defaultsDB] boolForKey: @"SendLastChatState"])
            [featuresArray addObject:@"http://jabber.org/protocol/chatstates"];
        if([[HelperTools defaultsDB] boolForKey: @"SendReceivedMarkers"])
            [featuresArray addObject:@"urn:xmpp:receipts"];
        if([[HelperTools defaultsDB] boolForKey: @"SendDisplayedMarkers"])
            [featuresArray addObject:@"urn:xmpp:chat-markers:0"];
        if([[HelperTools defaultsDB] boolForKey: @"allowVersionIQ"])
            [featuresArray addObject:@"jabber:iq:version"];
        //voip stuff
        if([HelperTools shouldProvideVoip])
        {
            [featuresArray addObject:@"urn:xmpp:jingle-message:0"];
            [featuresArray addObject:@"urn:xmpp:jingle:1"];
            [featuresArray addObject:@"urn:xmpp:jingle:apps:rtp:1"];
            [featuresArray addObject:@"urn:xmpp:jingle:apps:rtp:audio"];
            [featuresArray addObject:@"urn:xmpp:jingle:apps:rtp:video"];
            [featuresArray addObject:@"urn:xmpp:jingle:transports:ice-udp:1"];
            [featuresArray addObject:@"urn:ietf:rfc:5888"];
            [featuresArray addObject:@"urn:xmpp:jingle:apps:dtls:0"];
            [featuresArray addObject:@"urn:ietf:rfc:5576"];
            [featuresArray addObject:@"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0"];
            [featuresArray addObject:@"urn:xmpp:jingle:apps:rtp:rtcp-fb:0"];
        }
        
        featuresSet = [[NSSet alloc] initWithArray:featuresArray];
    });
    return featuresSet;
}

+(NSString*) generateStringOfFeatureSet:(NSSet*) features
{
    // this has to be sorted for the features hash to be correct, see https://xmpp.org/extensions/xep-0115.html#ver
    NSArray* featuresArray = [[features allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString* toreturn = [NSMutableString new];
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
    NSMutableString* toreturn = [NSMutableString new];
    for(XMPPDataForm* form in [forms sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"formType" ascending:YES selector:@selector(compare:)]]])
    {
        [toreturn appendString:[self _replaceLowerThanInString:form.formType]];
        [toreturn appendString:@"<"];
        for(NSString* field in [[form allKeys] sortedArrayUsingSelector:@selector(compare:)])
        {
            if([@"FORM_TYPE" isEqualToString:field])
                continue;
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
 */
+(NSString*) formatLastInteraction:(NSDate*) lastInteraction
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

+(NSString*) stringFromTimeInterval:(NSUInteger) interval
{
    NSUInteger hours = interval / 3600;
    NSUInteger minutes = (interval % 3600) / 60;
    NSUInteger seconds = interval % 60;

    return [NSString stringWithFormat:@"%luh %lumin and %lusec", hours, minutes, seconds];
}

+(NSDate*) parseDateTimeString:(NSString*) datetime
{
    static NSDateFormatter* rfc3339DateFormatter;
    static NSDateFormatter* rfc3339DateFormatter2;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        rfc3339DateFormatter = [NSDateFormatter new];
        rfc3339DateFormatter2 = [NSDateFormatter new];
        
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
        rfc3339DateFormatter = [NSDateFormatter new];
        
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    });
    
    return [rfc3339DateFormatter stringFromDate:datetime];
}

+(NSString*) sanitizeFilePath:(const char* const) file
{
    NSString* fileStr = [NSString stringWithFormat:@"%s", file];
    NSArray* filePathComponents = [fileStr pathComponents];
    if([filePathComponents count]>1)
        fileStr = [NSString stringWithFormat:@"%@/%@", filePathComponents[[filePathComponents count]-2], filePathComponents[[filePathComponents count]-1]];
    return fileStr;
}

//don't use this directly, but via createDelayableTimer() makros
+(MLDelayableTimer*) startDelayableQueuedTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func onQueue:(dispatch_queue_t _Nullable) queue
{
    if(queue == nil)
        queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    MLDelayableTimer* timer = [[MLDelayableTimer alloc] initWithHandler:^(MLDelayableTimer* timer){
        if(handler)
            dispatch_async(queue, ^{
                DDLogDebug(@"calling handler for timer: %@", timer);
                handler();
            });
    } andCancelHandler:^(MLDelayableTimer* timer){
        if(cancelHandler)
            dispatch_async(queue, ^{
                DDLogDebug(@"calling cancel block for timer: %@", timer);
                cancelHandler();
            });
    } timeout:timeout tolerance:0.1 andDescription:[NSString stringWithFormat:@"created at %@:%d in %s", [self sanitizeFilePath:file], line, func]];
    
    if(timeout < 0.001)
    {
        //DDLogVerbose(@"Timer timeout is smaller than 0.001, dispatching handler directly: %@", timer);
        [timer invalidate];
        if(handler)
            dispatch_async(queue, ^{
                handler();
            });
        return timer;       //this timer is not added to a runloop and invalid because the handler already got called
    }
    
    [timer start];
    return timer;
}

//don't use this directly, but via createTimer() makros
+(monal_void_block_t) startQueuedTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func onQueue:(dispatch_queue_t _Nullable) queue
{
    MLDelayableTimer* timer = [self startDelayableQueuedTimer:timeout withHandler:handler andCancelHandler:cancelHandler andFile:file andLine:line andFunc:func onQueue:queue];
    return ^{
        [timer cancel];
    };
}

+(AnyPromise*) waitAtLeastSeconds:(NSTimeInterval) seconds forPromise:(AnyPromise*) promise
{
    return PMKWhen(@[promise, PMKAfter(seconds)]).then(^{
        return promise;
    });
}

+(NSString*) generateRandomPassword
{
    u_int32_t i=arc4random();
    return [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]];
}

+(NSString*) encodeRandomResource
{
    u_int32_t i=arc4random();
#if TARGET_OS_MACCATALYST
    NSString* resource = [NSString stringWithFormat:@"Monal-macOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#else
#if IS_QUICKSY
    NSString* resource = [NSString stringWithFormat:@"Quicksy-iOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#else
    NSString* resource = [NSString stringWithFormat:@"Monal-iOS.%@", [self hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]]];
#endif
#endif
    return resource;
}

+(NSString*) appBuildVersionInfoFor:(MLVersionType) type
{
    @synchronized(_versionInfoCache) {
        if(_versionInfoCache[@(type)] != nil)
            return _versionInfoCache[@(type)];
        
#ifdef IS_ALPHA
        NSString* rawVersionString = [NSString stringWithFormat:@"Alpha %s (%s %s UTC)", ALPHA_COMMIT_HASH, __DATE__, __TIME__];
#else// IS_ALPHA
        NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
        NSString* rawVersionString = [NSString stringWithFormat:@"%@ %@ (%@)",
#ifdef DEBUG
            @"Beta",
#else// DEBUG
            @"Stable",
#endif// DEBUG
            [infoDict objectForKey:@"CFBundleShortVersionString"],
            [infoDict objectForKey:@"CFBundleVersion"]
        ];
#endif// IS_ALPHA
        
        if(type == MLVersionTypeIQ)
            return _versionInfoCache[@(type)] = rawVersionString;
        else if(type == MLVersionTypeLog)
            return _versionInfoCache[@(type)] = [NSString stringWithFormat:@"Version %@, %@ on iOS/macOS %@", rawVersionString, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"], [UIDevice currentDevice].systemVersion];
        unreachable(@"unknown version type!");
    }
}

+(NSNumber*) currentTimestampInSeconds
{
    return [HelperTools dateToNSNumberSeconds:[NSDate date]];
}

+(NSNumber*) dateToNSNumberSeconds:(NSDate*) date
{
    return [NSNumber numberWithUnsignedLong:(unsigned long)date.timeIntervalSince1970];
}

+(NSArray<MLXMLNode*>* _Nullable) sdp2xml:(NSString*) sdp withInitiator:(BOOL) initiator
{
    DDLogVerbose(@"Parsing SDP string using rust(withInitiator=%@): %@", bool2str(initiator), sdp);
    __block NSMutableArray<MLXMLNode*>* retval = [NSMutableArray new];
    MLBasePaser* delegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedElement) {
        DDLogVerbose(@"Parsed jingle sdp element: %@", parsedElement);
        [retval addObject:parsedElement];
    }];
    NSString* xmlString = [JingleSDPBridge getJingleStringForSDPString:sdp withInitiator:initiator];
    if(xmlString == nil)
        return nil;
    DDLogVerbose(@"Parsing XML string produced by rust sdp parser(withInitiator=%@): %@", bool2str(initiator), xmlString);
    NSXMLParser* xmlParser = [[NSXMLParser alloc] initWithData:[xmlString dataUsingEncoding:NSUTF8StringEncoding]];
    [xmlParser setShouldProcessNamespaces:YES];
    [xmlParser setShouldReportNamespacePrefixes:YES];       //for debugging only
    [xmlParser setShouldResolveExternalEntities:NO];
    [xmlParser setDelegate:delegate];
    [xmlParser parse];     //blocking operation
    return retval;
}

+(NSString* _Nullable) xml2sdp:(MLXMLNode*) xml withInitiator:(BOOL) initiator
{
    NSString* xmlstr = [[[MLXMLNode alloc] initWithElement:@"root" withAttributes:@{} andChildren:xml.children andData:nil] XMLString];
    NSString* retval = [JingleSDPBridge getSDPStringForJingleString:xmlstr withInitiator:initiator];
    DDLogVerbose(@"Got sdp string from rust(withInitiator=%@): %@", bool2str(initiator), retval);
    return retval;
}

+(MLXMLNode* _Nullable) candidate2xml:(NSString*) candidate withMid:(NSString*) mid pwd:(NSString* _Nullable) pwd ufrag:(NSString* _Nullable) ufrag andInitiator:(BOOL) initiator
{
    //use some dummy sdp string to make our rust sdp parser happy
    //always use "audio" for our dummy media
    NSMutableString* sdp = [NSMutableString stringWithFormat:@"v=0\r\n\
o=- 2005859539484728435 2 IN IP4 127.0.0.1\r\n\
s=-\r\n\
t=0 0\r\n\
m=audio 9 UDP/TLS/RTP/SAVPF 0\r\n\
c=IN IP4 0.0.0.0\r\n\
a=mid:%@\r\n\
a=%@\r\n", mid, candidate];
    if(pwd != nil)
        [sdp appendString:[NSString stringWithFormat:@"a=ice-pwd:%@\r\n", pwd]];
    if(ufrag != nil)
        [sdp appendString:[NSString stringWithFormat:@"a=ice-ufrag:%@\r\n", ufrag]];
    DDLogVerbose(@"Dummy sdp candidate string for rust parser: %@", sdp);
    
    //this result array should only contain one single content node or be nil on parser errors
    NSArray* xml = [self sdp2xml:sdp withInitiator:initiator];
    if(xml == nil)
        return nil;
    MLAssert([xml count] == 1, @"Only one single content node expected!", (@{@"xml": xml}));
    MLXMLNode* contentNode = xml[0];
    MLAssert([contentNode check:@"/{urn:xmpp:jingle:1}content"], @"Content node not present!", (@{@"xml": xml}));
    
    //remove unwanted description node resulting from our dummy sdp media line above (which is needed for the sdp parser)
    for(MLXMLNode* node in [contentNode find:@"{urn:xmpp:jingle:apps:rtp:1}description"])
        [contentNode removeChildNode:node];
    return contentNode;
}

+(NSString* _Nullable) xml2candidate:(MLXMLNode*) xml withInitiator:(BOOL) initiator
{
    //add dummy description childs to each content element, but don't change the original xml node
    MLXMLNode* node = [xml copy];
    for(MLXMLNode* contentNode in [node find:@"{urn:xmpp:jingle:1}content"])
        [contentNode addChildNode:[[MLXMLNode alloc] initWithElement:@"description" andNamespace:@"urn:xmpp:jingle:apps:rtp:1" withAttributes:@{@"media": @"audio"} andChildren:@[] andData:nil]];
    NSString* xmlString = [self xml2sdp:node withInitiator:initiator];
    //the candidate attribute line should always be the last one (given our current rust parser code), but we try to be more robust here
    NSArray* lines = [xmlString componentsSeparatedByString:@"\r\n"];
    NSString* prefix = @"a=candidate";
    for(NSString* line in lines)
        if(line.length >= prefix.length && [prefix isEqualToString:[line substringWithRange:NSMakeRange(0, prefix.length)]])
            return [line substringWithRange:NSMakeRange(2, line.length - 2)];
    return nil;
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

+(NSData*) sha1HmacForKey:(NSData*) key andData:(NSData*) data
{
    if(!key || !data)
        return nil;
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CCHmac(kCCHmacAlgSHA1, [key bytes], (UInt32)[key length], [data bytes], (UInt32)[data length], digest);
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

+(NSString*) stringSha1HmacForKey:(NSString*) key andData:(NSString*) data
{
    if(!key || !data)
        return nil;
	return [self hexadecimalString:[self sha1HmacForKey:[key dataUsingEncoding:NSUTF8StringEncoding] andData:[data dataUsingEncoding:NSUTF8StringEncoding]]];
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

+(NSData*) sha512:(NSData*) data
{
    if(!data)
        return nil;
    NSData* hashed;
    unsigned char digest[CC_SHA512_DIGEST_LENGTH];
    if(CC_SHA512([data bytes], (UInt32)[data length], digest))
        hashed = [NSData dataWithBytes:digest length:CC_SHA512_DIGEST_LENGTH];
    return hashed;
}

+(NSString*) stringSha512:(NSString*) data
{
    return [self hexadecimalString:[self sha512:[data dataUsingEncoding:NSUTF8StringEncoding]]];
}

+(NSData*) sha512HmacForKey:(NSData*) key andData:(NSData*) data
{
    if(!key || !data)
        return nil;
	unsigned char digest[CC_SHA512_DIGEST_LENGTH];
	CCHmac(kCCHmacAlgSHA512, [key bytes], (UInt32)[key length], [data bytes], (UInt32)[data length], digest);
    return [NSData dataWithBytes:digest length:CC_SHA512_DIGEST_LENGTH];
}

+(NSString*) stringSha512HmacForKey:(NSString*) key andData:(NSString*) data
{
    if(!key || !data)
        return nil;
	return [self hexadecimalString:[self sha512HmacForKey:[key dataUsingEncoding:NSUTF8StringEncoding] andData:[data dataUsingEncoding:NSUTF8StringEncoding]]];
}

+(NSUUID*) dataToUUID:(NSData*) data
{
    NSData* hash = [self sha256:data];
    uint8_t* bytes = (uint8_t*)hash.bytes;
    uint16_t* version = (uint16_t*)(bytes + 6);
    *version = (*version & 0x0fff) | 0x4000;
    return [[NSUUID alloc] initWithUUIDBytes:bytes];
}

+(NSUUID*) stringToUUID:(NSString*) data
{
    return [self dataToUUID:[data dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark base64, hex and other data formats

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

//very fast, taken from https://stackoverflow.com/a/33501154
+(NSString*) hexadecimalString:(NSData*) data
{
    static char _NSData_BytesConversionString_[512] = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff";
    UInt16*  mapping = (UInt16*)_NSData_BytesConversionString_;
    register NSUInteger len = data.length;
    char*    hexChars = (char*)malloc( sizeof(char) * (len*2) );

    // --- Coeur's contribution - a safe way to check the allocation
    if (hexChars == NULL) {
    // we directly raise an exception instead of using NSAssert to make sure assertion is not disabled as this is irrecoverable
        [NSException raise:@"NSInternalInconsistencyException" format:@"failed malloc" arguments:nil];
        return nil;
    }
    // ---

    register UInt16* dst = ((UInt16*)hexChars) + len-1;
    register unsigned char* src = (unsigned char*)data.bytes + len-1;

    while (len--) *dst-- = mapping[*src--];

    NSString* retVal = [[NSString alloc] initWithBytesNoCopy:hexChars length:data.length*2 encoding:NSASCIIStringEncoding freeWhenDone:YES];
    return retVal;
}

+(NSData*) dataWithHexString:(NSString*) hex
{
    char buf[3];
    buf[2] = '\0';
    
    if([hex length] % 2 != 00) {
        DDLogError(@"Hex strings should have an even number of digits");
        return [NSData new];
    }
    unsigned char* bytes = malloc([hex length] / 2);
    if(bytes == NULL)
    {
        [NSException raise:@"NSInternalInconsistencyException" format:@"failed malloc" arguments:nil];
        return nil;
    }
    unsigned char* bp = bytes;
    for (unsigned int i = 0; i < [hex length]; i += 2) {
        buf[0] = (unsigned char) [hex characterAtIndex:i];
        buf[1] = (unsigned char) [hex characterAtIndex:i+1];
        char* b2 = NULL;
        *bp++ = (unsigned char) strtol(buf, &b2, 16);
        if(b2 != buf + 2) {
            DDLogError(@"String should be all hex digits");
            free(bytes);
            return [NSData new];
        }
    }
    return [NSData dataWithBytesNoCopy:bytes length:[hex length]/2 freeWhenDone:YES];
}

//see https://stackoverflow.com/a/29911397/3528174
+(NSData*) XORData:(NSData*) data1 withData:(NSData*) data2
{
    const char* data1Bytes = [data1 bytes];
    const char* data2Bytes = [data2 bytes];
    // Mutable data that individual xor'd bytes will be added to
    NSMutableData* xorData = [NSMutableData new];
    for(NSUInteger i = 0; i < data1.length; i++)
    {
        const char xorByte = data1Bytes[i] ^ data2Bytes[i];
        [xorData appendBytes:&xorByte length:1];
    }
    return xorData;
}

#pragma mark omemo stuff

+(NSString*) signalHexKeyWithData:(NSData*) data
{
    NSString* hex = [self hexadecimalString:data];
    
    //remove 05 cipher info
    hex = [hex substringWithRange:NSMakeRange(2, hex.length - 2)];

    return hex;
}

+(NSData*) signalIdentityWithHexKey:(NSString*) hexKey
{
    //add 05 cipher info
    NSString* hexKeyWithCipherInfo = [NSString stringWithFormat:@"05%@", hexKey];
    NSData* identity = [self dataWithHexString:hexKeyWithCipherInfo];

    return identity;
}

+(NSString*) signalHexKeyWithSpacesWithData:(NSData*) data
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

#pragma mark ui stuff

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

//taken from: https://stackoverflow.com/a/30932216/3528174
+(NSArray*) splitString:(NSString*) string withSeparator:(NSString*) separator andMaxSize:(NSUInteger)size
{
    NSMutableArray* result = [[NSMutableArray alloc]initWithCapacity:size];
    NSArray* components = [string componentsSeparatedByString:separator];

    if(components.count < size)
        return components;

    NSUInteger i = 0;
    while(i < size-1)
    {
        [result addObject:components[i]];
        i++;
    }

    NSMutableString* lastItem = [[NSMutableString alloc] init];
    while(i < components.count)
    {
        [lastItem appendString:components[i]];
        [lastItem appendString:separator];
        i++;
    }
    
    //remove the last separator
    [result addObject:[lastItem substringToIndex:lastItem.length - 1]];

    return result;
}

//see https://nachtimwald.com/2017/04/02/constant-time-string-comparison-in-c/
+(BOOL) constantTimeCompareAttackerString:(NSString* _Nonnull) str1 withKnownString:(NSString* _Nonnull) str2
{
    if(str1 == nil || str2 == nil)
        return NO;
    
    const char* s1 = str1.UTF8String;
    const char* s2 = str2.UTF8String;
    volatile int m = 0;
    volatile size_t i = 0;
    volatile size_t j = 0;
    volatile size_t k = 0;    
    
    while(1)
    {
        //this will only turn on bits in m, but never turn them off
        m |= s1[i] ^ s2[j];
        
        //
        if(s1[i] == '\0')
            break;
        i++;
        
        //always balance increments even if s2 is shorter than s1
        if(s2[j] != '\0')
            j++;
        if(s2[j] == '\0')
            k++;
    }
    
    return m == 0;      //check if we never turned on any bit in m
}

+(BOOL) isIP:(NSString*) host
{
    if([[IPV4 matchesInString:host options:0 range:NSMakeRange(0, [host length])] count] > 0)
        return YES;
    if([[IPV6_HEX4DECCOMPRESSED matchesInString:host options:0 range:NSMakeRange(0, [host length])] count] > 0)
        return YES;
    if([[IPV6_6HEX4DEC matchesInString:host options:0 range:NSMakeRange(0, [host length])] count] > 0)
        return YES;
    if([[IPV6_HEXCOMPRESSED matchesInString:host options:0 range:NSMakeRange(0, [host length])] count] > 0)
        return YES;
    if([[IPV6 matchesInString:host options:0 range:NSMakeRange(0, [host length])] count] > 0)
        return YES;
    return NO;
}

+(NSURLSession*) createEphemeralURLSession
{
    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    if([[HelperTools defaultsDB] boolForKey: @"useDnssecForAllConnections"])
        sessionConfig.requiresDNSSECValidation = YES;
    return [NSURLSession sessionWithConfiguration:sessionConfig];
}

@end
