//
//  HelperTools.h
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

void logException(NSException* exception);

@interface HelperTools : NSObject

+(void) configureFileProtectionFor:(NSString*) file;
+(NSDictionary*) splitJid:(NSString*) jid;
+(void) postSendingErrorNotification;
+(NSString*) sha256HmacForKey: (NSString*) key andData: (NSString*) data;
+(BOOL) isInBackground;
+(void) dispatchSyncReentrant:(monal_void_block_t) block onQueue:(dispatch_queue_t) queue;
+(void) activityLog;
+(NSUserDefaults*) defaultsDB;
+(DDFileLogger*) configureLogging;
+(BOOL) isAppExtension;
+(NSString*) generateStringOfFeatureSet:(NSSet*) features;
+(NSSet*) getOwnFeatureSet;
+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features;
+(NSString* _Nullable) formatLastInteraction:(NSDate*) lastInteraction;
+(NSDate*) parseDateTimeString:(NSString*) datetime;
+(NSString*) generateDateTimeString:(NSDate*) datetime;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t _Nullable) cancelHandler;
+(NSString*) encodeRandomResource;
+(NSString*) encodeBase64WithString:(NSString*) strData;
+(NSString*) encodeBase64WithData:(NSData*) objData;
+(NSData*) dataWithBase64EncodedString:(NSString*) string;

+ (NSString *)hexadecimalString:(NSData*) data;
+ (NSData *)dataWithHexString:(NSString *)hex;
+ (NSString *)signalHexKeyWithData:(NSData*) data;

+(UIView*) MLCustomViewHeaderWithTitle:(NSString*) title;

@end

NS_ASSUME_NONNULL_END
