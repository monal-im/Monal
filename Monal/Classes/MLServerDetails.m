//
//  MLServerDetails.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/21/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLServerDetails.h"
#import "UIColor+Theme.h"
#import "SCRAM.h"
#import "MLContactSoftwareVersionInfo.h"
#import "DataLayer.h"

@interface MLServerDetails ()

@property (nonatomic, strong) MLContactSoftwareVersionInfo* serverVersion;
@property (nonatomic, strong) NSMutableArray* serverCaps;
@property (nonatomic, strong) NSMutableArray* mucServers;
@property (nonatomic, strong) NSMutableArray* stunTurnServers;
@property (nonatomic, strong) NSMutableArray* srvRecords;
@property (nonatomic, strong) NSMutableArray* tlsVersions;
@property (nonatomic, strong) NSMutableArray* saslMethods;
@property (nonatomic, strong) NSMutableArray* channelBindingTypes;

@end

@implementation MLServerDetails

//TODO: make all of these shareable as one long text (or json)
enum MLServerDetailsSections {
    SERVER_VERSION_SECTION,
    SUPPORTED_SERVER_XEPS_SECTION,
    MUC_SERVERS_SECTION,
    VOIP_SECTION,
    SRV_RECORS_SECTION,
    TLS_SECTION,
    SASL_SECTION,
    CB_SECTION,
    ML_SERVER_DETAILS_SECTIONS_CNT
};

#define SERVER_DETAILS_COLOR_OK @"Blue"
#define SERVER_DETAILS_COLOR_NON_IDEAL @"Orange"
#define SERVER_DETAILS_COLOR_ERROR @"Red"
#define SERVER_DETAILS_COLOR_NONE @""

- (void) viewDidLoad
{
    [super viewDidLoad];
}

-(void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear:animated];
    self.serverCaps = [NSMutableArray new];
    self.mucServers = [NSMutableArray new];
    self.stunTurnServers = [NSMutableArray new];
    self.srvRecords = [NSMutableArray new];
    self.tlsVersions = [NSMutableArray new];
    self.saslMethods = [NSMutableArray new];
    self.channelBindingTypes = [NSMutableArray new];

    self.navigationItem.title = self.xmppAccount.connectionProperties.identity.domain;
    self.tableView.allowsSelection = NO;

    self.serverVersion = self.xmppAccount.connectionProperties.serverVersion;
    [self checkServerCaps:self.xmppAccount.connectionProperties];
    [self checkMucServers:self.xmppAccount.connectionProperties];
    [self convertSRVRecordsToReadable];
    [self checkTLSVersions:self.xmppAccount.connectionProperties];
    [self checkSASLMethods:self.xmppAccount.connectionProperties];
    [self checkChannelBindingTypes:self.xmppAccount.connectionProperties];
    
    [self checkStunServers:self.xmppAccount.connectionProperties.discoveredStunTurnServers];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void) checkServerCaps:(MLXMPPConnection*) connection
{
    // supportsPubSub
    [self.serverCaps addObject:@{
        // see MLIQProcessor.m multiple xep required for pubsub
        @"Title":NSLocalizedString(@"XEP-0163 Personal Eventing Protocol", @""),
        @"Description":NSLocalizedString(@"This specification defines semantics for using the XMPP publish-subscribe protocol to broadcast state change events associated with an instant messaging and presence account.", @""),
        @"Color": connection.supportsPubSub ? (connection.supportsModernPubSub ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_NON_IDEAL) : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsBlocking
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0191: Blocking Command", @""),
        @"Description":NSLocalizedString(@"XMPP protocol extension for communications blocking.", @""),
        @"Color": [connection.serverDiscoFeatures containsObject:@"urn:xmpp:blocking"] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsSM3
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0198: Stream Management", @""),
        @"Description":NSLocalizedString(@"Resume a stream when disconnected. Results in faster reconnect and saves battery life.", @""),
        @"Color": connection.supportsSM3 ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsPing
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0199: XMPP Ping", @""),
        @"Description":NSLocalizedString(@"XMPP protocol extension for sending application-level pings over XML streams.", @""),
        @"Color": [connection.serverDiscoFeatures containsObject:@"urn:xmpp:ping"] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsExternalServiceDiscovery
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0215: External Service Discovery", @""),
        @"Description":NSLocalizedString(@"XMPP protocol extension for discovering services external to the XMPP network, like STUN or TURN servers needed for A/V calls.", @""),
        @"Color": [connection.serverDiscoFeatures containsObject:@"urn:xmpp:extdisco:2"] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];
    
    // supportsRosterVersion
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0237: Roster Versioning", @""),
        @"Description":NSLocalizedString(@"Defines a proposed modification to the XMPP roster protocol that enables versioning of rosters such that the server will not send the roster to the client if the roster has not been modified.", @""),
        @"Color": [connection.serverFeatures check:@"{urn:xmpp:features:rosterver}ver"] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // usingCarbons2
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0280: Message Carbons", @""),
        @"Description":NSLocalizedString(@"Synchronize your messages on all loggedin devices.", @""),
        @"Color": connection.usingCarbons2 ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsMam2
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0313: Message Archive Management", @""),
        @"Description":NSLocalizedString(@"Access message archives on the server.", @""),
        @"Color": [connection.accountDiscoFeatures containsObject:@"urn:xmpp:mam:2"]  ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsClientState
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0352: Client State Indication", @""),
        @"Description":NSLocalizedString(@"Indicate when a particular device is active or inactive. Saves battery.", @""),
        @"Color": [connection.serverFeatures check:@"{urn:xmpp:csi:0}csi"] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsPush / pushEnabled
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0357: Push Notifications", @""),
        @"Description":NSLocalizedString(@"Receive push notifications via Apple even when disconnected. Vastly improves reliability.", @""),
        @"Color": [connection.accountDiscoFeatures containsObject:@"urn:xmpp:push:0"] ? (connection.pushEnabled ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_NON_IDEAL) : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsHTTPUpload
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0363: HTTP File Upload", @""),
        @"Description":[NSString stringWithFormat:NSLocalizedString(@"Upload files to the server to share with others. (Maximum allowed size of files reported by the server: %@)", @""), [HelperTools bytesToHuman:connection.uploadSize]],
        @"Color": connection.supportsHTTPUpload ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsRosterPreApproval
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0379: Pre-Authenticated Roster Subscription", @""),
        @"Description":NSLocalizedString(@"Defines a protocol and URI scheme for pre-authenticated roster links that allow a third party to automatically obtain the user's presence subscription.", @""),
        @"Color": [connection.serverFeatures check:@"{urn:xmpp:features:pre-approval}sub"] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];

    // supportsSSDP
    [self.serverCaps addObject:@{
        // see MLIQProcessor.m multiple xep required for pubsub
        @"Title":NSLocalizedString(@"XEP-0474: SASL SCRAM Downgrade Protection", @""),
        @"Description":NSLocalizedString(@"This specification provides a way to secure the SASL and SASL2 handshakes against method and channel-binding downgrades.", @""),
        @"Color": connection.supportsSSDP ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_ERROR
    }];
}

-(void) checkMucServers:(MLXMPPConnection*) connection
{
    DDLogVerbose(@"Checking muc servers: %@", connection.conferenceServers);
    //yes, checkMucServers: is plural, but for now, our connectionProperties only store one single muc server (the first one encountered)
    if(connection.conferenceServers.count == 0)
    {
        [self.mucServers addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not provide any MUC servers.", @""), @"Color":SERVER_DETAILS_COLOR_ERROR}];
        return;
    }
    for(NSString* jid in connection.conferenceServers)
    {
        NSDictionary* entry = [connection.conferenceServers[jid] findFirst:@"identity@@"];
        [self.mucServers addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Server: %@", @""), jid], @"Description": [NSString stringWithFormat:NSLocalizedString(@"%@ (type '%@', category '%@')", @""), entry[@"name"], entry[@"type"], entry[@"category"]], @"Color": [@"text" isEqualToString:entry[@"type"]] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_NONE}];
    }
    DDLogVerbose(@"Extracted muc server entries: %@", self.mucServers);
}

-(void) checkStunServers:(NSMutableArray<NSDictionary*>*) stunTurnServers
{
    for(NSDictionary* service in stunTurnServers)
    {
        NSString* color;
        if(service[@"type"] && ([service[@"type"] isEqualToString:@"stun"] || [service[@"type"] isEqualToString:@"turn"]))
        {
            color = SERVER_DETAILS_COLOR_OK;
        }
        else if(service[@"type"] && ([service[@"type"] isEqualToString:@"stuns"] || [service[@"type"] isEqualToString:@"turns"]))
        {
            color = SERVER_DETAILS_COLOR_OK;
        }
        else
        {
            color = SERVER_DETAILS_COLOR_ERROR;
        }
        [self.stunTurnServers addObject:@{
            @"Title": service[@"type"],
            @"Description": [NSString stringWithFormat:@"%@:%@", service[@"host"], service[@"port"]],
            @"Color": color
        }];
    }
}

-(void) convertSRVRecordsToReadable
{
    BOOL foundCurrentConn = NO;

    if(self.xmppAccount.discoveredServersList == nil || self.xmppAccount.discoveredServersList.count == 0)
    {
        [self.srvRecords addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not have any SRV records in DNS.", @""), @"Color":SERVER_DETAILS_COLOR_ERROR}];
            return;
    }
    
    for(id srvEntry in self.xmppAccount.discoveredServersList)
    {
        NSString* hostname = [srvEntry objectForKey:@"server"];
        NSNumber* port = [srvEntry objectForKey:@"port"];
        NSString* isSecure = [[srvEntry objectForKey:@"isSecure"] boolValue] ? NSLocalizedString(@"Yes", @"") : NSLocalizedString(@"No", @"");
        NSString* prio = [srvEntry objectForKey:@"priority"];

        // Check if entry is currently in use
        NSString* entryColor = SERVER_DETAILS_COLOR_NONE;
        if([self.xmppAccount.connectionProperties.server.connectServer isEqualToString:hostname] &&
           self.xmppAccount.connectionProperties.server.connectPort == port &&
           self.xmppAccount.connectionProperties.server.isDirectTLS == [[srvEntry objectForKey:@"isSecure"] boolValue])
        {
            entryColor = SERVER_DETAILS_COLOR_OK;
            foundCurrentConn = YES;
        }
        else if(!foundCurrentConn)
        {
            // Set the color of all connections entries that failed to red
            // discoveredServersList is sorted. Therfore all entries before foundCurrentConn == YES have failed
            entryColor = SERVER_DETAILS_COLOR_ERROR;
        }

        [self.srvRecords addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Server: %@", @""), hostname], @"Description": [NSString stringWithFormat:NSLocalizedString(@"Port: %@, Direct TLS: %@, Priority: %@", @""), port, isSecure, prio], @"Color": entryColor}];
    }
}

-(void) checkTLSVersions:(MLXMPPConnection*) connection
{
    DDLogVerbose(@"connection uses tls version: %@", connection.tlsVersion);
    [self.tlsVersions addObject:@{@"Title": NSLocalizedString(@"TLS 1.2", @""), @"Description":NSLocalizedString(@"Older, slower, but still secure TLS version", @""), @"Color":([@"1.2" isEqualToString:connection.tlsVersion] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_NONE)}];
    [self.tlsVersions addObject:@{@"Title": NSLocalizedString(@"TLS 1.3", @""), @"Description":NSLocalizedString(@"Newest TLS version which is faster than TLS 1.2", @""), @"Color":([@"1.3" isEqualToString:connection.tlsVersion] ? SERVER_DETAILS_COLOR_OK : SERVER_DETAILS_COLOR_NONE)}];
    DDLogVerbose(@"tls versions: %@", self.tlsVersions);
}

-(void) checkSASLMethods:(MLXMPPConnection*) connection
{
    DDLogVerbose(@"saslMethods: %@", connection.saslMethods);
    if(connection.saslMethods == nil || connection.saslMethods.count == 0)
    {
        [self.saslMethods addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not support modern SASL2 authentication.", @""), @"Color":SERVER_DETAILS_COLOR_ERROR}];
        return;
    }
    for(NSString* method in [connection.saslMethods.allKeys sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]])
    {
        BOOL used = [connection.saslMethods[method] boolValue];
        BOOL supported = [[SCRAM supportedMechanismsIncludingChannelBinding:YES] containsObject:method];    // || [@[@"PLAIN"] containsObject:method];
        NSString* description = NSLocalizedString(@"Unknown authentication method", @"");
        if([method isEqualToString:@"PLAIN"])
            description = NSLocalizedString(@"Sends password in cleartext (only encrypted by TLS), not very secure", @"");
        else if([method isEqualToString:@"EXTERNAL"])
            description = NSLocalizedString(@"Uses TLS client certificates for authentication", @"");
        else if([method hasPrefix:@"SCRAM-"] && [method hasSuffix:@"-PLUS"])
            description = NSLocalizedString(@"Salted Challenge Response Authentication Mechanism using the given Hash Method additionally secured by Channel-Binding", @"");
        else if([method hasPrefix:@"SCRAM-"])
            description = NSLocalizedString(@"Salted Challenge Response Authentication Mechanism using the given Hash Method", @"");
        [self.saslMethods addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Method: %@", @""), method], @"Description":description, @"Color":(used ? SERVER_DETAILS_COLOR_OK : (!supported ? SERVER_DETAILS_COLOR_NON_IDEAL : SERVER_DETAILS_COLOR_NONE))}];
    }
}

-(void) checkChannelBindingTypes:(MLXMPPConnection*) connection
{
    DDLogVerbose(@"channelBindingTypes: %@", connection.channelBindingTypes);
    if(connection.channelBindingTypes == nil || connection.channelBindingTypes.count == 0)
    {
        [self.channelBindingTypes addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not support any modern channel-binding to secure against MITM attacks on the TLS layer.", @""), @"Color":SERVER_DETAILS_COLOR_ERROR}];
        return;
    }
    NSArray* supportedChannelBindingTypes = self.xmppAccount.supportedChannelBindingTypes;
    for(NSString* type in [connection.channelBindingTypes.allKeys sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]])
    {
        BOOL used = [connection.channelBindingTypes[type] boolValue];
        BOOL supported = [supportedChannelBindingTypes containsObject:type];
        NSString* description = NSLocalizedString(@"Unknown channel-binding type", @"");
        if([type isEqualToString:@"tls-exporter"])
            description = NSLocalizedString(@"Secure channel-binding defined for TLS1.3 and some TLS1.2 connections.", @"");
        else if([type isEqualToString:@"tls-server-end-point"])
            description = NSLocalizedString(@"Weakest channel-binding type, not securing against stolen certs/keys, but detects wrongly issued certs.", @"");
        [self.channelBindingTypes addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Type: %@", @""), type], @"Description":description, @"Color":(used ? SERVER_DETAILS_COLOR_OK : (!supported ? SERVER_DETAILS_COLOR_NON_IDEAL : SERVER_DETAILS_COLOR_NONE))}];
    }
}

#pragma mark - Table view data source

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return ML_SERVER_DETAILS_SECTIONS_CNT;
}

-(NSInteger) tableView:(UITableView*) tableView numberOfRowsInSection:(NSInteger) section
{
    if(section == SERVER_VERSION_SECTION)
        return 1;
    else if(section == SUPPORTED_SERVER_XEPS_SECTION)
        return (NSInteger)self.serverCaps.count;
    else if(section == MUC_SERVERS_SECTION)
        return (NSInteger)self.mucServers.count;
    else if(section == VOIP_SECTION)
        return (NSInteger)self.stunTurnServers.count;
    else if(section == SRV_RECORS_SECTION)
        return (NSInteger)self.srvRecords.count;
    else if(section == TLS_SECTION)
        return (NSInteger)self.tlsVersions.count;
    else if(section == SASL_SECTION)
        return (NSInteger)self.saslMethods.count;
    else if(section == CB_SECTION)
        return (NSInteger)self.channelBindingTypes.count;
    return 0;
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"serverCell" forIndexPath:indexPath];

    NSDictionary* dic;
    if(indexPath.section == SERVER_VERSION_SECTION)
    {
        if(indexPath.row == 0)
        {
            NSString* serverName = nilDefault(self.serverVersion.appName, NSLocalizedString(@"<unknown server>", @"server details"));
            NSString* serverVersion = nilDefault(self.serverVersion.appVersion, NSLocalizedString(@"<unknown version>", @"server details"));
            NSString* serverPlatform = self.serverVersion.platformOs != nil ? [NSString stringWithFormat:NSLocalizedString(@" running on %@", @"server details"), self.serverVersion.platformOs] : @"";
            dic = @{
                @"Color": SERVER_DETAILS_COLOR_NONE, 
                @"Title": serverName,
                @"Description": [NSString stringWithFormat:NSLocalizedString(@"version %@%@", @"server details"), serverVersion, serverPlatform],
            };
        }
    }
    else if(indexPath.section == SUPPORTED_SERVER_XEPS_SECTION)
        dic = [self.serverCaps objectAtIndex:(NSUInteger)indexPath.row];
    else if(indexPath.section == MUC_SERVERS_SECTION)
        dic = [self.mucServers objectAtIndex:(NSUInteger)indexPath.row];
    else if(indexPath.section == VOIP_SECTION)
        dic = [self.stunTurnServers objectAtIndex:(NSUInteger)indexPath.row];
    else if(indexPath.section == SRV_RECORS_SECTION)
        dic = [self.srvRecords objectAtIndex:(NSUInteger)indexPath.row];
    else if(indexPath.section == TLS_SECTION)
        dic = [self.tlsVersions objectAtIndex:(NSUInteger)indexPath.row];
    else if(indexPath.section == SASL_SECTION)
        dic = [self.saslMethods objectAtIndex:(NSUInteger)indexPath.row];
    else if(indexPath.section == CB_SECTION)
        dic = [self.channelBindingTypes objectAtIndex:(NSUInteger)indexPath.row];

    cell.textLabel.text = nilExtractor([dic objectForKey:@"Title"]);
    cell.detailTextLabel.text = nilExtractor([dic objectForKey:@"Description"]);

    // Add background color to selected cells
    if([dic objectForKey:@"Color"])
    {
        NSString* entryColor = [dic objectForKey:@"Color"];
        // Remove background color from textLabel & detailTextLabel
        cell.textLabel.backgroundColor = UIColor.clearColor;
        cell.detailTextLabel.backgroundColor = UIColor.clearColor;

        if([entryColor isEqualToString:SERVER_DETAILS_COLOR_OK])
        {
            if(self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
                [cell setBackgroundColor:[UIColor colorWithRed:0.43 green:0.52 blue:0.93 alpha:1.0]];
            else
                [cell setBackgroundColor:[UIColor colorWithRed:0.76 green:0.76 blue:0.96 alpha:1.0]];
        }
        else if([entryColor isEqualToString:SERVER_DETAILS_COLOR_ERROR])
        {
            if(self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
                [cell setBackgroundColor:[UIColor colorWithRed:0.93 green:0.47 blue:0.47 alpha:1.0]];
            else
                [cell setBackgroundColor:[UIColor colorWithRed:0.96 green:0.76 blue:0.78 alpha:1.0]];
        }
        else if([entryColor isEqualToString:SERVER_DETAILS_COLOR_NON_IDEAL])
        {
            if(self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
                [cell setBackgroundColor:[UIColor colorWithRed:0.82 green:0.75 blue:0.37 alpha:1.0]];
            else
                [cell setBackgroundColor:[UIColor colorWithRed:0.96 green:0.93 blue:0.70 alpha:1.0]];
        }
        else
            [cell setBackgroundColor:nil];
    }
    return cell;
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    if(section == SERVER_VERSION_SECTION)
        return NSLocalizedString(@"This is the software running on your server.", @"");
    else if(section == SUPPORTED_SERVER_XEPS_SECTION)
        return NSLocalizedString(@"These are the modern XMPP capabilities Monal detected on your server after you have logged in.", @"");
    else if(section == MUC_SERVERS_SECTION)
        return NSLocalizedString(@"These are the MUC servers detected by Monal (blue entry used by Monal).", @"");
    else if(section == VOIP_SECTION)
        return NSLocalizedString(@"These are STUN and TURN services announced by your server (blue entries are used by Monal).", @"");
    else if(section == SRV_RECORS_SECTION)
        return NSLocalizedString(@"These are SRV resource records found for your domain.", @"");
    else if(section == TLS_SECTION)
        return NSLocalizedString(@"These are the TLS versions supported by Monal, the one used to connect to your server will be green.", @"");
    else if(section == SASL_SECTION)
        return NSLocalizedString(@"These are the SASL2 methods your server supports (used one in blue, orange ones unsupported by Monal).", @"");
    else if(section == CB_SECTION)
        return NSLocalizedString(@"These are the channel-binding types your server supports to detect attacks on the TLS layer (used one in blue, orange ones unsupported by Monal).", @"");
    return @"";
}

@end
