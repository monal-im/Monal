//
//  MLServerDetailsVC.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 12/21/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLServerDetailsVC.h"

#import "MLXMPPManager.h"
#import "MLContactsCell.h"

@interface MLServerDetailsVC ()


@property (nonatomic, strong) NSMutableArray *serverCaps;


@end

@implementation MLServerDetailsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear
{
    [super viewWillAppear];
    
    self.serverCaps =[[NSMutableArray alloc] init];
    if(self.xmppAccount.server) {
        self.view.window.title= self.xmppAccount.server;
    }
    
    if(self.xmppAccount.supportsSM3)
    {
        [self.serverCaps addObject:@{@"Title":@"XEP-0198: Stream Management", @"Description":@"Resume a stream when disconnected. Results in faster reconnect and saves battery life."}];
    }
    
    if(self.xmppAccount.supportsPush)
    {
        [self.serverCaps addObject:@{@"Title":@"XEP-0357: Push Notifications", @"Description":@"Receive push notifications from via Apple even when disconnected. Vastly improves reliability. "}];
    }
    
    if(self.xmppAccount.usingCarbons2)
    {
        [self.serverCaps addObject:@{@"Title":@"XEP-0280: Message Carbons", @"Description":@"Synchronize your messages on all loggedin devices."}];
    }
    
    if(self.xmppAccount.supportsMam0)
    {
        [self.serverCaps addObject:@{@"Title":@"XEP-0313: Message Archive Management", @"Description":@"Access message archives on the server."}];
    }
    
    if(self.xmppAccount.supportsHTTPUpload)
    {
        [self.serverCaps addObject:@{@"Title":@"XEP-0363: HTTP File Upload", @"Description":@"Upload files to the server to share with others."}];
    }
    
    if(self.xmppAccount.supportsClientState)
    {
        [self.serverCaps addObject:@{@"Title":@"XEP-0352: Client State Indication", @"Description":@"Indicate when a particular device is active or inactive. Saves battery. "}];
    }
    
    [self.detailsTable reloadData];
}


#pragma mark - table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.serverCaps.count;
}
   

#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    MLContactsCell *cell = [tableView makeViewWithIdentifier:@"serverCell" owner:self];
    cell.name.backgroundColor =[NSColor clearColor];
    cell.status.backgroundColor= [NSColor clearColor];
    
    NSDictionary *dic = [self.serverCaps objectAtIndex:row];
    
    cell.name.stringValue= [dic objectForKey:@"Title"];
    cell.status.stringValue= [dic objectForKey:@"Description"];
    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 60.0f;
}


@end
