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

@interface MLServerDetails ()

@property (nonatomic, strong) NSMutableArray* serverCaps;
@property (nonatomic, strong) NSMutableArray* srvRecords;
@property (nonatomic, strong) NSMutableArray* saslMethods;
@property (nonatomic, strong) NSMutableArray* channelBindingTypes;

@end

@implementation MLServerDetails

enum MLServerDetailsSections {
    SUPPORTED_SERVER_XEPS_SECTION,
    SRV_RECORS_SECTION,
    SASL_SECTION,
    CB_SECTION,
    ML_SERVER_DETAILS_SECTIONS_CNT
};

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.serverCaps = [[NSMutableArray alloc] init];
    self.srvRecords = [[NSMutableArray alloc] init];
    self.saslMethods = [[NSMutableArray alloc] init];
    self.channelBindingTypes = [[NSMutableArray alloc] init];

    self.navigationItem.title = self.xmppAccount.connectionProperties.identity.domain;
    self.tableView.allowsSelection = NO;

    [self checkServerCaps:self.xmppAccount.connectionProperties];
    [self convertSRVRecordsToReadable];
    [self checkSASLMethods:self.xmppAccount.connectionProperties];
    [self checkChannelBindingTypes:self.xmppAccount.connectionProperties];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void) checkServerCaps:(MLXMPPConnection*) connection
{
    // supportsBlocking
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0191: Blocking Command", @""),
        @"Description":NSLocalizedString(@"XMPP protocol extension for communications blocking.", @""),
        @"Color": connection.supportsBlocking ? @"Green" : @"Red"
    }];

    // supportsSM3
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0198: Stream Management", @""),
        @"Description":NSLocalizedString(@"Resume a stream when disconnected. Results in faster reconnect and saves battery life.", @""),
        @"Color": connection.supportsSM3 ? @"Green" : @"Red"
    }];

    // supportsPing
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0199: XMPP Ping", @""),
        @"Description":NSLocalizedString(@"XMPP protocol extension for sending application-level pings over XML streams.", @""),
        @"Color": connection.supportsPing ? @"Green" : @"Red"
    }];

    // supportsRosterVersion
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0237: Roster Versioning", @""),
        @"Description":NSLocalizedString(@"Defines a proposed modification to the XMPP roster protocol that enables versioning of rosters such that the server will not send the roster to the client if the roster has not been modified.", @""),
        @"Color": connection.supportsRosterVersion ? @"Green" : @"Red"
    }];

    // usingCarbons2
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0280: Message Carbons", @""),
        @"Description":NSLocalizedString(@"Synchronize your messages on all loggedin devices.", @""),
        @"Color": connection.usingCarbons2 ? @"Green" : @"Red"
    }];

    // supportsMam2
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0313: Message Archive Management", @""),
        @"Description":NSLocalizedString(@"Access message archives on the server.", @""),
        @"Color": connection.supportsMam2 ? @"Green" : @"Red"
    }];

    // supportsClientState
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0352: Client State Indication", @""),
        @"Description":NSLocalizedString(@"Indicate when a particular device is active or inactive. Saves battery.", @""),
        @"Color": connection.supportsClientState ? @"Green" : @"Red"
    }];

    // supportsPush / pushEnabled
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0357: Push Notifications", @""),
        @"Description":NSLocalizedString(@"Receive push notifications from via Apple even when disconnected. Vastly improves reliability.", @""),
        @"Color": connection.supportsPush ? (connection.pushEnabled ? @"Green" : @"Yellow") : @"Red"
    }];

    // supportsHTTPUpload
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0363: HTTP File Upload", @""),
        @"Description":[NSString stringWithFormat:NSLocalizedString(@"Upload files to the server to share with others. (Maximum allowed size of files reported by the server: %@)", @""), [HelperTools bytesToHuman:connection.uploadSize]],
        @"Color": connection.supportsHTTPUpload ? @"Green" : @"Red"
    }];

    // supportsRosterPreApproval
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0379: Pre-Authenticated Roster Subscription", @""),
        @"Description":NSLocalizedString(@"Defines a protocol and URI scheme for pre-authenticated roster links that allow a third party to automatically obtain the user's presence subscription.", @""),
        @"Color": connection.supportsRosterPreApproval ? @"Green" : @"Red"
    }];

    // supportsPubSub
    [self.serverCaps addObject:@{
        // see MLIQProcessor.m multiple xep required for pubsub
        @"Title":NSLocalizedString(@"XEP-0163 Personal Eventing Protocol", @""),
        @"Description":NSLocalizedString(@"This specification defines semantics for using the XMPP publish-subscribe protocol to broadcast state change events associated with an instant messaging and presence account.", @""),
        @"Color": connection.supportsPubSub ? @"Green" : @"Red"
    }];
}

-(void) convertSRVRecordsToReadable
{
    BOOL foundCurrentConn = NO;

    if(self.xmppAccount.discoveredServersList == nil || self.xmppAccount.discoveredServersList.count == 0)
    {
        [self.srvRecords addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not have any SRV records in DNS.", @""), @"Color":@"Red"}];
            return;
    }
    
    for(id srvEntry in self.xmppAccount.discoveredServersList)
    {
        NSString* hostname = [srvEntry objectForKey:@"server"];
        NSNumber* port = [srvEntry objectForKey:@"port"];
        NSString* isSecure = [[srvEntry objectForKey:@"isSecure"] boolValue] ? NSLocalizedString(@"Yes", @"") : NSLocalizedString(@"No", @"");
        NSString* prio = [srvEntry objectForKey:@"priority"];

        // Check if entry is currently in use
        NSString* entryColor = @"None";
        if([self.xmppAccount.connectionProperties.server.connectServer isEqualToString:hostname] &&
           self.xmppAccount.connectionProperties.server.connectPort == port &&
           self.xmppAccount.connectionProperties.server.isDirectTLS == [[srvEntry objectForKey:@"isSecure"] boolValue])
        {
            entryColor = @"Green";
            foundCurrentConn = YES;
        }
        else if(!foundCurrentConn)
        {
            // Set the color of all connections entries that failed to red
            // discoveredServersList is sorted. Therfore all entries before foundCurrentConn == YES have failed
            entryColor = @"Red";
        }

        [self.srvRecords addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Server: %@", @""), hostname], @"Description": [NSString stringWithFormat:NSLocalizedString(@"Port: %@, Direct TLS: %@, Priority: %@", @""), port, isSecure, prio], @"Color": entryColor}];
    }
}

-(void) checkSASLMethods:(MLXMPPConnection*) connection
{
    DDLogVerbose(@"saslMethods: %@", connection.saslMethods);
    if(connection.saslMethods == nil || connection.saslMethods.count == 0)
    {
        [self.saslMethods addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not support modern SASL2 authentication.", @""), @"Color":@"Red"}];
        return;
    }
    for(NSString* method in [connection.saslMethods.allKeys sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]])
    {
        BOOL used = [connection.saslMethods[method] boolValue];
        BOOL supported = [[SCRAM supportedMechanismsIncludingChannelBinding:YES] containsObject:method] || [@[@"PLAIN"] containsObject:method];
        NSString* description = NSLocalizedString(@"Unknown authentication method", @"");
        if([method isEqualToString:@"PLAIN"])
            description = NSLocalizedString(@"Sends password in cleartext (only encrypted by TLS), not very secure", @"");
        else if([method isEqualToString:@"EXTERNAL"])
            description = NSLocalizedString(@"Uses TLS client certificates for authentication", @"");
        else if([method hasPrefix:@"SCRAM-"] && [method hasSuffix:@"-PLUS"])
            description = NSLocalizedString(@"Salted Challenge Response Authentication Mechanism using the given Hash Method additionally secured by Channel-Binding", @"");
        else if([method hasPrefix:@"SCRAM-"])
            description = NSLocalizedString(@"Salted Challenge Response Authentication Mechanism using the given Hash Method", @"");
        [self.saslMethods addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Method: %@", @""), method], @"Description":description, @"Color":(used ? @"Green" : (!supported ? @"Yellow" : @"None"))}];
    }
}

-(void) checkChannelBindingTypes:(MLXMPPConnection*) connection
{
    DDLogVerbose(@"channelBindingTypes: %@", connection.channelBindingTypes);
    if(connection.channelBindingTypes == nil || connection.channelBindingTypes.count == 0)
    {
        [self.channelBindingTypes addObject:@{@"Title": NSLocalizedString(@"None", @""), @"Description":NSLocalizedString(@"This server does not support any modern channel-binding to secure against MITM attacks on the TLS layer.", @""), @"Color":@"Red"}];
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
        [self.channelBindingTypes addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Type: %@", @""), type], @"Description":description, @"Color":(used ? @"Green" : (!supported ? @"Yellow" : @"None"))}];
    }
}

#pragma mark - Table view data source

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return ML_SERVER_DETAILS_SECTIONS_CNT;
}

-(NSInteger) tableView:(UITableView*) tableView numberOfRowsInSection:(NSInteger) section
{
    if(section == SUPPORTED_SERVER_XEPS_SECTION)
        return self.serverCaps.count;
    else if(section == SRV_RECORS_SECTION)
        return self.srvRecords.count;
    else if(section == SASL_SECTION)
        return self.saslMethods.count;
    else if(section == CB_SECTION)
        return self.channelBindingTypes.count;
    return 0;
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"serverCell" forIndexPath:indexPath];

    NSDictionary* dic;
    if(indexPath.section == SUPPORTED_SERVER_XEPS_SECTION)
        dic = [self.serverCaps objectAtIndex:indexPath.row];
    else if(indexPath.section == SRV_RECORS_SECTION)
        dic = [self.srvRecords objectAtIndex:indexPath.row];
    else if(indexPath.section == SASL_SECTION)
        dic = [self.saslMethods objectAtIndex:indexPath.row];
    else if(indexPath.section == CB_SECTION)
        dic = [self.channelBindingTypes objectAtIndex:indexPath.row];

    cell.textLabel.text = [dic objectForKey:@"Title"];
    cell.detailTextLabel.text = [dic objectForKey:@"Description"];

    // Add background color to selected cells
    if([dic objectForKey:@"Color"])
    {
        NSString* entryColor = [dic objectForKey:@"Color"];
        // Remove background color from textLabel & detailTextLabel
        cell.textLabel.backgroundColor = UIColor.clearColor;
        cell.detailTextLabel.backgroundColor = UIColor.clearColor;

        if([entryColor isEqualToString:@"Green"])
            [cell setBackgroundColor:[UIColor colorWithRed:0 green:0.8 blue:0 alpha:0.2]];
        else if([entryColor isEqualToString:@"Red"])
            [cell setBackgroundColor:[UIColor colorWithRed:0.8 green:0 blue:0 alpha:0.2]];
        else if([entryColor isEqualToString:@"Yellow"])
            [cell setBackgroundColor:[UIColor colorWithRed:1.0 green:1.0 blue:0 alpha:0.2]];
        else
            [cell setBackgroundColor:nil];
    }
    return cell;
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    if(section == SUPPORTED_SERVER_XEPS_SECTION)
        return NSLocalizedString(@"These are the modern XMPP capabilities Monal detected on your server after you have logged in.", @"");
    else if(section == SRV_RECORS_SECTION)
        return NSLocalizedString(@"These are SRV resource records found for your domain.", @"");
    else if(section == SASL_SECTION)
        return NSLocalizedString(@"These are the SASL2 methods your server supports.", @"");
    else if(section == CB_SECTION)
        return NSLocalizedString(@"These are the channel-binding types your server supports to detect attacks on the TLS layer.", @"");
    return @"";
}

@end
