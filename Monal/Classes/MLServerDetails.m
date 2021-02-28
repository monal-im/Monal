//
//  MLServerDetails.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/21/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLServerDetails.h"
#import "UIColor+Theme.h"

@interface MLServerDetails ()

@property (nonatomic, strong) NSMutableArray *serverCaps;
@property (nonatomic, strong) NSMutableArray *srvRecords;

@end

@implementation MLServerDetails

enum MLServerDetailsSections {
    SUPPORTED_SERVER_XEPS_SECTION,
    SRV_RECORS_SECTION,
    ML_SERVER_DETAILS_SECTIONS_CNT
};

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void) checkServerCaps:(MLXMPPConnection*) connection
{
    // supportsBlocking
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0191: Blocking Command", @""),
        @"Description":NSLocalizedString(@"TODO", @""),
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
        @"Description":NSLocalizedString(@"TODO", @""),
        @"Color": connection.supportsPing ? @"Green" : @"Red"
    }];

    // supportsRosterVersion
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0237: Roster Versioning", @""),
        @"Description":NSLocalizedString(@"TODO", @""),
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
        @"Description":NSLocalizedString(@"Upload files to the server to share with others.", @""),
        @"Color": connection.supportsHTTPUpload ? @"Green" : @"Red"
    }];

    // supportsRosterPreApproval
    [self.serverCaps addObject:@{
        @"Title":NSLocalizedString(@"XEP-0379: Pre-Authenticated Roster Subscription", @""),
        @"Description":NSLocalizedString(@"TODO", @""),
        @"Color": connection.supportsRosterPreApproval ? @"Green" : @"Red"
    }];

    // supportsPubSub
    [self.serverCaps addObject:@{
        // see MLIQProcessor.m multiple xep required for pubsub
        @"Title":NSLocalizedString(@"PubSub Support", @""),
        @"Description":NSLocalizedString(@"TODO", @""),
        @"Color": connection.supportsPubSub ? @"Green" : @"Red"
    }];
}

-(void) convertSRVRecordsToReadable {
    BOOL foundCurrentConn = NO;

    for(id srvEntry in self.xmppAccount.discoveredServersList) {
        NSString* hostname = [srvEntry objectForKey:@"server"];
        NSNumber* port = [srvEntry objectForKey:@"port"];
        NSString* isSecure = [[srvEntry objectForKey:@"isSecure"] boolValue] ? NSLocalizedString(@"Yes", @"") : NSLocalizedString(@"No", @"");
        NSString* prio = [srvEntry objectForKey:@"priority"];

        // Check if entry is currently in use
        NSString* entryColor = @"None";
        if([self.xmppAccount.connectionProperties.server.connectServer isEqualToString:hostname] &&
           self.xmppAccount.connectionProperties.server.connectPort == port &&
           self.xmppAccount.connectionProperties.server.isDirectTLS == [isSecure boolValue])
        {
            entryColor = @"Green";
            foundCurrentConn = YES;
        } else if(!foundCurrentConn) {
            // Set the color of all connections entries that failed to red
            // discoveredServersList is sorted. Therfore all entries before foundCurrentConn == YES have failed
            entryColor = @"Red";
        }

        [self.srvRecords addObject:@{@"Title": [NSString stringWithFormat:NSLocalizedString(@"Server: %@", @""), hostname], @"Description": [NSString stringWithFormat:NSLocalizedString(@"Port: %@, Is Secure: %@, Prio: %@", @""), port, isSecure, prio], @"Color": entryColor}];
    }
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.serverCaps = [[NSMutableArray alloc] init];
    self.srvRecords = [[NSMutableArray alloc] init];
    
    self.navigationItem.title = self.xmppAccount.connectionProperties.identity.domain;

    [self checkServerCaps:self.xmppAccount.connectionProperties];
    [self convertSRVRecordsToReadable];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return ML_SERVER_DETAILS_SECTIONS_CNT;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section == SUPPORTED_SERVER_XEPS_SECTION) {
        return self.serverCaps.count;
    } else if(section == SRV_RECORS_SECTION) {
        return self.srvRecords.count;
    }
    return 0;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"serverCell" forIndexPath:indexPath];

    NSDictionary* dic;
    if(indexPath.section == SUPPORTED_SERVER_XEPS_SECTION) {
        dic = [self.serverCaps objectAtIndex:indexPath.row];
    } else if(indexPath.section == SRV_RECORS_SECTION) {
        dic = [self.srvRecords objectAtIndex:indexPath.row];
    }

    cell.textLabel.text = [dic objectForKey:@"Title"];
    cell.detailTextLabel.text = [dic objectForKey:@"Description"];

    // Add background color to selected cells
    if([dic objectForKey:@"Color"]) {
        NSString* entryColor = [dic objectForKey:@"Color"];
        // Remove background color from textLabel & detailTextLabel
        cell.textLabel.backgroundColor = UIColor.clearColor;
        cell.detailTextLabel.backgroundColor = UIColor.clearColor;

        if([entryColor isEqualToString:@"Green"])
        {
            [cell setBackgroundColor:[UIColor colorWithRed:0 green:0.8 blue:0 alpha:0.2]];
        }
        else if([entryColor isEqualToString:@"Red"])
        {
            [cell setBackgroundColor:[UIColor colorWithRed:0.8 green:0 blue:0 alpha:0.2]];
        }
        else if([entryColor isEqualToString:@"Yellow"])
        {
            [cell setBackgroundColor:[UIColor colorWithRed:1.0 green:1.0 blue:0 alpha:0.2]];
        }
    }
    return cell;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if(section == SUPPORTED_SERVER_XEPS_SECTION) {
        return NSLocalizedString(@"These are the modern XMPP capabilities Monal detected on your server after you have logged in.", @"");
    } else if(section == SRV_RECORS_SECTION) {
        return NSLocalizedString(@"These are SRV resource records found for your domain", @"");
    }
    return @"";
}

@end
