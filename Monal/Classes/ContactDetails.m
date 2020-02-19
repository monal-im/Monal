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
@property (nonatomic, assign) NSInteger groupMemberCount;
@property (nonatomic, strong) UIImage *leftImage;
@property (nonatomic, strong) UIImage *rightImage;

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
    if(!self.contact) return;
    
    [[MLXMPPManager sharedInstance] getVCard:self.contact];
    self.tableView.rowHeight= UITableViewAutomaticDimension;
    
    self.navigationItem.title=self.contact.contactDisplayName;
    
    if(self.contact.isGroup) {
       NSArray *members= [[DataLayer sharedInstance] resourcesForContact:self.contact.contactJid];
        self.groupMemberCount=members.count;
        self.navigationItem.title =@"Group Chat";
        
    }
    
    self.accountNo=self.contact.accountId;
    [[DataLayer sharedInstance] addContact:self.contact.contactJid forAccount:self.accountNo  fullname:@"" nickname:@"" andMucNick:nil  withCompletion:^(BOOL success) {
    }];
    
    
#ifndef DISABLE_OMEMO
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    [self.xmppAccount queryOMEMODevicesFrom:self.contact.contactJid];
#endif
    
    [self refreshLock];
    [self refreshMute];
    
}

-(IBAction) callContact:(id)sender
{
    [self performSegueWithIdentifier:@"showCall" sender:self];
    [[MLXMPPManager sharedInstance] callContact:self.contact];
}


-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showCall"])
    {
        CallViewController *callScreen = segue.destinationViewController;
        callScreen.contact=self.contact;
    }
    else if([segue.identifier isEqualToString:@"showResources"])
    {
        MLResourcesTableViewController *resourcesVC = segue.destinationViewController;
        resourcesVC.contact=self.contact;
    }
    else if([segue.identifier isEqualToString:@"showKeys"])
    {
        MLKeysTableViewController *keysVC = segue.destinationViewController;
        keysVC.contact=self.contact;
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
            if(self.contact.isGroup) {
               detailCell.jid.text=[NSString stringWithFormat:@"%@ (%lu)", self.contact.contactJid, self.groupMemberCount];
                //for how hide things that arent relevant
                detailCell.lockButton.hidden=YES;
                detailCell.phoneButton.hidden=YES;
            } else {
                detailCell.jid.text=self.contact.contactJid;
            }
            
            [[MLImageManager sharedInstance] getIconForContact:self.contact.contactJid andAccount:self.contact.accountId withCompletion:^(UIImage *image) {
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
                if(self.contact.isGroup) {
                    cell.textInput.enabled=NO;
                    cell.textInput.text=self.contact.accountNickInGroup;
                } else  {
                    NSString* nickName=self.contact.nickName;
                    if([[nickName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
                        cell.textInput.text=nickName;
                    } else {
                        cell.textInput.text=self.contact.fullName;
                    }
                    if([cell.textInput.text isEqualToString:@"(null)"])  cell.textInput.text=@"";
                    cell.textInput.placeholder=@"Set a nickname";
                    cell.textInput.delegate=self;
                }
                thecell=cell;
            }
            else if(indexPath.row==1) {
                MLDetailsTableViewCell *cell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"MessageCell"];
                if(self.contact.isGroup) {
                    cell.cellDetails.text=self.contact.groupSubject;
                } else  {
                    cell.cellDetails.text=self.contact.statusMessage;
                    if([cell.cellDetails.text isEqualToString:@"(null)"])  cell.cellDetails.text=@"";
                }
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
            if(indexPath.row==0) {
               thecell.textLabel.text=@"Encryption Keys";
           } else
            if(indexPath.row==1) {
                if(self.contact.isGroup) {
                    thecell.textLabel.text=@"Participants";
                } else {
                    thecell.textLabel.text=@"Resources";
                }
            }
            else if(indexPath.row==2) {
                if(self.contact.isGroup) {
                     thecell.textLabel.text=@"Leave Conversation";
                } else  {
                    thecell.textLabel.text=@"Remove Contact";
                }
            }
            thecell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
    }
    return thecell;
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    if(section==0)  return 1;
    if(section==1)  return 3;
    if(section==2)  return 3;
    
    return 0; //some default shouldnt reach this
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
            case 2:  {
                [self removeContact];
                break;
            }
        }
    }
}

-(void) removeContact {
    NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", nil),self.contact.fullName ];
    NSString* detailString =@"They will no longer see when you are online. They may not be able to access your encryption keys.";
       
    BOOL isMUC=self.contact.isGroup;
    if(isMUC)
    {
        messageString =@"Leave this converstion?";
        detailString=nil;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        if(isMUC) {
            [[MLXMPPManager sharedInstance] leaveRoom:self.contact.contactJid withNick:self.contact.accountNickInGroup forAccountId:self.contact.accountId ];
        }
        else  {
            [[MLXMPPManager sharedInstance] removeContact:self.contact];
        }
   
    }]];
    
    alert.popoverPresentationController.sourceView=self.tableView;
    
    [self presentViewController:alert animated:YES completion:nil];
}

-(void) showChatImges{
    NSMutableArray *images = [[DataLayer sharedInstance] allAttachmentsFromContact:self.contact.contactJid forAccount:self.accountNo];
    
    if(!self.photos)
    {   self.photos =[[NSMutableArray alloc] init];
        for (NSDictionary *imagePath  in images) {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            NSString *readPath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
            readPath = [readPath stringByAppendingPathComponent:[imagePath objectForKey:@"path"]];
            UIImage *image=[UIImage imageWithContentsOfFile:readPath];
            IDMPhoto* photo=[IDMPhoto photoWithImage:image];
            [self.photos addObject:photo];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.photos.count>0) {
            IDMPhotoBrowser *browser = [[IDMPhotoBrowser alloc] initWithPhotos:self.photos];
            browser.delegate=self;
            browser.autoHideInterface=NO;
            browser.displayArrowButton = YES;
            browser.displayCounterLabel = YES;
            browser.displayActionButton=YES;
            browser.displayToolbar=YES;
            
            self.leftImage=[UIImage imageNamed:@"IDMPhotoBrowser_arrowLeft"];
            self.rightImage=[UIImage imageNamed:@"IDMPhotoBrowser_arrowRight"];
            browser.leftArrowImage =self.leftImage;
            browser.rightArrowImage =self.rightImage;
            UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(closePhotos)];
                          browser.navigationItem.rightBarButtonItem=close;
            
            UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];
            
            
            [self presentViewController:nav animated:YES completion:nil];
        } else  {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nothing to see" message:@"You have not received any images in this conversation." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        
    });
    
}

-(void) closePhotos {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)close:(id)sender
{
    [self textFieldShouldEndEditing:self.currentTextField];
    if(self.completion) self.completion();
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}


-(IBAction) muteContact:(id)sender
{
    if(!self.isMuted) {
        [[DataLayer sharedInstance] muteJid:self.contact.contactJid];
    } else {
        [[DataLayer sharedInstance] unMuteJid:self.contact.contactJid];
    }
    [self refreshMute];
}

-(void) refreshMute
{
    [[DataLayer sharedInstance] isMutedJid:self.contact.contactJid withCompletion:^(BOOL muted) {
        self.isMuted= muted;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
        });
        
    }];
}

-(IBAction) toggleEncryption:(id)sender
{
    NSArray *devices= [self.xmppAccount.monalSignalStore knownDevicesForAddressName:self.contact.contactJid];
    if(devices.count>0) {
        if(self.isEncrypted) {
            [[DataLayer sharedInstance] disableEncryptForJid:self.contact.contactJid andAccountNo:self.accountNo];
            [self refreshLock];
        } else {
            [[DataLayer sharedInstance] encryptForJid:self.contact.contactJid andAccountNo:self.accountNo];
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
    self.isEncrypted= [[DataLayer sharedInstance] shouldEncryptForJid:self.contact.contactJid andAccountNo:self.accountNo];
    
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
    [[DataLayer sharedInstance] setNickName:textField.text forContact:self.contact.contactJid andAccount:self.accountNo];
    
    if(textField.text.length>0)
        self.navigationItem.title = textField.text;
    else
        self.navigationItem.title=self.contact.fullName;
    
    self.contact.nickName=textField.text;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:@{@"contact":self.contact}];
    
    return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    self.currentTextField=textField;
    return YES;
}

#pragma mark - photo browser delegate
- (NSUInteger)numberOfPhotosInPhotoBrowser:(IDMPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <IDMPhoto>)photoBrowser:(IDMPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

@end
