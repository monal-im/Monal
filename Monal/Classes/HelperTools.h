//
//  HelperTools.h
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

#include "metamacros.h"

#define createTimer(timeout, handler, ...)						            createQueuedTimer(timeout, nil, handler, __VA_ARGS__)
#define createQueuedTimer(timeout, queue, handler, ...)						metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([HelperTools startQueuedTimer:timeout withHandler:handler andCancelHandler:nil andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__ onQueue:queue])(_createQueuedTimer(timeout, queue, handler, __VA_ARGS__))
#define _createQueuedTimer(timeout, queue, handler, cancelHandler, ...)		[HelperTools startQueuedTimer:timeout withHandler:handler andCancelHandler:cancelHandler andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__ onQueue:queue]

#define MLAssert(check, text, ...)                                          metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([HelperTools MLAssert:check withText:text andUserData:nil])([HelperTools MLAssert:check withText:text andUserData:metamacro_head(__VA_ARGS__)])

NS_ASSUME_NONNULL_BEGIN

@class MLXMLNode;
@class xmpp;
@class XMPPStanza;
@class UNNotificationRequest;

void logException(NSException* exception);

@interface HelperTools : NSObject

+(void) MLAssert:(BOOL) check withText:(NSString*) text andUserData:(id _Nullable) additionalData;
+(void) postError:(NSString*) description withNode:(XMPPStanza* _Nullable) node andAccount:(xmpp*) account andIsSevere:(BOOL) isSevere;
+(NSString*) extractXMPPError:(XMPPStanza*) stanza withDescription:(NSString* _Nullable) description;
+(NSString*) pushServer;

+(NSData*) serializeObject:(id) obj;
+(id) unserializeData:(NSData*) data;
+(NSError* _Nullable) postUserNotificationRequest:(UNNotificationRequest*) request;
+(NSData*) resizeAvatarImage:(UIImage* _Nullable) image withCircularMask:(BOOL) circularMask toMaxBase64Size:(unsigned long) length;
+(double) report_memory;
+(UIColor*) generateColorFromJid:(NSString*) jid;
+(NSString*) bytesToHuman:(int64_t) bytes;
+(NSString*) stringFromToken:(NSData*) tokenIn;
+(void) configureFileProtectionFor:(NSString*) file;
+(NSDictionary<NSString*, NSString*>*) splitJid:(NSString*) jid;
+(void) clearSyncErrorsOnAppForeground;
+(void) updateSyncErrorsWithDeleteOnly:(BOOL) removeOnly andWaitForCompletion:(BOOL) waitForCompletion;

+(BOOL) isInBackground;
+(BOOL) isNotInFocus;

+(void) dispatchSyncReentrant:(monal_void_block_t) block onQueue:(dispatch_queue_t) queue;
+(void) activityLog;
+(NSUserDefaults*) defaultsDB;
@property (class, nonatomic, strong) DDFileLogger* fileLogger;
+(void) configureLogging;
+(BOOL) isAppExtension;
+(NSString*) generateStringOfFeatureSet:(NSSet*) features;
+(NSSet*) getOwnFeatureSet;
+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features andForms:(NSArray*) forms;
+(NSString* _Nullable) formatLastInteraction:(NSDate*) lastInteraction;
+(NSDate*) parseDateTimeString:(NSString*) datetime;
+(NSString*) generateDateTimeString:(NSDate*) datetime;
+(NSString*) encodeRandomResource;
+(NSData* _Nullable) sha1:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha1:(NSString* _Nullable) data;
+(NSData* _Nullable) sha256:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha256:(NSString* _Nullable) data;
+(NSData* _Nullable) sha256HmacForKey:(NSData* _Nullable) key andData:(NSData* _Nullable) data;
+(NSString* _Nullable) stringSha256HmacForKey:(NSString* _Nullable) key andData:(NSString* _Nullable) data;
+(NSString*) encodeBase64WithString:(NSString*) strData;
+(NSString*) encodeBase64WithData:(NSData*) objData;
+(NSData*) dataWithBase64EncodedString:(NSString*) string;

+(NSString *)hexadecimalString:(NSData*) data;
+(NSData *)dataWithHexString:(NSString *)hex;
+(NSString *)signalHexKeyWithData:(NSData*) data;
+(NSString *)signalHexKeyWithSpacesWithData:(NSData*) data;

+(UIView*) MLCustomViewHeaderWithTitle:(NSString*) title;
+(CIImage*) createQRCodeFromString:(NSString*) input;

//don't use these four directly, but via createTimer() makro
+(monal_void_block_t) startQueuedTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func onQueue:(dispatch_queue_t _Nullable) queue;

+(NSString*) appBuildVersionInfo;

+(BOOL) deviceUsesSplitView;

@end

NS_ASSUME_NONNULL_END
