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

@interface HelperTools : NSObject

+(NSString*) generateStringOfFeatureSet:(NSSet*) features;
+(NSSet*) getOwnFeatureSet;
+(NSString*) getOwnCapsHash;
+(NSString*) getEntityCapsHashForIdentities:(NSArray*) identities andFeatures:(NSSet*) features;
+(NSString* _Nullable) formatLastInteraction:(NSDate*) lastInteraction;
+(NSDate*) parseDateTimeString:(NSString*) datetime;
+(NSString*) generateDateTimeString:(NSDate*) datetime;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler;
+(monal_void_block_t) startTimer:(double) timeout withHandler:(monal_void_block_t) handler andCancelHandler:(monal_void_block_t) cancelHandler;
+(NSString*) encodeRandomResource;
+(NSString*) encodeBase64WithString:(NSString*) strData;
+(NSString*) encodeBase64WithData:(NSData*) objData;
+(NSData*) dataWithBase64EncodedString:(NSString*) string;

+ (NSString *)hexadecimalString:(NSData*) data;
+ (NSData *)dataWithHexString:(NSString *)hex;
+ (NSString *)signalHexKeyWithData:(NSData*) data;

@end

NS_ASSUME_NONNULL_END
