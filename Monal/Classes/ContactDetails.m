//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "ContactDetails.h"
#import "MLImageManager.h"
#import "MLConstants.h"
#import "CallViewController.h"
#import "MLXMPPManager.h"
#import "MLDetailsTableViewCell.h"
#import "MLContactDetailHeader.h"
#import "MLKeysTableViewController.h"
#import "MLResourcesTableViewController.h"

@interface ContactDetails()
@property (nonatomic, assign) BOOL isMuted;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isEncrypted;

@property (nonatomic, strong) NSString *accountNo;

@end

@implementation ContactDetails

#pragma mark view lifecycle
-(void) viewDidLoad
{
    [super viewDidLoad];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[MLXMPPManager sharedInstance] getVCard:_contact];
    self.tableView.rowHeight= UITableViewAutomaticDimension;
    self.navigationItem.title=[self.contact objectForKey:@"full_name"];
    
#ifndef DISABLE_OMEMO
    self.accountNo=[NSString stringWithFormat:@"%@", [self.contact objectForKey:@"account_id"]];
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    [xmppAccount queryOMEMODevicesFrom:[self.contact objectForKey:@"buddy_name"]];
#endif
    
    [self refreshLock];
    [self refreshMute];
    
}

-(IBAction) callContact:(id)sender
{
    [self performSegueWithIdentifier:@"showCall" sender:self];
    [[MLXMPPManager sharedInstance] callContact:_contact];
}


-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showCall"])
    {
        CallViewController *callScreen = segue.destinationViewController;
        callScreen.contact=_contact; 
    }
     else if([segue.identifier isEqualToString:@"showResources"])
    {
        MLResourcesTableViewController *resourcesVC = segue.destinationViewController;
        resourcesVC.contact=_contact;
    }
    else if([segue.identifier isEqualToString:@"showKeys"])
    {
        MLKeysTableViewController *keysVC = segue.destinationViewController;
        keysVC.contact=_contact;
    }
}


#pragma mark -- tableview

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if(section==0) return 2; // table view does not like <=1

    return 30.0;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* thecell;
  
   switch(indexPath.section) {
        case 0: {
            MLContactDetailHeader *detailCell=  (MLContactDetailHeader *)[tableView dequeueReusableCellWithIdentifier:@"headerCell"];

            detailCell.jid.text=[self.contact objectForKey:@"buddy_name"];
//            thecell.fullName.text=[self.contact objectForKey:@"full_name"];
//            thecell.buddyStatus.text=[self.contact objectForKey:@"state"];

//            if([thecell.buddyStatus.text isEqualToString:@"(null)"])  thecell.buddyStatus.text=@"";
//            if([thecell.fullName.text isEqualToString:@"(null)"])  thecell.fullName.text=@"";

            NSString* accountNo=[NSString stringWithFormat:@"%@", [self.contact objectForKey:@"account_id"]];
            [[MLImageManager sharedInstance] getIconForContact:[self.contact objectForKey:@"buddy_name"] andAccount:accountNo withCompletion:^(UIImage *image) {
                detailCell.buddyIconView.image=image;
             //   detailCell.background.image=image;
            }];
            
            detailCell.background.image= [UIImage imageNamed:@"Tie_My_Boat_by_Ray_García"];

            if(self.isMuted) {
                [detailCell.muteButton setImage:[UIImage imageNamed:@"847-moon-selected"] forState:UIControlStateNormal];
            } else  {
                [detailCell.muteButton setImage:[UIImage imageNamed:@"847-moon"] forState:UIControlStateNormal];
            }
            
            if(self.isEncrypted) {
                [detailCell.lockButton setImage:[UIImage imageNamed:@"744-locked-selected"] forState:UIControlStateNormal];
            } else  {
                [detailCell.lockButton setImage:[UIImage imageNamed:@"745-unlocked"] forState:UIControlStateNormal];
            }
            
            thecell=detailCell;
            break;
        }
        case 1: {
            MLDetailsTableViewCell *cell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"MessageCell"];
            cell.cellDetails.text=[_contact objectForKey:@"status"];
            if([cell.cellDetails.text isEqualToString:@"(null)"])  cell.cellDetails.text=@"";
            thecell=cell;
            break;
        }
        case 2: {
            thecell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Sub"];
            if(indexPath.row==1) {
                thecell.textLabel.text=@"Resources"; //if muc change to participants
            } else  {
                thecell.textLabel.text=@"Encryption Keys"; //if muc change to participants
            }
            thecell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
   }
    return thecell;
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    if(section==2) return 2;
    else  return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    
	return 3;
	
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=nil; 
    if(section==1)
        toreturn= @"Status Message";
    
    if(section==2)
        toreturn= @"Connection Details";
    
    return toreturn;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if(indexPath.section!=2) return;
    
    switch(indexPath.row)
    {
        case 0:  {
            [self performSegueWithIdentifier:@"showKeys" sender:self];
            break;
        }
        case 1:  {
            [self performSegueWithIdentifier:@"showResources" sender:self];
            break;
        }
    }
    
}


-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}


-(IBAction) muteContact:(id)sender
{
    if(!self.isMuted) {
        [[DataLayer sharedInstance] muteJid:[self.contact objectForKey:@"buddy_name"]];
    } else {
        [[DataLayer sharedInstance] unMuteJid:[self.contact objectForKey:@"buddy_name"]];
    }
    [self refreshMute];
}

-(void) refreshMute
{
    [[DataLayer sharedInstance] isMutedJid:[self.contact objectForKey:@"buddy_name"] withCompletion:^(BOOL muted) {
        self.isMuted= muted;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
        });
        
    }];
}

-(IBAction) toggleEncryption:(id)sender
{
    if(self.isEncrypted) {
        [[DataLayer sharedInstance] disableEncryptForJid:[self.contact objectForKey:@"buddy_name"] andAccountNo:self.accountNo];
    } else {
        [[DataLayer sharedInstance] encryptForJid:[self.contact objectForKey:@"buddy_name"] andAccountNo:self.accountNo];
    }
    [self refreshLock];
}

-(void) refreshLock
{
    self.isEncrypted= [[DataLayer sharedInstance] shouldEncryptForJid:[self.contact objectForKey:@"buddy_name"] andAccountNo:self.accountNo];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    });
}
@end
