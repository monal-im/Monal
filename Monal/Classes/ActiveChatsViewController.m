//
//  ActiveChatsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ActiveChatsViewController.h"
#import "DataLayer.h"
#import "MLContactCell.h"
#import "chatViewController.h"
#import "MonalAppDelegate.h"
#import "ContactDetails.h"

@interface ActiveChatsViewController ()
@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign)  NSInteger thisyear;
@property (nonatomic, assign)  NSInteger thismonth;
@property (nonatomic, assign)  NSInteger thisday;
@end

@implementation ActiveChatsViewController

#pragma mark view lifecycle
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"Chats",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _chatListTable=[[UITableView alloc] init];
    _chatListTable.delegate=self;
    _chatListTable.dataSource=self;
    
    self.view=_chatListTable;
    
    UIBarButtonItem* rightButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close All",@"") style:UIBarButtonItemStyleBordered target:self action:@selector(closeAll)];
    self.navigationItem.rightBarButtonItem=rightButton;
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalAccountStatusChanged object:nil];
    
    [_chatListTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
    [self setupDateObjects];
    
}


-(void) refreshDisplay
{
    [[DataLayer sharedInstance] activeContactsWithCompletion:^(NSMutableArray *cleanActive) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:cleanActive];
            self->_contacts=cleanActive;
            [self->_chatListTable reloadData];
            MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [appDelegate updateUnread];
        });
    }];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self refreshDisplay];
    [[MLXMPPManager sharedInstance] handleNewMessage:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) closeAll
{
    [[DataLayer sharedInstance] removeAllActiveBuddies];
    [self refreshDisplay];
}

-(void) presentChatWithRow:(NSDictionary *)row
{
    [self  performSegueWithIdentifier:@"showConversation" sender:row];
}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showConversation"])
    {
        UINavigationController *nav = segue.destinationViewController;
        chatViewController *chatVC = (chatViewController *)nav.topViewController;
        [chatVC setupWithContact:sender];
    }
    else if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController *nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails *)nav.topViewController;
        details.contact= sender;
    }
    
}



#pragma mark tableview datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
   return [_contacts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContactCell* cell =[tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell =[[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }
    

    NSDictionary* row = [_contacts objectAtIndex:indexPath.row];
    
    NSString* fullName=[row objectForKey:@"full_name"];
    if([[fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
        [cell showDisplayName:fullName];
    }
    else {
        [cell showDisplayName:[row objectForKey:@"buddy_name"]];
    }
    
    NSString *state= [[row objectForKey:@"state"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if(![[row objectForKey:@"status"] isEqualToString:@"(null)"] && ![[row objectForKey:@"status"] isEqualToString:@""]) {
       [cell showStatusText:[row objectForKey:@"status"]];
    }
    else
    {
        [cell showStatusText:nil];
    }
    
    if(([state isEqualToString:@"away"]) ||
       ([state isEqualToString:@"dnd"])||
       ([state isEqualToString:@"xa"])
       )
    {
        cell.status=kStatusAway;
    }
    else if([state isEqualToString:@"offline"]) {
        cell.status=kStatusOffline;
    }
    else if([state isEqualToString:@"(null)"] || [state isEqualToString:@""]) {
        cell.status=kStatusOnline;
    }
    
    cell.accountNo=[[row objectForKey:@"account_id"] integerValue];
    cell.username=[row objectForKey:@"buddy_name"] ;
    
    //cell.count=[[row objectForKey:@"count"] integerValue];
    NSString* accountNo=[NSString stringWithFormat:@"%ld", (long)cell.accountNo];
    [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:accountNo withCompletion:^(NSNumber *unread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.count=[unread integerValue];
        });
    }];
    
    NSMutableArray *message = [[DataLayer sharedInstance] lastMessageForContact:cell.username andAccount:accountNo];
    if(message.count>0)
    {
        NSDictionary *row = message[0];
        //TODO chek type Message, Image, Link
        if([[row objectForKey:@"messageType"] isEqualToString:kMessageTypeUrl])
        {
            [cell showStatusText:@"🔗 A Link"];
        } else if([[row objectForKey:@"messageType"] isEqualToString:kMessageTypeImage])
        {
            [cell showStatusText:@"📷 An Image"];
        } else  {
        [cell showStatusText:[row objectForKey:@"message"]];
        }
    }
    
    [[MLImageManager sharedInstance] getIconForContact:[row objectForKey:@"buddy_name"] andAccount:accountNo withCompletion:^(UIImage *image) {
            cell.userImage.image=image;
    }];
    
    if([row objectForKey:@"lastMessageTime"]) {
        cell.time.text = [self formattedDateWithSource:[row objectForKey:@"lastMessageTime"]];
        cell.time.hidden=NO;
    } else  {
        cell.time.hidden=YES;
    }
    
    
    [cell setOrb];
    return cell;
}


#pragma mark tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}


-(NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Close";
}


- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath 
{
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary* contact= [_contacts objectAtIndex:indexPath.row];
        
        [[DataLayer sharedInstance] removeActiveBuddy:[contact objectForKey:@"buddy_name"] forAccount:[contact objectForKey:@"account_id"]];
        [[DataLayer sharedInstance] activeContactsWithCompletion:^(NSMutableArray *cleanActive) {
            [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:cleanActive];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_contacts=cleanActive;
                [self->_chatListTable deleteRowsAtIndexPaths:@[indexPath]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
            });
        }];
        
    }
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
      
    // [[_contacts objectAtIndex:indexPath.row] setObject:[NSNumber numberWithInt:0] forKey:@"count"];
 
    [self presentChatWithRow:[_contacts objectAtIndex:indexPath.row] ];
    
        [tableView reloadRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationNone];
        
        
        _lastSelectedUser=[_contacts objectAtIndex:indexPath.row];
//    }
    
    
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *contactDic = [_contacts objectAtIndex:indexPath.row];

    [self performSegueWithIdentifier:@"showDetails" sender:contactDic];
}


#pragma mark - empty data set

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"pooh"];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = @"No one is here";
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = @"When you start talking to someone from the contacts screen, they will show up here.";
    
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
    return [UIColor colorWithRed:239/255.0 green:238/255.0 blue:233/255.0 alpha:1];
}

- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    BOOL toreturn = (_contacts.count==0)?YES:NO;
    if(toreturn)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    return toreturn;
}

#pragma mark - date

-(NSString*) formattedDateWithSource:(NSString*) sourceDateString
{
    NSString* dateString;
    
    NSDate* sourceDate=[self.sourceDateFormat dateFromString:sourceDateString];
    
    NSInteger msgday =[self.gregorian components:NSCalendarUnitDay fromDate:sourceDate].day;
    NSInteger msgmonth=[self.gregorian components:NSCalendarUnitMonth fromDate:sourceDate].month;
    NSInteger msgyear =[self.gregorian components:NSCalendarUnitYear fromDate:sourceDate].year;
    
    BOOL showFullDate=YES;
    
    //if([sourceDate timeIntervalSinceDate:priorDate]<60*60) showFullDate=NO;
    
    if (((self.thisday!=msgday) || (self.thismonth!=msgmonth) || (self.thisyear!=msgyear)) && showFullDate )
    {
        // note: if it isnt the same day we want to show the full  day
        [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
        //no more need for seconds
        [self.destinationDateFormat setTimeStyle:NSDateFormatterNoStyle];
    }
    else
    {
        //today just show time
        [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
    }
    
    dateString = [self.destinationDateFormat stringFromDate:sourceDate];
    return dateString?dateString:@"";
}

-(void) setupDateObjects
{
    self.destinationDateFormat = [[NSDateFormatter alloc] init];
    [self.destinationDateFormat setLocale:[NSLocale currentLocale]];
    [self.destinationDateFormat setDoesRelativeDateFormatting:YES];
    
    self.sourceDateFormat = [[NSDateFormatter alloc] init];
    [self.sourceDateFormat setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    [self.sourceDateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    self.gregorian = [[NSCalendar alloc]
                      initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDate* now =[NSDate date];
    self.thisday =[self.gregorian components:NSCalendarUnitDay fromDate:now].day;
    self.thismonth =[self.gregorian components:NSCalendarUnitMonth fromDate:now].month;
    self.thisyear =[self.gregorian components:NSCalendarUnitYear fromDate:now].year;
    
    
}

@end
