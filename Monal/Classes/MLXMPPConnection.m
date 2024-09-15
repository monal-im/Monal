//
//  MLXMPPConnection.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPConnection.h"
#import "MLXMLNode.h"

@interface MLXMPPConnection ()

@property (nonatomic) MLXMPPServer* server;
@property (nonatomic) MLXMPPIdentity* identity;

@end

@implementation MLXMPPConnection

-(id) initWithServer:(MLXMPPServer*) server andIdentity:(MLXMPPIdentity*) identity
{
    self = [super init];
    self.server = server;
    self.identity = identity;
    self.serverFeatures = [MLXMLNode new];
    self.accountDiscoFeatures = [NSSet new];
    self.serverDiscoFeatures = [NSSet new];
    self.serverContactAddresses = [NSDictionary new];
    self.conferenceServers = [NSMutableDictionary new];
    self.discoveredServices = [NSMutableArray new];
    self.discoveredStunTurnServers = [NSMutableArray new];
    self.discoveredAdhocCommands = [NSMutableDictionary new];
    self.serverVersion = nil;
    return self;
}

-(BOOL) supportsRosterVersioning
{
    return [self.serverFeatures check:@"{urn:xmpp:features:rosterver}ver"];
}

-(BOOL) supportsClientState
{
    return [self.serverFeatures check:@"{urn:xmpp:csi:0}csi"];
}

-(BOOL) supportsRosterPreApproval
{
    return [self.serverFeatures check:@"{urn:xmpp:features:pre-approval}sub"];
}

-(NSArray<NSDictionary*>*) conferenceServerIdentities
{
    NSMutableArray<NSDictionary*>* result = [NSMutableArray array];

    for (NSString* jid in self.conferenceServers) {
        NSDictionary* entry = [self.conferenceServers[jid] findFirst:@"identity@@"];
        NSMutableDictionary* mutableEntry = [entry mutableCopy];
        mutableEntry[@"jid"] = jid;
        [result addObject:mutableEntry];
    }

    return [result copy];
}

@end
