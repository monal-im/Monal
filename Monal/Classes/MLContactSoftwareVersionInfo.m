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

-(BOOL) isEqual:(id _Nullable) object
{
    if(object == nil || self == object)
        return YES;
    else if([object isKindOfClass:[MLContactSoftwareVersionInfo class]])
        return [self.fromJid isEqualToString:((MLContactSoftwareVersionInfo*)object).fromJid] && [self.resource isEqualToString:((MLContactSoftwareVersionInfo*)object).resource];
    else
        return NO;
}

-(NSUInteger) hash
{
    return [self.fromJid hash] ^ [self.resource hash] ^ [self.appName hash] ^ [self.appVersion hash] ^ [self.platformOs hash];
}

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@/%@", self.fromJid, self.resource];
}

@end
