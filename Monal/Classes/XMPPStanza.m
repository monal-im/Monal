//
//  XMPPStanza.m
//  monalxmpp
//
//  Created by Thilo Molitor on 24.09.20.
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
    [self addChildNode:delay];
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

-(void) setFrom:(NSString* _Nullable) from
{
    NSDictionary* jid = [HelperTools splitJid:from];
    @synchronized(self.attributes) {
        if(from != nil)
            self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", jid[@"user"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        else
            [self.attributes removeObjectForKey:@"from"];
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

-(void) setFromUser:(NSString* _Nullable) user
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        if(user == nil)
            [self.attributes removeObjectForKey:@"from"];
        else
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

-(void) setFromNode:(NSString* _Nullable) node
{
    if(!self.attributes[@"from"])
        return;
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        if(node == nil)
            self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        else
            self.attributes[@"from"] = [NSString stringWithFormat:@"%@@%@%@", node, jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) fromNode
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"from"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        return jid[@"node"];
    }
}

-(void) setFromHost:(NSString* _Nullable) host
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        if(host == nil)
            [self.attributes removeObjectForKey:@"from"];
        else if(jid[@"node"])
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
        return jid[@"host"];
    }
}

-(void) setFromResource:(NSString*) resource
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        if(jid[@"user"])
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

-(void) setTo:(NSString* _Nullable) to
{
    NSDictionary* jid = [HelperTools splitJid:to];
    @synchronized(self.attributes) {
        if(to != nil)
            self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", jid[@"user"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        else
            [self.attributes removeObjectForKey:@"to"];
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

-(void) setToUser:(NSString* _Nullable) user
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        if(user == nil)
            [self.attributes removeObjectForKey:@"to"];
        else
            self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", [user lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) toUser
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        return jid[@"user"];
    }
}

-(void) setToNode:(NSString* _Nullable) node
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        if(node == nil)
            self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        else
            self.attributes[@"to"] = [NSString stringWithFormat:@"%@@%@%@", [node lowercaseString], jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
    }
}
-(NSString*) toNode
{
    @synchronized(self.attributes) {
        if(!self.attributes[@"to"])
            return nil;
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        return jid[@"node"];
    }
}

-(void) setToHost:(NSString* _Nullable) host
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        if(host == nil)
            [self.attributes removeObjectForKey:@"from"];
        else if(jid[@"node"])
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
        return jid[@"host"];
    }
}

-(void) setToResource:(NSString*) resource
{
    @synchronized(self.attributes) {
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        if(jid[@"user"])
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
