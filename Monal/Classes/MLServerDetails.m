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
    
    self.navigationItem.title= self.xmppAccount.connectionProperties.identity.domain;
    
    if(self.xmppAccount.connectionProperties.supportsSM3)
    {
        [self.serverCaps addObject:@{NSLocalizedString(@"Title",@ ""):NSLocalizedString(@"XEP-0198: Stream Management",@ ""), NSLocalizedString(@"Description",@ ""):NSLocalizedString(@"Resume a stream when disconnected. Results in faster reconnect and saves battery life.",@ "")}];
    }
    
    if(self.xmppAccount.connectionProperties.supportsPush)
    {
        [self.serverCaps addObject:@{NSLocalizedString(@"Title",@ ""):NSLocalizedString(@"XEP-0357: Push Notifications",@ ""), NSLocalizedString(@"Description",@ ""):NSLocalizedString(@"Receive push notifications from via Apple even when disconnected. Vastly improves reliability.",@ "")}];
    }
    
    if(self.xmppAccount.connectionProperties.usingCarbons2)
    {
        [self.serverCaps addObject:@{NSLocalizedString(@"Title",@ ""):NSLocalizedString(@"XEP-0280: Message Carbons",@ ""), NSLocalizedString(@"Description",@ ""):NSLocalizedString(@"Synchronize your messages on all loggedin devices.",@ "")}];
    }
    
    if(self.xmppAccount.connectionProperties.supportsMam2)
    {
           [self.serverCaps addObject:@{NSLocalizedString(@"Title",@ ""):NSLocalizedString(@"XEP-0313: Message Archive Management",@ ""), NSLocalizedString(@"Description",@ ""):NSLocalizedString(@"Access message archives on the server.",@ "")}];
    }
    
    if(self.xmppAccount.connectionProperties.supportsHTTPUpload)
    {
           [self.serverCaps addObject:@{NSLocalizedString(@"Title",@ ""):NSLocalizedString(@"XEP-0363: HTTP File Upload",@ ""), NSLocalizedString(@"Description",@ ""):NSLocalizedString(@"Upload files to the server to share with others.",@ "")}];
    }
    
    if(self.xmppAccount.connectionProperties.supportsClientState)
    {
           [self.serverCaps addObject:@{NSLocalizedString(@"Title",@ ""):NSLocalizedString(@"XEP-0352: Client State Indication",@ ""), NSLocalizedString(@"Description",@ ""):NSLocalizedString(@"Indicate when a particular device is active or inactive. Saves battery.",@ "")}];
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
    
    cell.textLabel.text= [dic objectForKey:NSLocalizedString(@"Title",@ "")];
    cell.detailTextLabel.text= [dic objectForKey:NSLocalizedString(@"Description",@ "")];
    
    return cell;
}


-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"These are the modern XMPP capabilities Monal detected on your server after you have logged in.",@ "");
}



@end
