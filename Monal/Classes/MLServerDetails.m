//
//  MLServerDetails.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/21/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLServerDetails.h"

@interface MLServerDetails ()

@property (nonatomic, strong) NSMutableArray *serverCaps;

@end

@implementation MLServerDetails

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.serverCaps =[[NSMutableArray alloc] init];
    
    self.navigationItem.title= self.xmppAccount.server;
    
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
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.serverCaps.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"serverCell" forIndexPath:indexPath];
    
    NSDictionary *dic = [self.serverCaps objectAtIndex:indexPath.row];
    
    cell.textLabel.text= [dic objectForKey:@"Title"];
    cell.detailTextLabel.text= [dic objectForKey:@"Description"];
    
    return cell;
}


-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"These are the modern XMPP capabilities Monal detected on your server after you've logged in. ";
}



@end
