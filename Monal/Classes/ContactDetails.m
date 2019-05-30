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
#import "MLTextInputCell.h"


@interface ContactDetails()
@property (nonatomic, assign) BOOL isMuted;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isEncrypted;

@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) xmpp* xmppAccount;
@property (nonatomic, weak) UITextField* currentTextField;
@property (nonatomic, strong) NSMutableArray * photos;

@end

@implementation ContactDetails

#pragma mark view lifecycle
-(void) viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"TextCell"];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[MLXMPPManager sharedInstance] getVCard:_contact];
    self.tableView.rowHeight= UITableViewAutomaticDimension;
 
    NSString* nickName=[self.contact  objectForKey:@"nick_name"];
    if([[nickName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
        self.navigationItem.title=nickName;
    } else  {
        NSString* fullName=[self.contact  objectForKey:@"full_name"];
        if([[fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
            self.navigationItem.title=fullName;
        }
        else {
             self.navigationItem.title=[self.contact  objectForKey:@"buddy_name"];
        }
        
    }
  
    self.accountNo=[NSString stringWithFormat:@"%@", [self.contact objectForKey:@"account_id"]];
    //if not in buddylist, add.
    [[DataLayer sharedInstance] addContact:[self.contact objectForKey:@"buddy_name"]  forAccount:self.accountNo  fullname:@"" nickname:@"" withCompletion:^(BOOL success) {
    }];
    
    
#ifndef DISABLE_OMEMO
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    [self.xmppAccount queryOMEMODevicesFrom:[self.contact objectForKey:@"buddy_name"]];
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


#pragma mark - tableview

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
           if(indexPath.row==0)
           {
               MLTextInputCell *cell=  (MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                   NSString* nickName=[self.contact  objectForKey:@"nick_name"];
               if([[nickName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
                   cell.textInput.text=[_contact objectForKey:@"nick_name"];
               } else {
               cell.textInput.text=[_contact objectForKey:@"full_name"];
               }
               if([cell.textInput.text isEqualToString:@"(null)"])  cell.textInput.text=@"";
               cell.textInput.placeholder=@"Set a nickname";
               cell.textInput.delegate=self;
               thecell=cell;
           }
           else if(indexPath.row==1) {
               MLDetailsTableViewCell *cell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"MessageCell"];
               cell.cellDetails.text=[_contact objectForKey:@"status"];
               if([cell.cellDetails.text isEqualToString:@"(null)"])  cell.cellDetails.text=@"";
               thecell=cell;
           }
           else {
               UITableViewCell *cell=  (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"TableCell"];
               cell.textLabel.text = @"View Images Received";
               thecell=cell;
           }
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
    if(section==0)   return 1;
    if(section==1)  return 3;
    
    return 2;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=nil; 
    if(section==1)
        toreturn= @"About";
    
    if(section==2)
        toreturn= @"Connection Details";
    
    return toreturn;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if(indexPath.section==0) return;
    
    if(indexPath.section==1){
        if(indexPath.row<2) return;
        [self showChatImges];
        
    }
    else  {
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
}

-(void) showChatImges{
    NSMutableArray *images = [[DataLayer sharedInstance] allAttachmentsFromContact:[self.contact objectForKey:@"buddy_name"] forAccount:self.accountNo];
    
    if(!self.photos)
    {   self.photos =[[NSMutableArray alloc] init];
        for (NSDictionary *imagePath  in images) {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            NSString *readPath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
            readPath = [readPath stringByAppendingPathComponent:[imagePath objectForKey:@"path"]];
            UIImage *image=[UIImage imageWithContentsOfFile:readPath];
            MWPhoto* photo=[MWPhoto photoWithImage:image];
            [self.photos addObject:photo];
        }
    }
    
dispatch_async(dispatch_get_main_queue(), ^{
    
    MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    
    browser.displayActionButton = YES; // Show action button to allow sharing, copying, etc (defaults to YES)
    browser.displayNavArrows = NO; // Whether to display left and right nav arrows on toolbar (defaults to NO)
    browser.displaySelectionButtons = NO; // Whether selection buttons are shown on each image (defaults to NO)
    browser.zoomPhotosToFill = YES; // Images that almost fill the screen will be initially zoomed to fill (defaults to YES)
    browser.alwaysShowControls = YES; // Allows to control whether the bars and controls are always visible or whether they fade away to show the photo full (defaults to NO)
    browser.enableGrid = YES; // Whether to allow the viewing of all the photo thumbnails on a grid (defaults to YES)
    browser.startOnGrid = YES; // Whether to start on the grid of thumbnails instead of the first photo (defaults to NO)
    
    UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];
    
    
    [self presentViewController:nav animated:YES completion:nil];
    
});
    
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
      NSArray *devices= [self.xmppAccount.monalSignalStore knownDevicesForAddressName:[self.contact objectForKey:@"buddy_name"]];
    if(devices.count>0) {
        if(self.isEncrypted) {
            [[DataLayer sharedInstance] disableEncryptForJid:[self.contact objectForKey:@"buddy_name"] andAccountNo:self.accountNo];
             [self refreshLock];
        } else {
            [[DataLayer sharedInstance] encryptForJid:[self.contact objectForKey:@"buddy_name"] andAccountNo:self.accountNo];
            [self refreshLock];
        }
       
    } else  {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Encryption Not Supported" message:@"This contact does not appear to have any devices that support encryption." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
}

-(void) refreshLock
{
    self.isEncrypted= [[DataLayer sharedInstance] shouldEncryptForJid:[self.contact objectForKey:@"buddy_name"] andAccountNo:self.accountNo];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    });
}


#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}


-(BOOL) textFieldShouldEndEditing:(UITextField *)textField {
    [[DataLayer sharedInstance] setNickName:textField.text forContact:[self.contact objectForKey:@"buddy_name"] andAccount:self.accountNo];
  
    if(textField.text.length>0)
        self.navigationItem.title = textField.text;
    else
        self.navigationItem.title=[self.contact objectForKey:@"full_name"];
    
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:self.contact];
    
    return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    self.currentTextField=textField;
    return YES;
}

#pragma mark - photo browser delegate
- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

@end
