//
//  MLContactSoftwareVersionInfo.m
//  monalxmpp
//
//  Created by Friedrich Altheide on 24.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLContactSoftwareVersionInfo.h"

@interface MLContactSoftwareVersionInfo ()

@end

@implementation MLContactSoftwareVersionInfo

-(instancetype) initWithJid:(NSString*) jid andRessource:(NSString*) resource andAppName:(NSString*) appName andAppVersion:(NSString*) appVersion andPlatformOS:(NSString*) platformOs
{
    self = [super init];
    self.fromJid = jid;
    self.resource = resource;
    self.appName = appName;
    self.appVersion = appVersion;
    self.platformOs = platformOs;
    
    return self;
}

@end
