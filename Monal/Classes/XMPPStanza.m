//
//  XMPPStanza.m
//  monalxmpp
//
//  Created by Thilo Molitor on 24.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/XMPPStanza.h>
#import <monalxmpp/HelperTools.h>

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
    if(from == nil)
    {
        [self.attributes removeObjectForKey:@"from"];
        return;
    }
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

-(void) setFromUser:(NSString* _Nullable) user
{
    @synchronized(self.attributes) {
        if(user == nil)
            [self.attributes removeObjectForKey:@"from"];
        else
        {
            if(self.attributes[@"from"] == nil)
                self.attributes[@"from"] = [user lowercaseString];
            else
            {
                NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
                self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", [user lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
            }
        }
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
    @synchronized(self.attributes) {
        if(self.attributes[@"from"] == nil)
            MLAssert(node == nil, @"You can't set a node value if there's no host!");
        else
        {
            NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
            MLAssert(jid[@"host"] != nil, @"You can't set a node value if there's no host!");
            if(node == nil)
                self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
            else
                self.attributes[@"from"] = [NSString stringWithFormat:@"%@@%@%@", [node lowercaseString], jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        }
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
        if(self.attributes[@"from"] == nil)
        {
            if(host == nil)
                ;   // do nothing, everything's already nil
            else
                self.attributes[@"from"] = [host lowercaseString];
        }
        else
        {
            if(host == nil)
                [self.attributes removeObjectForKey:@"from"];
            else
            {
                NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
                if(jid[@"node"])
                    self.attributes[@"from"] = [NSString stringWithFormat:@"%@@%@%@", jid[@"node"], [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
                else
                    self.attributes[@"from"] = [NSString stringWithFormat:@"%@%@", [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
            }
        }
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
        if(self.attributes[@"from"] == nil)
            return;     // do nothing: we can't set a resource if we don't have a host
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"from"]];
        if(jid[@"user"] == nil)
            return;     // do nothing: we can't set a resource if we don't have a host
        else
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
    if(to == nil)
    {
        [self.attributes removeObjectForKey:@"to"];
        return;
    }
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

-(void) setToUser:(NSString* _Nullable) user
{
    @synchronized(self.attributes) {
        if(user == nil)
            [self.attributes removeObjectForKey:@"to"];
        else
        {
            if(self.attributes[@"to"] == nil)
                self.attributes[@"to"] = [user lowercaseString];
            else
            {
                NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
                self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", [user lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
            }
        }
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
        if(self.attributes[@"to"] == nil)
            MLAssert(node == nil, @"You can't set a node value if there's no host!");
        else
        {
            NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
            MLAssert(jid[@"host"] != nil, @"You can't set a node value if there's no host!");
            if(node == nil)
                self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
            else
                self.attributes[@"to"] = [NSString stringWithFormat:@"%@@%@%@", [node lowercaseString], jid[@"host"], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
        }
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
        if(self.attributes[@"to"] == nil)
        {
            if(host == nil)
                ;   // do nothing, everything's already nil
            else
                self.attributes[@"to"] = [host lowercaseString];
        }
        else
        {
            if(host == nil)
                [self.attributes removeObjectForKey:@"to"];
            else
            {
                NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
                if(jid[@"node"])
                    self.attributes[@"to"] = [NSString stringWithFormat:@"%@@%@%@", jid[@"node"], [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
                else
                    self.attributes[@"to"] = [NSString stringWithFormat:@"%@%@", [host lowercaseString], jid[@"resource"] ? [NSString stringWithFormat:@"/%@", jid[@"resource"]] : @""];
            }
        }
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
        if(self.attributes[@"to"] == nil)
            return;     // do nothing: we can't set a resource if we don't have a host
        NSDictionary* jid = [HelperTools splitJid:self.attributes[@"to"]];
        if(jid[@"user"] == nil)
            return;     // do nothing: we can't set a resource if we don't have a host
        else
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
