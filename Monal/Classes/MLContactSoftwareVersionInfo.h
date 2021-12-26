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
@property (nonatomic, copy) NSString* appName;
@property (nonatomic, copy) NSString* appVersion;
@property (nonatomic, copy) NSString* platformOs;

-(instancetype) initWithJid:(NSString*) jid andRessource:(NSString*) ressource andAppName:(NSString*) appName andAppVersion:(NSString*) appVersion andPlatformOS:(NSString*) platformOs;

@end

NS_ASSUME_NONNULL_END
