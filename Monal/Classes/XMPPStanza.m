//
//  XMPPStanza.m
//  monalxmpp
//
//  Created by tmolitor on 24.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "XMPPStanza.h"
#import "HelperTools.h"

@implementation XMPPStanza

-(void) addDelayTagFrom:(NSString*) from
{
    MLXMLNode* delay = [[MLXMLNode alloc] initWithElement:@"delay" andNamespace:@"urn:xmpp:delay"];
    delay.attributes[@"from"] = from;
    delay.attributes[@"stamp"] = [HelperTools generateDateTimeString:[NSDate date]];
    [self addChild:delay];
}

-(NSString*) id
{
    @synchronized(self.attributes) {
        return self.attributes[@"id"];
    }
}

-(void) setId:(NSString* _Nullable) id
{
    @synchronized(self.attributes) {
        if(!id)
            [self.attributes removeObjectForKey:@"id"];
        else
            self.attributes[@"id"] = id;
    }
}

-(void) setFrom:(NSString*) from
{
    NSDictionary* jid = [HelperTools splitJid:from];
    @synchronized(self.attributes) {
        self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", jid[@"user"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) from
{
    NSDictionary* jid;
    @synchronized(self.attributes) {
        if(!self.attributes[@"from"])
            return nil;
        jid = [HelperTools splitJid:self.attributes[@"from"]];
    }
    return [NSString stringWithFormat:@"%@%@", jid[@"user"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
}

-(void) setFromUser:(NSString*) user
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", [user lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) fromUser
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"from"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        return jid[@"user"];
    }
}

-(void) setFromNode:(NSString*) node
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        self.attributes[@"from"] = [NSString stringWithFormat:@"%@@%@%@", node, jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) fromNode
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"from"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        return [jid[@"node"] lowercaseString];
    }
}

-(void) setFromHost:(NSString*) host
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        if(jid[@"node"])
            self.attributes[@"from"] = [NSString stringWithFormat:@"%@@%@%@", jid[@"node"], [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        else
            self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) fromHost
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"from"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        return [jid[@"host"] lowercaseString];
    }
}

-(void) setFromResource:(NSString*) resource
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", jid[@"user"], resource && ![resource isEqualToString:@""] ? [NSString stringWithFormat:@"/%@", resource] : @""];
    }
}
-(NSString*) fromResource
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"from"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        return jid[@"resource"];
    }
}

-(void) setTo:(NSString*) to
{
    NSDictionary* jid = [HelperTools splitJid:to];
    @synchronized(self.attributes) {
        self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", jid[@"user"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) to
{
    NSDictionary* jid;
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        jid = [HelperTools splitJid:self.attributes[@"to"]];
    }
    return [NSString stringWithFormat:@"%@%@", jid[@"user"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
}

-(void) setToUser:(NSString*) user
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", [user lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) toUser
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        return [jid[@"user"] lowercaseString];
    }
}

-(void) setToNode:(NSString*) node
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        self.attributes[@"to"] = [NSString stringWithFormat:@"%@@%@%@", [node lowercaseString], jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) toNode
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        return [jid[@"node"] lowercaseString];
    }
}

-(void) setToHost:(NSString*) host
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        if(jid[@"node"])
            self.attributes[@"to"] = [NSString stringWithFormat:@"%@@%@%@", jid[@"node"], [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        else
            self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) toHost
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        return [jid[@"host"] lowercaseString];
    }
}

-(void) setToResource:(NSString*) resource
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", jid[@"user"], resource && ![resource isEqualToString:@""] ? [NSString stringWithFormat:@"/%@", resource] : @""];
    }
}
-(NSString*) toResource
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        return jid[@"resource"];
    }
}

@end
