//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "ContactDetails.h"
#import "MBProgressHUD.h"
#import "MLImageManager.h"
#import "MLConstants.h"
#import "CallViewController.h"
#import "MLXMPPManager.h"
#import "MLDetailsTableViewCell.h"
#import "MLContactDetailHeader.h"
#import "MLKeysTableViewController.h"
#import "MLResourcesTableViewController.h"
#import "MLTextInputCell.h"
#import "HelperTools.h"
#import "MLChatViewHelper.h"
#import "MLOMEMO.h"


@interface ContactDetails()
@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) BOOL isMuted;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isEncrypted;
@property (nonatomic, assign) BOOL isSubscribed;
@property (nonatomic, strong) NSString *subMessage;

@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) xmpp* xmppAccount;
@property (nonatomic, weak) UITextField* currentTextField;
@property (nonatomic, strong) NSMutableArray * photos;
@property (nonatomic, assign) NSInteger groupMemberCount;
@property (nonatomic, strong) UIImage *leftImage;
@property (nonatomic, strong) UIImage *rightImage;
@property (nonatomic, strong) NSMutableDictionary *versionInfoDic;
@property (nonatomic, strong) MBProgressHUD* saveHUD;
@end

@class HelperTools;

@implementation ContactDetails

#pragma mark view lifecycle
-(void) viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"TextCell"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if(!self.contact) return;
    
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    
    self.navigationItem.title = self.contact.contactDisplayName;
    
    if(self.contact.isGroup) {
       NSArray* members = [[DataLayer sharedInstance] resourcesForContact:self.contact.contactJid];
        self.groupMemberCount = members.count;
        self.navigationItem.title = NSLocalizedString(@"Group Chat",@"");
    }
    
    self.accountNo = self.contact.accountId;
    
    self.isEncrypted = [[DataLayer sharedInstance] shouldEncryptForJid:self.contact.contactJid andAccountNo:self.accountNo];
    self.isPinned = [[DataLayer sharedInstance] isPinnedChat:self.accountNo andBuddyJid:self.contact.contactJid];
    
    NSDictionary* newSub = [[DataLayer sharedInstance] getSubscriptionForContact:self.contact.contactJid andAccount:self.contact.accountId];
    self.contact.ask = [newSub objectForKey:@"ask"];
    self.contact.subscription = [newSub objectForKey:@"subscription"];
    
    if(!self.contact.subscription || ![self.contact.subscription isEqualToString:kSubBoth]) {
        self.isSubscribed = NO;
       
        if([self.contact.subscription isEqualToString:kSubNone]){
            self.subMessage=NSLocalizedString(@"Neither can see keys.",@"");
        }
        
        else  if([self.contact.subscription isEqualToString:kSubTo]){
             self.subMessage=NSLocalizedString(@"You can see their keys. They can't see yours",@"");
        }
        
        else if([self.contact.subscription isEqualToString:kSubFrom]){
             self.subMessage=NSLocalizedString(@"They can see your keys. You can't see theirs",@"");
        } else {
              self.subMessage=NSLocalizedString(@"Unknown Subcription",@"");
        }
        
        if([self.contact.ask isEqualToString:kAskSubscribe])
        {
            self.subMessage =[NSString  stringWithFormat:NSLocalizedString(@"%@ (Pending Approval)",@""), self.subMessage];
        }
        
    } else  {
        self.isSubscribed=YES;
    }
    
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    
    [self refreshLock];
    [self refreshMute];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillAppear:animated];
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
        CallViewController* callScreen = segue.destinationViewController;
        callScreen.contact=self.contact;
    }
    else if([segue.identifier isEqualToString:@"showResources"])
    {
        MLResourcesTableViewController* resourcesVC = segue.destinationViewController;
        resourcesVC.contact=self.contact;
    }
    else if([segue.identifier isEqualToString:@"showKeys"])
    {
        MLKeysTableViewController* keysVC = segue.destinationViewController;
        keysVC.contact=self.contact;
    }
}

// Close the current view
-(void) escapePressed:(UIKeyCommand*)keyCommand
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

// List of custom hardware key commands
- (NSArray<UIKeyCommand *> *)keyCommands {
    return @[
            // esc
            [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(escapePressed:)],
    ];
}


#pragma mark - tableview

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if(section == 0) return 2; // table view does not like <=1
    
    return 30.0;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* thecell;
    
    switch(indexPath.section) {
        case 0: {
            MLContactDetailHeader* detailCell = (MLContactDetailHeader *)[tableView dequeueReusableCellWithIdentifier:@"headerCell"];

            // Set jid field
            if(self.contact.isGroup) {
               detailCell.jid.text=[NSString stringWithFormat:@"%@ (%lu)", self.contact.contactJid, self.groupMemberCount];
                //hide things that aren't relevant
                detailCell.phoneButton.hidden = YES;
                detailCell.isContact.hidden = YES;
            } else {
                detailCell.jid.text = self.contact.contactJid;
                detailCell.isContact.hidden = self.isSubscribed;
                detailCell.isContact.text = self.subMessage;
            }
            
            // Set human readable lastInteraction field
            NSDate* lastInteractionDate = [[DataLayer sharedInstance] lastInteractionOfJid:self.contact.contactJid forAccountNo:self.contact.accountId];
            NSString* lastInteractionStr;
            if(lastInteractionDate.timeIntervalSince1970 > 0) {
                lastInteractionStr = [NSDateFormatter localizedStringFromDate:lastInteractionDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
            } else {
                lastInteractionStr = NSLocalizedString(@"now", @"");
            }
            detailCell.lastInteraction.text = [NSString stringWithFormat:NSLocalizedString(@"Last seen: %@", @""), lastInteractionStr];

            if(self.contact.isGroup || !self.isSubscribed) {
                detailCell.lockButton.hidden = YES;
            }

            [[MLImageManager sharedInstance] getIconForContact:self.contact.contactJid andAccount:self.contact.accountId withCompletion:^(UIImage *image) {
                detailCell.buddyIconView.image = image;
                //   detailCell.background.image=image;
            }];
            
            detailCell.background.image = [UIImage imageNamed:@"Tie_My_Boat_by_Ray_Garcia"];
            
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
            
            thecell = detailCell;
            break;
        }
        case 1: {
            if(indexPath.row == 0)
            {
                MLTextInputCell *cell=  (MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                if(self.contact.isGroup) {
                    cell.textInput.enabled=NO;
                    cell.textInput.text=self.contact.accountNickInGroup;
                } else  {
                    cell.textInput.text=[self.contact contactDisplayName];
                    cell.textInput.placeholder = NSLocalizedString(@"Set a nickname for this contact", @"");
                    cell.textInput.delegate = self;
                }
                thecell = cell;
            }
            else if(indexPath.row == 1) {
                MLDetailsTableViewCell* cell = (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"MessageCell"];
                if(self.contact.isGroup) {
                    cell.cellDetails.text = self.contact.groupSubject;
                } else  {
                    cell.cellDetails.text = self.contact.statusMessage;
                    if([cell.cellDetails.text isEqualToString:@"(null)"])
                        cell.cellDetails.text = @"";
                }
                thecell = cell;
            }
            else {
                UITableViewCell* cell=  (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"TableCell"];
                cell.textLabel.text = NSLocalizedString(@"View Images Received",@"");
                thecell = cell;
            }
            break;
        }
        case 2: {
            thecell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Sub"];
            if(indexPath.row == 0) {
               thecell.textLabel.text = NSLocalizedString(@"Encryption Keys", @"");
           } else
            if(indexPath.row == 1) {
                if(self.contact.isGroup) {
                    thecell.textLabel.text = NSLocalizedString(@"Participants", @"");
                } else {
                    thecell.textLabel.text = NSLocalizedString(@"Resources", @"");
                }
            }
            else if(indexPath.row == 2) {
                if(self.contact.isGroup) {
                    thecell.textLabel.text = NSLocalizedString(@"Leave Conversation", @"");
                } else {
                    if(self.isSubscribed) {
                        thecell.textLabel.text = NSLocalizedString(@"Remove Contact", @"");
                    } else {
                        thecell.textLabel.text = NSLocalizedString(@"Add Contact", @"");
                    }
                }
            }
            else if(indexPath.row == 3) {
                thecell.textLabel.text = NSLocalizedString(@"Block Sender", @"");
            }
            else if(indexPath.row == 4) {
                thecell.textLabel.text = NSLocalizedString(@"Unblock Sender", @"");
            }
            else if(indexPath.row == 5)  {
                if(self.isPinned) {
                    thecell.textLabel.text = NSLocalizedString(@"Unpin Chat", @"");
                } else {
                    thecell.textLabel.text = NSLocalizedString(@"Pin Chat", @"");
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
    if(section == 0)  return 1;
    if(section == 1)  return 3;
    if(section == 2)  return 6;
    if(section==3){
        return [_versionInfoDic count];
    }
    
    return 0; //some default shouldnt reach this
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn = nil;
    if(section == 1)
        toreturn= NSLocalizedString(@"About",@"");
    
    if(section == 2)
        toreturn= NSLocalizedString(@"Connection Details",@"");
    
    return toreturn;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if(indexPath.section == 0 || indexPath.section == 3) return;
    
    if(indexPath.section==1){
        if(indexPath.row < 2) return;
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
                if(self.contact.isGroup) {
                    [self removeContact]; // works for muc too
                } else  {
                    if(self.isSubscribed) {
                        [self removeContact];
                    }  else  {
                        [self addContact];
                    }
                }
                break;
            }
            case 3:  {
                [self blockContact];
                break;
            }
            case 4:  {
                [self unBlockContact];
                break;
            }
            case 5:  {
                if(self.isPinned) {
                    [[DataLayer sharedInstance] unPinChat:self.accountNo andBuddyJid:self.contact.contactJid];
                } else {
                    [[DataLayer sharedInstance] pinChat:self.accountNo andBuddyJid:self.contact.contactJid];
                }
                self.isPinned = !self.isPinned;
                self.contact.isPinned = self.isPinned;
                // Update button text
                [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
                // Update color in activeViewController
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact":self.contact, @"pinningChanged": @YES}];
                break;
            }
        }
    }
}

-(void) addContact {
    NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Add %@ to your contacts?", @""), self.contact.contactJid];
    NSString* detailString = NSLocalizedString(@"They will see when you are online. They will be able to send you encrypted messages.", @"");

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[MLXMPPManager sharedInstance] addContact:self.contact];
        if([self.contact.state isEqualToString:kSubTo]  || [self.contact.state isEqualToString:kSubNone] ) {
            [[MLXMPPManager sharedInstance] approveContact:self.contact]; //incase there was a pending request
        }
    }]];
    
    alert.popoverPresentationController.sourceView=self.tableView;
    
    [self presentViewController:alert animated:YES completion:nil];
}

-(void) removeContact {
    NSString* messageString = [NSString stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", @""), self.contact.contactJid];
    NSString* detailString = NSLocalizedString(@"They will no longer see when you are online. They may not be able to send you encrypted messages.", @"");
       
    BOOL isMUC=self.contact.isGroup;
    if(isMUC)
    {
        messageString =NSLocalizedString(@"Leave this converstion?",@"");
        detailString=nil;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No",@"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes",@"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
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

-(void) blockContact {
    NSString* messageString = [NSString stringWithFormat:NSLocalizedString(@"Block %@ from contacting you?", @""), self.contact.contactJid];
    NSString* detailString = NSLocalizedString(@"This sender will no longer be able to contact you",@"");

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[MLXMPPManager sharedInstance] blocked:YES Jid:self.contact];
    }]];
    
    alert.popoverPresentationController.sourceView=self.tableView;
    
    [self presentViewController:alert animated:YES completion:nil];
}

-(void) unBlockContact {
    NSString* messageString = [NSString stringWithFormat:NSLocalizedString(@"Allow %@ to contact you?", @""), self.contact.contactJid];
    NSString* detailString =NSLocalizedString(@"This sender will be able to send you messages",@"");

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[MLXMPPManager sharedInstance] blocked:NO Jid:self.contact];
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
            UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close",@"") style:UIBarButtonItemStyleDone target:self action:@selector(closePhotos)];
                          browser.navigationItem.rightBarButtonItem=close;
            
            UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];
            
            [self presentViewController:nav animated:YES completion:nil];
        } else  {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Nothing to see", @"") message:NSLocalizedString(@"You have not received any images in this conversation.",@"") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:self.contact.contactJid];
    self.isMuted = muted;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    });
}

-(IBAction) toggleEncryption:(id)sender
{
#ifndef DISABLE_OMEMO
    NSArray* devices = [self.xmppAccount.omemo knownDevicesForAddressName:self.contact.contactJid];
    [MLChatViewHelper<ContactDetails*> toggleEncryption:&(self->_isEncrypted) forAccount:self.accountNo forContactJid:self.contact.contactJid withKnownDevices:devices withSelf:self afterToggle:^() {
        [self refreshLock];
    }];
#endif
}

-(void) refreshLock
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath* path = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    });
}

#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

-(void) refreshContact:(NSNotification*) notification
{
    weakify(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        strongify(self);
        self.navigationItem.title = [self.contact contactDisplayName];
        if(self.saveHUD)
            self.saveHUD.hidden = YES;
    });
}

-(BOOL) textFieldShouldEndEditing:(UITextField *)textField {
    if(!textField)
        return NO;
    
    //update roster on our server if the nick changed
    if(!self.contact.nickName || ![self.contact.nickName isEqualToString:textField.text])
    {
        //no need to update our db here, this will be done automatically on incoming roster push that gets initiated by our roster set with the new name
        [self.xmppAccount updateRosterItem:self.contact.contactJid withName:textField.text];
        
        self.saveHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.saveHUD.label.text = NSLocalizedString(@"Saving changes to server", @"");
        self.saveHUD.mode = MBProgressHUDModeIndeterminate;
        self.saveHUD.removeFromSuperViewOnHide = YES;
    }
    
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
