//
//  ContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ContactsViewController.h"
#import "MLContactCell.h"
#import "MLInfoCell.h"
#import "DataLayer.h"
#import "chatViewController.h"
#import "ContactDetails.h"
#import "addContact.h"
#import "CallViewController.h"
#import "MonalAppDelegate.h"
#import "UIColor+Theme.h"
#import "MLGroupChatTableViewController.h"


#define konlineSection 1
#define kofflineSection 2

@interface ContactsViewController () 
@property (nonatomic, strong) NSArray* searchResults ;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic ,strong) NSMutableArray* contacts;
@property (nonatomic ,strong) NSMutableArray* offlineContacts;
@property (nonatomic ,strong) MLContact* lastSelectedContact;

@end

@implementation ContactsViewController



#pragma mark view life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.navigationItem.title=NSLocalizedString(@"Contacts", @"");
    
    self.contactsTable=self.tableView;
    self.contactsTable.delegate=self;
    self.contactsTable.dataSource=self;
    
    
    self.contacts=[[NSMutableArray alloc] init] ;
    self.offlineContacts=[[NSMutableArray alloc] init] ;
    
    [self.contactsTable reloadData];
    
    
    [self.contactsTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                                   bundle:[NSBundle mainBundle]]
             forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
    self.searchController =[[UISearchController alloc] initWithSearchResultsController:nil];
    
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.definesPresentationContext = YES;
    
    self.navigationItem.searchController = self.searchController;
    
    self.tableView.emptyDataSetSource = self;
    self.tableView.emptyDataSetDelegate = self;
        
    
}

-(void) dealloc
{
   
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.lastSelectedContact=nil;
    [self refreshDisplay];
    
    if(self.contacts.count+self.offlineContacts.count == 0)
    {
        [self reloadTable];
    }
}


-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - jingle

-(void) showCallRequest:(NSNotification *) notification
{
    NSDictionary* dic = notification.object;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* contactName = [dic objectForKey:@"user"];
        NSString* userName = [dic objectForKey:kUsername];

        UIAlertController* messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Incoming Call", @"") message:[NSString stringWithFormat:NSLocalizedString(@"Incoming audio call to %@ from %@ ", @""),userName,  contactName] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *acceptAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Accept", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            
            [self performSegueWithIdentifier:@"showCall" sender:dic];
            
            [[MLXMPPManager sharedInstance] handleCall:dic withResponse:YES];
        }];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Decline" , @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [[MLXMPPManager sharedInstance] handleCall:dic withResponse:NO];
        }];
        [messageAlert addAction:closeAction];
        [messageAlert addAction:acceptAction];

        [self.tabBarController presentViewController:messageAlert animated:YES completion:nil];
    });
}

#pragma mark - message signals

-(void) reloadTable
{
    if(self.contactsTable.hasUncommittedUpdates) return;
    
    [self.contactsTable reloadData];
}

-(void) refreshDisplay
{
    if([[HelperTools defaultsDB] boolForKey:@"SortContacts"]) //sort by status
    {
        NSMutableArray* results = [[DataLayer sharedInstance] onlineContactsSortedBy:@"Status"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.contacts= results;
            [self reloadTable];
        });
    }
    else {
        NSMutableArray* results = [[DataLayer sharedInstance] onlineContactsSortedBy:@"Name"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.contacts= results;
         [self reloadTable];
        });
    }
    if([[HelperTools defaultsDB] boolForKey:@"OfflineContact"])
    {
        NSMutableArray* results = [[DataLayer sharedInstance] offlineContacts];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.offlineContacts= results;
           [self reloadTable];
        });
    }
    if(self.searchResults.count == 0)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self reloadTable];
        });
    }
}


#pragma mark - chat presentation
-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
   if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController* nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails *)nav.topViewController;
        details.contact = sender;
    }
    else if([segue.identifier isEqualToString:@"showGroups"])
       {
           MLGroupChatTableViewController* groups = (MLGroupChatTableViewController *)segue.destinationViewController;
           groups.selectGroup = ^(MLContact *selectedContact) {
               if(self.selectContact) self.selectContact(selectedContact);
               [self close:nil];
           };
       }
}

#pragma mark - Search Controller

- (void)didDismissSearchController:(UISearchController *)searchController;
{
    self.searchResults = nil;
    [self reloadTable];
}


- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
{
    if(searchController.searchBar.text.length > 0) {
        NSString* term = [searchController.searchBar.text copy];
        self.searchResults = [[DataLayer sharedInstance] searchContactsWithString:term];
    } else  {
        self.searchResults = nil;
    }
    [self reloadTable];
}


#pragma mark - tableview datasource
-(NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toReturn = nil;
    switch (section) {
        case konlineSection:
            toReturn = NSLocalizedString(@"Recently Seen", @"");
            break;
        case kofflineSection:
            toReturn = NSLocalizedString(@"Away", @"");
            break;
        default:
            break;
    }
    
    return toReturn;
}

-(NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewRowAction *delete = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:NSLocalizedString(@"Delete", @"") handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
        [self deleteRowAtIndexPath:indexPath];
    }];
    UITableViewRowAction* mute;
    MLContactCell* cell = (MLContactCell *)[tableView cellForRowAtIndexPath:indexPath];
    if(cell.muteBadge.hidden)
    {
        mute = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault title:NSLocalizedString(@"Mute", @"") handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            [self muteContactAtIndexPath:indexPath];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
        }];
        [mute setBackgroundColor:[UIColor monalGreen]];
        
    } else  {
        mute = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault title:NSLocalizedString(@"Unmute",@"") handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            [self unMuteContactAtIndexPath:indexPath];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
        }];
        [mute setBackgroundColor:[UIColor monalGreen]];
        
    }
    
    //    UITableViewRowAction *block = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"Block" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
    //        [self blockContactAtIndexPath:indexPath];
    //        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    //    }];
    //    [block setBackgroundColor:[UIColor darkGrayColor]];
    
    return @[delete, mute];
    
}

-(MLContact  *)contactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact* contact;
    if ((indexPath.section==1) && (indexPath.row<=[self.contacts count]) ) {
        contact=[self.contacts objectAtIndex:indexPath.row];
    }
    else if((indexPath.section==2) && (indexPath.row<=[self.offlineContacts count]) ) {
        contact=[self.offlineContacts objectAtIndex:indexPath.row];
    }
    return contact;
}

-(void) muteContactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact *contact = [self contactAtIndexPath:indexPath];
    if(contact){
        [[DataLayer sharedInstance] muteJid:contact.contactJid];
    }
}

-(void) unMuteContactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact *contact = [self contactAtIndexPath:indexPath];
    if(contact){
        [[DataLayer sharedInstance] unMuteJid:contact.contactJid];
    }
}


-(void) blockContactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact *contact = [self contactAtIndexPath:indexPath];
    if(contact){
        [[DataLayer sharedInstance] blockJid:contact.contactJid];
    }
}


-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger toreturn=0;
    if(self.searchResults.count>0) {
        toreturn =1;
    }
    else{
        if([[HelperTools defaultsDB] boolForKey:@"OfflineContact"])
            toreturn =3;
        else
            toreturn =2;
    }
    return toreturn;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toReturn=0;
    if(self.searchResults.count>0) {
        toReturn=[self.searchResults count];
    }
    //if(tableView ==self.view)
    else {
        switch (section) {
            case konlineSection:
                toReturn= [self.contacts count];
                break;
            case kofflineSection:
                toReturn=[self.offlineContacts count];
                break;
            default:
                break;
        }
    }
    
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact* row = nil;
    if(self.searchResults.count > 0) {
        row = [self.searchResults objectAtIndex:indexPath.row];
    }
    else
    {
        if(indexPath.section == konlineSection)
        {
            row = [self.contacts objectAtIndex:indexPath.row];
        }
        else if(indexPath.section == kofflineSection)
        {
            row = [self.offlineContacts objectAtIndex:indexPath.row];
        }
        else {
            DDLogError(@"Could not identify cell section");
        }
    }
    
    MLContactCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell = [[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }
    
    cell.count = 0;
    cell.userImage.image = nil;
    cell.statusText.text = @"";
    
    [cell showDisplayName:row.contactDisplayName];
    
    if(![row.statusMessage isEqualToString:@"(null)"] && ![row.statusMessage isEqualToString:@""]) {
        [cell showStatusText:row.statusMessage];
    }
    else {
        [cell showStatusText:nil];
    }
    
    if(row.isGroup && row.groupSubject) {
        [cell showStatusText:row.groupSubject];
    }
    
    if(tableView == self.view) {
        if(indexPath.section == konlineSection)
        {
            NSString* stateString = [row.state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ;
            
            if(([stateString isEqualToString:@"away"]) ||
               ([stateString isEqualToString:@"dnd"])||
               ([stateString isEqualToString:@"xa"])
               )
            {
                cell.status = kStatusAway;
            }
            else if([row.state isEqualToString:@"(null)"] ||
                    [row.state isEqualToString:@""])
                cell.status=kStatusOnline;
        }
        else  if(indexPath.section == kofflineSection) {
            cell.status=kStatusOffline;
        }}
    else {
        if(row.isOnline == YES)
        {
            cell.status = kStatusOnline;
        }
        else
        {
            cell.status = kStatusOffline;
        }
    }
    
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    
    cell.accountNo=[row.accountId integerValue];
    cell.username=row.contactJid;

    NSNumber* unreadMessagesCnt = [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:row.accountId];
    dispatch_async(dispatch_get_main_queue(), ^{
        cell.count = [unreadMessagesCnt integerValue];
    });

    [[MLImageManager sharedInstance] getIconForContact:row.contactJid andAccount:row.accountId withCompletion:^(UIImage *image) {
        cell.userImage.image=image;
    }];
    [cell setOrb];
    
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:row.contactJid];
    dispatch_async(dispatch_get_main_queue(), ^{
        cell.muteBadge.hidden = !muted;
    });
    return cell;
}

#pragma mark - tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}

-(NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NSLocalizedString(@"Remove Contact",@"");
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView ==self.view) {
        return YES;
    }
    else
    {
        return NO;
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView ==self.view) {
        return YES;
    }
    else
    {
        return NO;
    }
}

-(void) deleteRowAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact* contact;
    if ((indexPath.section == 1) && (indexPath.row<=[self.contacts count]) ) {
        contact=[self.contacts objectAtIndex:indexPath.row];
    }
    else if((indexPath.section == 2) && (indexPath.row<=[self.offlineContacts count]) ) {
        contact=[self.offlineContacts objectAtIndex:indexPath.row];
    }
    else {
        //we cannot delete here
        return;
    }
    
    NSString* messageString = [NSString stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", @""), contact.contactJid];
    NSString* detailString = NSLocalizedString(@"They will no longer see when you are online. They may not be able to access your encryption keys.", @"");
    
    BOOL isMUC=contact.isGroup;
    if(isMUC)
    {
        messageString =NSLocalizedString(@"Leave this converstion?", @"");
        detailString=nil;
    }
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        if(isMUC) {
            [[MLXMPPManager sharedInstance] leaveRoom:contact.contactJid withNick:contact.accountNickInGroup forAccountId:contact.accountId ];
        }
        else  {
            [[MLXMPPManager sharedInstance] removeContact:contact];
        }
        
        if(self.searchResults.count == 0) {
            [self.contactsTable beginUpdates];
            if ((indexPath.section == 1) && (indexPath.row <= [self.contacts count]) ) {
                [self.contacts removeObjectAtIndex:indexPath.row];
            }
            else if((indexPath.section==2) && (indexPath.row<=[self.offlineContacts count]) ) {
                [self.offlineContacts removeObjectAtIndex:indexPath.row];
            }
            else {
                //nothing to delete just end
                [self.contactsTable endUpdates];
                return;
            }
            
            [self.contactsTable deleteRowsAtIndexPaths:@[indexPath]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.contactsTable endUpdates];
        }
        
    }]];
    
    alert.popoverPresentationController.sourceView=self.tableView;
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self deleteRowAtIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    MLContact *contactDic;
    if(self.searchResults.count>0)
    {
        contactDic=  [self.searchResults objectAtIndex:indexPath.row];
    }
    else  {
        if(indexPath.section==konlineSection) {
            contactDic=[self.contacts objectAtIndex:indexPath.row];
        }
        else {
            contactDic=[self.offlineContacts objectAtIndex:indexPath.row];
        }
    }
    
    [self performSegueWithIdentifier:@"showDetails" sender:contactDic];
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact* row;
    
    if(self.searchResults.count>0)
    {
        row= [self.searchResults objectAtIndex:indexPath.row];
    } else
    {
        if((indexPath.section==konlineSection))
        {
            if(indexPath.row<self.contacts.count)
                row=[self.contacts objectAtIndex:indexPath.row];
        }
        else if (indexPath.section==kofflineSection)
        {
            if(indexPath.row<self.offlineContacts.count)
                row= [self.offlineContacts objectAtIndex:indexPath.row];
        }
        
        row.unreadCount=0;
    }
    
    [self dismissViewControllerAnimated:YES completion:^{
        if(self.selectContact) self.selectContact(row);
    }];
    
}

#pragma mark - empty data set

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"river"];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = NSLocalizedString(@"You need friends for this ride", @"");
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = NSLocalizedString(@"Add new contacts with the + button above. Your friends will pop up here when they can talk", @"");
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIColor colorNamed:@"contacts"];
}

- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    BOOL  toreturn=(self.contacts.count+self.offlineContacts.count==0)?YES:NO;
    
    if(toreturn)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    
    return toreturn;
}

-(IBAction) close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
