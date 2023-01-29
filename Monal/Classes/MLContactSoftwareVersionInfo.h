//
//  MLContactSofwareVersionInfo.h
//  monalxmpp
//
//  Created by Friedrich Altheide on 24.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLContactSoftwareVersionInfo : NSObject

@property (nonatomic, copy) NSString* fromJid;
@property (nonatomic, copy) NSString* resource;
@property (nonatomic, copy) NSString* _Nullable appName;
@property (nonatomic, copy) NSString* _Nullable appVersion;
@property (nonatomic, copy) NSString* _Nullable platformOs;
@property (nonatomic, copy) NSDate* _Nullable lastInteraction;

-(instancetype) initWithJid:(NSString*) jid andRessource:(NSString*) resource andAppName:(NSString* _Nullable) appName andAppVersion:(NSString* _Nullable) appVersion andPlatformOS:(NSString* _Nullable) platformOs andLastInteraction:(NSDate* _Nullable) lastInteraction;
-(BOOL) isEqual:(id _Nullable) object;
-(NSUInteger) hash;

@end

NS_ASSUME_NONNULL_END
