//
//  MLContactSoftwareVersionInfo.m
//  monalxmpp
//
//  Created by Friedrich Altheide on 24.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <monalxmpp/MLContactSoftwareVersionInfo.h>

@interface MLContactSoftwareVersionInfo ()

@end

@implementation MLContactSoftwareVersionInfo

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(instancetype) initWithJid:(NSString*) jid andRessource:(NSString* _Nullable) resource andAppName:(NSString* _Nullable) appName andAppVersion:(NSString* _Nullable) appVersion andPlatformOS:(NSString* _Nullable) platformOs andLastInteraction:(NSDate* _Nullable) lastInteraction
{
    self = [super init];
    self.fromJid = jid;
    self.resource = resource;
    self.appName = appName;
    self.appVersion = appVersion;
    self.platformOs = platformOs;
    self.lastInteraction = lastInteraction;
    return self;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.fromJid forKey:@"fromJid"];
    [coder encodeObject:self.resource forKey:@"resource"];
    [coder encodeObject:self.appName forKey:@"appName"];
    [coder encodeObject:self.appVersion forKey:@"appVersion"];
    [coder encodeObject:self.platformOs forKey:@"platformOs"];
    [coder encodeObject:self.lastInteraction forKey:@"lastInteraction"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    self.fromJid = [coder decodeObjectForKey:@"fromJid"];
    self.resource = [coder decodeObjectForKey:@"resource"];
    self.appName = [coder decodeObjectForKey:@"appName"];
    self.appVersion = [coder decodeObjectForKey:@"appVersion"];
    self.platformOs = [coder decodeObjectForKey:@"platformOs"];
    self.lastInteraction = [coder decodeObjectForKey:@"lastInteraction"];
    return self;
}

-(BOOL) isEqual:(id _Nullable) object
{
    if(object == nil)
        return NO;
    else if(self == object)
        return YES;
    else if([object isKindOfClass:[MLContactSoftwareVersionInfo class]])
    {
        MLContactSoftwareVersionInfo* other = ((MLContactSoftwareVersionInfo*)object);
        return [self.fromJid isEqualToString:other.fromJid] && ((self.resource != nil && [self.resource isEqualToString:other.resource]) || (self.resource == nil && other.resource == nil));
    }
    else
        return NO;
}

-(NSUInteger) hash
{
    return [self.fromJid hash] ^ [self.resource hash];
}

-(NSString*) id
{
    if(self.resource == nil)
        return [NSString stringWithFormat:@"%@", self.fromJid];
    return [NSString stringWithFormat:@"%@/%@", self.fromJid, self.resource];
}

@end
