//
//  HelperTools.h
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "MLDelayableTimer.h"

#include "metamacros.h"

#define createDelayableTimer(timeout, handler, ...)                                     createDelayableQueuedTimer(timeout, nil, handler, __VA_ARGS__)
#define createDelayableQueuedTimer(timeout, queue, handler, ...)                        metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([HelperTools startDelayableQueuedTimer:timeout withHandler:handler andCancelHandler:nil andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__ onQueue:queue])(_createDelayableQueuedTimer(timeout, queue, handler, __VA_ARGS__))
#define _createDelayableQueuedTimer(timeout, queue, handler, cancelHandler, ...)        [HelperTools startDelayableQueuedTimer:timeout withHandler:handler andCancelHandler:cancelHandler andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__ onQueue:queue]

#define createTimer(timeout, handler, ...)                                  createQueuedTimer(timeout, nil, handler, __VA_ARGS__)
#define createQueuedTimer(timeout, queue, handler, ...)                     metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([HelperTools startQueuedTimer:timeout withHandler:handler andCancelHandler:nil andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__ onQueue:queue])(_createQueuedTimer(timeout, queue, handler, __VA_ARGS__))
#define _createQueuedTimer(timeout, queue, handler, cancelHandler, ...)     [HelperTools startQueuedTimer:timeout withHandler:handler andCancelHandler:cancelHandler andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__ onQueue:queue]

#define MLAssert(check, text, ...)                                          do { if(!(check)) { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([HelperTools MLAssertWithText:text andUserData:nil andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__];)([HelperTools MLAssertWithText:text andUserData:metamacro_head(__VA_ARGS__) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__];) while(YES); } } while(0)
#define unreachable(...)                                                    do { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))(MLAssert(NO, @"unreachable", __VA_ARGS__);)(MLAssert(NO, __VA_ARGS__);); } while(0)

#define showErrorOnAlpha(account, description, ...)                         do { [HelperTools showErrorOnAlpha:[NSString stringWithFormat:description, ##__VA_ARGS__] withNode:nil andAccount:account andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; } while(0)
#define showXMLErrorOnAlpha(account, node, description, ...)                do { [HelperTools showErrorOnAlpha:[NSString stringWithFormat:description, ##__VA_ARGS__] withNode:node andAccount:account andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; } while(0)

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class MLXMLNode;
@class xmpp;
@class XMPPStanza;
@class UNNotificationRequest;
@class DDLogMessage;
@class DDFileLogger;
@class UIView;
@class UITapGestureRecognizer;

typedef NS_ENUM(NSUInteger, MLVersionType) {
    MLVersionTypeIQ,
    MLVersionTypeLog,
};

typedef NS_ENUM(NSUInteger, MLDefinedIdentifier) {
    MLDefinedIdentifier_kAppGroup,
    MLDefinedIdentifier_kMonalOpenURL,
    MLDefinedIdentifier_kBackgroundProcessingTask,
    MLDefinedIdentifier_kBackgroundRefreshingTask,
    MLDefinedIdentifier_kMonalKeychainName,
    MLDefinedIdentifier_SHORT_PING,
    MLDefinedIdentifier_LONG_PING,
    MLDefinedIdentifier_MUC_PING,
    MLDefinedIdentifier_BGFETCH_DEFAULT_INTERVAL,
};

typedef NS_ENUM(NSUInteger, MLRunLoopIdentifier) {
    MLRunLoopIdentifierNetwork,
    MLRunLoopIdentifierTimer,
};

void logException(NSException* exception);
void swizzle(Class c, SEL orig, SEL new);

//weak container holding an object as weak pointer (needed to not create retain circles in NSCache
@interface WeakContainer : NSObject
@property (atomic, weak) id obj;
-(id) initWithObj:(id) obj;
@end

@interface HelperTools : NSObject

@property (class, nonatomic, strong, nullable) DDFileLogger* fileLogger;

+(NSData* _Nullable) convertLogmessageToJsonData:(DDLogMessage*) logMessage counter:(uint64_t*) counter andError:(NSError** _Nullable) error;
+(void) initSystem;
+(void) installExceptionHandler;
+(int) pendingCrashreportCount;
+(void) flushLogsWithTimeout:(double) timeout;
+(void) __attribute__((noreturn)) MLAssertWithText:(NSString*) text andUserData:(id _Nullable) additionalData andFile:(const char* const) file andLine:(int) line andFunc:(const char* const) func;
+(void) __attribute__((noreturn)) handleRustPanicWithText:(NSString*) text andBacktrace:(NSString*) backtrace;
+(void) __attribute__((noreturn)) throwExceptionWithName:(NSString*) name reason:(NSString*) reason userInfo:(NSDictionary* _Nullable) userInfo;
+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere andDisableAccount:(BOOL) disableAccount;
+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere;
+(NSString*) extractXMPPError:(XMPPStanza*) stanza withDescription:(NSString* _Nullable) description;
+(void) showErrorOnAlpha:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp* _Nullable) account andFile:(char*) file andLine:(int) line andFunc:(char*) func;

+(NSDictionary<NSString*, NSString*>*) getInvalidPushServers;
+(NSString*) getSelectedPushServerBasedOnLocale;
+(NSDictionary<NSString*, NSString*>*) getAvailablePushServers;

+(void) configureDefaultAudioSession;

+(NSArray<NSString*>*) getFailoverStunServers;
+(NSURL*) getFailoverTurnApiServer;
+(NSArray<MLXMLNode*>* _Nullable) sdp2xml:(NSString*) sdp withInitiator:(BOOL) initiator;
+(NSString* _Nullable) xml2sdp:(MLXMLNode*) xml withInitiator:(BOOL) initiator;
+(MLXMLNode* _Nullable) candidate2xml:(NSString*) candidate withMid:(NSString*) mid pwd:(NSString* _Nullable) pwd ufrag:(NSString* _Nullable) ufrag andInitiator:(BOOL) initiator;
+(NSString* _Nullable) xml2candidate:(MLXMLNode*) xml withInitiator:(BOOL) initiator;

+(UIImage* _Nullable) renderUIImageFromSVGURL:(NSURL* _Nullable) url    API_AVAILABLE(ios(16.0), macosx(13.0));  //means: API_AVAILABLE(ios(16.0), maccatalyst(16.0))
+(UIImage* _Nullable) renderUIImageFromSVGData:(NSData* _Nullable) data    API_AVAILABLE(ios(16.0), macosx(13.0));  //means: API_AVAILABLE(ios(16.0), maccatalyst(16.0))
+(void) busyWaitForOperationQueue:(NSOperationQueue*) queue;
+(id) getObjcDefinedValue:(MLDefinedIdentifier) identifier;
+(NSRunLoop*) getExtraRunloopWithIdentifier:(MLRunLoopIdentifier) identifier;
+(NSError* _Nullable) hardLinkOrCopyFile:(NSString*) from to:(NSString*) to;
+(NSString*) getQueueThreadLabelFor:(DDLogMessage*) logMessage;
+(BOOL) shouldProvideVoip;
+(BOOL) isSandboxAPNS;
+(int) compareIOcted:(NSData*) data1 with:(NSData*) data2;
+(NSURL*) getContainerURLForPathComponents:(NSArray*) components;
+(NSURL*) getSharedDocumentsURLForPathComponents:(NSArray*) components;
+(NSData*) serializeObject:(id) obj;
+(id) unserializeData:(NSData*) data;
+(NSError* _Nullable) postUserNotificationRequest:(UNNotificationRequest*) request;
+(void) addUploadItemPreviewForItem:(NSURL* _Nullable) url provider:(NSItemProvider* _Nullable) provider andPayload:(NSMutableDictionary*) payload withCompletionHandler:(void(^)(NSMutableDictionary* _Nullable)) completion;
+(void) handleUploadItemProvider:(NSItemProvider*) provider withCompletionHandler:(void (^)(NSMutableDictionary* _Nullable)) completion;
+(UIImage* _Nullable) rotateImage:(UIImage* _Nullable) image byRadians:(CGFloat) rotation;
+(UIImage* _Nullable) mirrorImageOnXAxis:(UIImage* _Nullable) image;
+(UIImage* _Nullable) mirrorImageOnYAxis:(UIImage* _Nullable) image;
+(UIImage*) imageWithNotificationBadgeForImage:(UIImage*) image;
+(UIView*) buttonWithNotificationBadgeForImage:(UIImage*) image hasNotification:(bool) hasNotification withTapHandler: (UITapGestureRecognizer*) handler;
+(NSData*) resizeAvatarImage:(UIImage* _Nullable) image withCircularMask:(BOOL) circularMask toMaxBase64Size:(unsigned long) length;
+(double) report_memory;
+(UIColor*) generateColorFromJid:(NSString*) jid;
+(NSString*) bytesToHuman:(int64_t) bytes;
+(NSString*) stringFromToken:(NSData*) tokenIn;
+(NSString* _Nullable) exportIPCDatabase;
+(void) configureFileProtection:(NSString*) protectionLevel forFile:(NSString*) file;
+(void) configureFileProtectionFor:(NSString*) file;
+(BOOL) isContactBlacklistedForEncryption:(MLContact*) contact;
+(void) removeAllShareInteractionsForAccountNo:(NSNumber*) accountNo;
+(NSDictionary<NSString*, NSString*>*) splitJid:(NSString*) jid;

+(void) scheduleBackgroundTask:(BOOL) force;
+(void) clearSyncErrorsOnAppForeground;
+(void) removePendingSyncErrorNotifications;
+(void) updateSyncErrorsWithDeleteOnly:(BOOL) removeOnly andWaitForCompletion:(BOOL) waitForCompletion;

+(BOOL) isInBackground;
+(BOOL) isNotInFocus;

+(void) dispatchAsync:(BOOL) async reentrantOnQueue:(dispatch_queue_t _Nullable) queue withBlock:(monal_void_block_t) block;
+(NSUserDefaults*) defaultsDB;
+(BOOL) isAppExtension;
+(NSString*) generateStringOfFeatureSet:(NSSet*) features;
+(NSSet*) getOwnFeatureSet;
+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features andForms:(NSArray*) forms;
+(NSString* _Nullable) formatLastInteraction:(NSDate*) lastInteraction;
+(NSString*) stringFromTimeInterval:(NSUInteger) interval;
+(NSDate*) parseDateTimeString:(NSString*) datetime;
+(NSString*) generateDateTimeString:(NSDate*) datetime;
+(NSString*) generateRandomPassword;
+(NSString*) encodeRandomResource;

+(NSData* _Nullable) sha1:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha1:(NSString* _Nullable) data;
+(NSData* _Nullable) sha1HmacForKey:(NSData* _Nullable) key andData:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha1HmacForKey:(NSString* _Nullable) key andData:(NSString* _Nullable) data;
+(NSData* _Nullable) sha256:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha256:(NSString* _Nullable) data;
+(NSData* _Nullable) sha256HmacForKey:(NSData* _Nullable) key andData:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha256HmacForKey:(NSString* _Nullable) key andData:(NSString* _Nullable) data;
+(NSData* _Nullable) sha512:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha512:(NSString* _Nullable) data;
+(NSData* _Nullable) sha512HmacForKey:(NSData* _Nullable) key andData:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha512HmacForKey:(NSString* _Nullable) key andData:(NSString* _Nullable) data;

+(NSUUID*) dataToUUID:(NSData*) data;
+(NSUUID*) stringToUUID:(NSString*) data;

+(NSString*) encodeBase64WithString:(NSString*) strData;
+(NSString*) encodeBase64WithData:(NSData*) objData;
+(NSData*) dataWithBase64EncodedString:(NSString*) string;
+(NSString*) hexadecimalString:(NSData*) data;
+(NSData*) dataWithHexString:(NSString*) hex;
+(NSData*) XORData:(NSData*) data1 withData:(NSData*) data2;

+(NSString*) signalHexKeyWithData:(NSData*) data;
+(NSData*) signalIdentityWithHexKey:(NSString*) hexKey;
+(NSString*) signalHexKeyWithSpacesWithData:(NSData*) data;

+(UIView*) MLCustomViewHeaderWithTitle:(NSString*) title;
+(CIImage*) createQRCodeFromString:(NSString*) input;
+(AnyPromise*) waitAtLeastSeconds:(NSTimeInterval) seconds forPromise:(AnyPromise*) promise;
+(NSString*) sanitizeFilePath:(const char* const) file;

//don't use these four directly, but via createTimer() makro
+(MLDelayableTimer*) startDelayableQueuedTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func onQueue:(dispatch_queue_t _Nullable) queue;
+(monal_void_block_t) startQueuedTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func onQueue:(dispatch_queue_t _Nullable) queue;

+(NSString*) appBuildVersionInfoFor:(MLVersionType) type;

+(NSNumber*) currentTimestampInSeconds;
+(NSNumber*) dateToNSNumberSeconds:(NSDate*) date;

+(BOOL) constantTimeCompareAttackerString:(NSString* _Nonnull) str1 withKnownString:(NSString* _Nonnull) str2;

+(BOOL) isIP:(NSString*) host;

+(NSURLSession*) createEphemeralURLSession;

@end

NS_ASSUME_NONNULL_END
