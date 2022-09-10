//
//  ContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ContactsViewController.h"
#import "MLContactCell.h"
#import "DataLayer.h"
#import "chatViewController.h"
#import "addContact.h"
#import "MLNewViewController.h"
#import "MonalAppDelegate.h"
#import "UIColor+Theme.h"
#import "xmpp.h"
#import <Monal-Swift.h>
#import "HelperTools.h"

@interface DZNEmptyDataSetView
@property (atomic, strong) UIView* contentView;
@property (atomic, strong) UIImageView* imageView;
@property (atomic, strong) UILabel* titleLabel;
@property (atomic, strong) UILabel* detailLabel;
@end

@interface UIScrollView () <UIGestureRecognizerDelegate>
@property (nonatomic, readonly) DZNEmptyDataSetView* emptyDataSetView;
@end

@interface ContactsViewController ()
@property (nonatomic, strong) UISearchController* searchController;
@property (nonatomic, strong) NSMutableArray<MLContact*>* contacts;
@property (nonatomic, strong) MLContact* lastSelectedContact;
@end

@implementation ContactsViewController

#pragma mark view life cycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.navigationItem.title=NSLocalizedString(@"Contacts", @"");
    
    self.contactsTable = self.tableView;
    self.contactsTable.delegate = self;
    self.contactsTable.dataSource = self;

    self.contacts = [[NSMutableArray alloc] init];
    
    [self.contactsTable reloadData];
    
    [self.contactsTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                    bundle:[NSBundle mainBundle]]
                                    forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.definesPresentationContext = YES;
    
    self.tableView.emptyDataSetSource = self;
    self.tableView.emptyDataSetDelegate = self;

    self.navigationItem.rightBarButtonItem.image = [UIImage systemImageNamed:@"plus"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDeviceRotation) name:UIDeviceOrientationDidChangeNotification object:nil];

}

-(void) handleDeviceRotation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self imageForEmptyDataSet:nil];
    });
}

-(void) dealloc
{
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.lastSelectedContact = nil;
    [self refreshDisplay];

    if(self.contacts.count == 0)
    {
        self.navigationItem.searchController = nil;
        [self reloadTable];
    }
    else
        self.navigationItem.searchController = self.searchController;
}


-(void) viewDidAppear:(BOOL) animated
{
    [super viewDidAppear:animated];
}


-(void) viewWillDisappear:(BOOL) animated
{
    [super viewWillDisappear:animated];
}

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(BOOL) canBecomeFirstResponder
{
    return YES;
}

-(NSArray<UIKeyCommand*>*) keyCommands {
    return @[
        [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(close:)]
    ];
}

#pragma mark - message signals

-(void) reloadTable
{
    if(self.contactsTable.hasUncommittedUpdates) return;
    
    [self.contactsTable reloadData];
}

-(void) refreshDisplay
{
    [self loadContactsWithFilter:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadTable];
    });
}


#pragma mark - chat presentation

-(BOOL) shouldPerformSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    return YES;
}

//this is needed to prevent segues invoked programmatically
-(void) performSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    if([self shouldPerformSegueWithIdentifier:identifier sender:sender] == NO)
        return;
    if([identifier isEqualToString:@"showDetails"])
    {
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeContactDetails:sender];
        [self presentViewController:detailsViewController animated:YES completion:^{}];
        return;
    }
    [super performSegueWithIdentifier:identifier sender:sender];
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    if([segue.identifier isEqualToString:@"showNewMenu"])
    {
        MLNewViewController* newView = segue.destinationViewController;
        newView.selectContact = self.selectContact;
    }
}

-(void) loadContactsWithFilter:(NSString*) filter
{
    if(filter && [filter length] > 0)
        self.contacts = [[DataLayer sharedInstance] searchContactsWithString:filter];
    else
        self.contacts = [[DataLayer sharedInstance] contactList];
}

#pragma mark - Search Controller

-(void) didDismissSearchController:(UISearchController*) searchController;
{
    // reset table to list of all contacts without a filter
    [self loadContactsWithFilter:nil];
    [self reloadTable];
}

-(void) updateSearchResultsForSearchController:(UISearchController*) searchController;
{
    [self loadContactsWithFilter:searchController.searchBar.text];
    [self reloadTable];
}

#pragma mark - tableview datasource

-(NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return nil;
}

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView*) tableView numberOfRowsInSection:(NSInteger) section
{
    return [self.contacts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact* contact = [self.contacts objectAtIndex:indexPath.row];
    
    MLContactCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
        cell = [[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    [cell initCell:contact withLastMessage:nil];
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    
    return cell;
}

#pragma mark - tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}

-(NSString*) tableView:(UITableView*) tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath*) indexPath
{
    MLAssert(indexPath.section == 0, @"Wrong section");
    MLContact* contact = self.contacts[indexPath.row];
    if(contact.isGroup == YES)
        return NSLocalizedString(@"Remove Conversation", @"");
    else
        return NSLocalizedString(@"Remove Contact", @"");
}

-(BOOL) tableView:(UITableView*) tableView canEditRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(tableView == self.view)
        return YES;
    else
        return NO;
}

-(BOOL) tableView:(UITableView*) tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(tableView == self.view)
        return YES;
    else
        return NO;
}

-(void) deleteRowAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact* contact = [self.contacts objectAtIndex:indexPath.row];
    NSString* messageString = [NSString stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", @""), contact.contactJid];
    NSString* detailString = NSLocalizedString(@"They will no longer see when you are online. They may not be able to access your encryption keys.", @"");
    
    if(contact.isGroup)
    {
        messageString = NSLocalizedString(@"Leave this converstion?", @"");
        detailString = nil;
    }
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:detailString preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action __unused) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action __unused) {
        // remove contact
        [[MLXMPPManager sharedInstance] removeContact:contact];
        // remove contact from table
        [self.contactsTable beginUpdates];
        [self.contacts removeObjectAtIndex:indexPath.row];
        [self.contactsTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.contactsTable endUpdates];
    }]];
    alert.popoverPresentationController.sourceView = self.tableView;
    [self presentViewController:alert animated:YES completion:nil];
}

-(void) tableView:(UITableView*) tableView commitEditingStyle:(UITableViewCellEditingStyle) editingStyle forRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(editingStyle == UITableViewCellEditingStyleDelete)
        [self deleteRowAtIndexPath:indexPath];
}

-(void) tableView:(UITableView*) tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath*) indexPath
{
    MLContact* contactDic = [self.contacts objectAtIndex:indexPath.row];
    [self performSegueWithIdentifier:@"showDetails" sender:contactDic];
}

-(void) tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    MLContact* row = [self.contacts objectAtIndex:indexPath.row];
    
    [self dismissViewControllerAnimated:YES completion:^{
        if(self.selectContact)
            self.selectContact(row);
    }];
    
}

#pragma mark - empty data set

-(UIImage*) imageForEmptyDataSet:(UIScrollView*) scrollView
{
    DZNEmptyDataSetView* emptyDataSetView = self.tableView.emptyDataSetView;
    CGRect headerFrame = self.navigationController.navigationBar.frame;
    CGRect tableFrame = self.tableView.frame;
    CGRect contentFrame = emptyDataSetView.contentView.frame;
    DDLogError(@"headerFrame: %@", NSStringFromCGRect(headerFrame));
    DDLogError(@"tableFrame: %@", NSStringFromCGRect(tableFrame));
    DDLogError(@"contentFrame: %@", NSStringFromCGRect(contentFrame));
    //emptyDataSetView.contentView.frame = tableFrame;
    tableFrame.size.height *= 0.5;
    tableFrame.origin.y -= headerFrame.size.height;
    emptyDataSetView.imageView.frame = tableFrame;
    [emptyDataSetView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[imageView]-(64@750)-[titleLabel]-(16@750)-[detailLabel]|" options:0 metrics:nil views:@{
        @"imageView": emptyDataSetView.imageView,
        @"titleLabel": emptyDataSetView.titleLabel,
        @"detailLabel": emptyDataSetView.detailLabel,
    }]];
    emptyDataSetView.imageView.translatesAutoresizingMaskIntoConstraints = YES;
    return [UIImage imageNamed:@"friends"];
}

-(CGFloat) spaceHeightForEmptyDataSet:(UIScrollView*) scrollView
{
    return 48.0f;
}

-(NSAttributedString*) titleForEmptyDataSet:(UIScrollView*) scrollView
{
    NSString* text = NSLocalizedString(@"You need friends for this ride", @"");
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

-(NSAttributedString*) descriptionForEmptyDataSet:(UIScrollView*) scrollView
{
    NSString *text = NSLocalizedString(@"Add new contacts with the + button above. Your friends will pop up here when they can talk", @"");
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

-(UIColor*) backgroundColorForEmptyDataSet:(UIScrollView*) scrollView
{
    return [UIColor colorNamed:@"contacts"];
}

-(BOOL) emptyDataSetShouldDisplay:(UIScrollView*) scrollView
{
    if(self.contacts.count == 0)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    return self.contacts.count == 0;
}

-(IBAction) close:(id) sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
