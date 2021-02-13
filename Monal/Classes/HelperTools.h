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

#define createTimer(timeout, handler, ...)						metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([HelperTools startTimer:timeout withHandler:handler andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])(_createTimer(timeout, handler, __VA_ARGS__))
#define _createTimer(timeout, handler, cancelHandler, ...)		[HelperTools startTimer:timeout withHandler:handler andCancelHandler:cancelHandler andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]

NS_ASSUME_NONNULL_BEGIN

@class XMPPStanza;

void logException(NSException* exception);

@interface HelperTools : NSObject

+(NSDictionary*) pushServer;
+(NSString*) stringFromToken:(NSData*) tokenIn;
+(NSString*) extractXMPPError:(XMPPStanza*) stanza withDescription:(NSString* _Nullable) description;
+(void) configureFileProtectionFor:(NSString*) file;
+(NSDictionary<NSString*, NSString*>*) splitJid:(NSString*) jid;
+(void) updateSyncErrorsWithDeleteOnly:(BOOL) removeOnly;
+(BOOL) isInBackground;
+(void) dispatchSyncReentrant:(monal_void_block_t) block onQueue:(dispatch_queue_t) queue;
+(void) activityLog;
+(NSUserDefaults*) defaultsDB;
@property (class, nonatomic, strong) DDFileLogger* fileLogger;
+(void) configureLogging;
+(BOOL) isAppExtension;
+(NSString*) generateStringOfFeatureSet:(NSSet*) features;
+(NSSet*) getOwnFeatureSet;
+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features;
+(NSString* _Nullable) formatLastInteraction:(NSDate*) lastInteraction;
+(NSDate*) parseDateTimeString:(NSString*) datetime;
+(NSString*) generateDateTimeString:(NSDate*) datetime;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andFile:(char*) file andLine:(int) line andFunc:(char*) func;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler andFile:(char*) file andLine:(int) line andFunc:(char*) func;
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

@end

NS_ASSUME_NONNULL_END
