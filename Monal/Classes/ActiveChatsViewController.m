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
#import "MLImageManager.h"



@interface ActiveChatsViewController ()
@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign)  NSInteger thisyear;
@property (nonatomic, assign)  NSInteger thismonth;
@property (nonatomic, assign)  NSInteger thisday;

@property (nonatomic, strong) NSArray* contacts;
@property (nonatomic, strong) MLContact* lastSelectedUser;

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
    
     self.chatListTable=[[UITableView alloc] init];
     self.chatListTable.delegate=self;
     self.chatListTable.dataSource=self;
    
    self.view= self.chatListTable;
    
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalAccountStatusChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshContact:) name: kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    [_chatListTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    #if !TARGET_OS_MACCATALYST
    if (@available(iOS 13.0, *)) {
        self.splitViewController.primaryBackgroundStyle=UISplitViewControllerBackgroundStyleSidebar;
    } else {
        // Fallback on earlier versions
    }
      #endif
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
    [self setupDateObjects];
    
}


-(void) refreshDisplay
{
    [[DataLayer sharedInstance] activeContactsWithCompletion:^(NSMutableArray *cleanActive) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (@available(iOS 11.0, *)) {
                 if(self.chatListTable.hasUncommittedUpdates) return;
             } else {
                 // Fallback on earlier versions
             }
            
            [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:cleanActive];
            self.contacts=cleanActive;
            [self.chatListTable reloadData];
            MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [appDelegate updateUnread];
        });
    }];
}

-(void) refreshContact:(NSNotification *) notification
{
    MLContact* user = [notification.userInfo objectForKey:@"contact"];;
    [self refreshRowForContact:user];
}


-(void) handleNewMessage:(NSNotification *)notification
{
    MLMessage *message =[notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus]) return;
    
    dispatch_async(dispatch_get_main_queue(),^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground || !message.shouldShowAlert)
        {
            return;
        }
        
        if([self.lastSelectedUser.contactJid isEqualToString:message.from])  return;
        
        __block BOOL contactInList=NO;
        if (@available(iOS 11.0, *)) {
            [self.chatListTable performBatchUpdates:^{
                __block BOOL contactInList=NO;
                [self.contacts enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    MLContact *rowContact = (MLContact *) obj;
                    if([rowContact.contactJid isEqualToString:message.from]) {
                        contactInList=YES;
                        NSIndexPath *indexPath =[NSIndexPath indexPathForRow:idx inSection:0];
                        [self.chatListTable beginUpdates];
                        [self.chatListTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                        [self.chatListTable endUpdates];
                    }
                }];
            }
             completion:^(BOOL finished){
                if(!contactInList) {
                    [self refreshDisplay];
                }
            }];
        } else  { //TODO remove when ios 10 is dropped

            [self.contacts enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                MLContact *rowContact = (MLContact *) obj;
                if([rowContact.contactJid isEqualToString:message.from]) {
                    contactInList=YES;
                    NSIndexPath *indexPath =[NSIndexPath indexPathForRow:idx inSection:0];
                    [self.chatListTable beginUpdates];
                    [self.chatListTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                    [self.chatListTable endUpdates];
                }
            }];
            
            if(!contactInList) {
                [self refreshDisplay];
            }
        }
    });
    
}

-(void) refreshRowForContact:(MLContact *) contact {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 11.0, *)) {
            [self.chatListTable performBatchUpdates:^{
                [self.contacts enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    MLContact *rowContact = (MLContact *) obj;
                    if([rowContact.contactJid isEqualToString:contact.contactJid]) {
                        NSIndexPath *indexPath =[NSIndexPath indexPathForRow:idx inSection:0];
                        [self.chatListTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                        *stop=YES;
                        return;
                    }
                }];
            } completion:^(BOOL finished){
                
            } ];
        } else  { //TODO remove when ios 10 is dropped
            [self.contacts enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                MLContact *rowContact = (MLContact *) obj;
                if([rowContact.contactJid isEqualToString:contact.contactJid]) {
                    NSIndexPath *indexPath =[NSIndexPath indexPathForRow:idx inSection:0];
                    [self.chatListTable beginUpdates];
                    [self.chatListTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                    [self.chatListTable endUpdates];
                    *stop=YES;
                    return;
                }
            }];
        }
    });
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.lastSelectedUser=nil;
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



#pragma mark - tableview datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
   return [self.contacts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContactCell* cell =[tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell =[[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }
    

    MLContact* row = [self.contacts objectAtIndex:indexPath.row];
    [cell showDisplayName:row.contactDisplayName];
    
    
    NSString *state= [row.state  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
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
    
    cell.accountNo=row.accountId.integerValue;
    cell.username=row.contactJid;
    cell.count=0;
    
    [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:row.accountId withCompletion:^(NSNumber *unread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.count=[unread integerValue];
        });
    }];
    
    [cell showStatusText:nil];
    
    [[DataLayer sharedInstance] lastMessageForContact:cell.username forAccount:row.accountId withCompletion:^(NSMutableArray *messages) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(messages.count>0)
            {
                MLMessage *messageRow = messages[0];
                if([messageRow.messageType isEqualToString:kMessageTypeUrl])
                {
                    [cell showStatusText:@"🔗 A Link"];
                } else if([messageRow.messageType isEqualToString:kMessageTypeImage])
                {
                    [cell showStatusText:@"📷 An Image"];
                } else  {
                    [cell showStatusText:messageRow.messageText];
                }
            } else  {
                DDLogWarn(@"Active chat but no messages found in history for %@.", row.contactJid);
            }
        });
    }];
                       
    [[MLImageManager sharedInstance] getIconForContact:row.contactJid andAccount:row.accountId withCompletion:^(UIImage *image) {
            cell.userImage.image=image;
    }];
    
    if(row.lastMessageTime) {
        cell.time.text = [self formattedDateWithSource:row.lastMessageTime];
        cell.time.hidden=NO;
    } else  {
        cell.time.hidden=YES;
    }
        
    [cell setOrb];
    return cell;
}


#pragma mark - tableview delegate

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
        MLContact* contact= [self.contacts objectAtIndex:indexPath.row];
        
        [[DataLayer sharedInstance] removeActiveBuddy:contact.contactJid forAccount:contact.accountId];
        [[DataLayer sharedInstance] activeContactsWithCompletion:^(NSMutableArray *cleanActive) {
            [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:cleanActive];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.contacts=cleanActive;
                [self.chatListTable deleteRowsAtIndexPaths:@[indexPath]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
            });
        }];
        
    }
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact *selected = self.contacts[indexPath.row];
    if(selected.contactJid==self.lastSelectedUser.contactJid) return;
    
    [self presentChatWithRow:[self.contacts objectAtIndex:indexPath.row] ];
    self.lastSelectedUser=[self.contacts objectAtIndex:indexPath.row];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *contactDic = [self.contacts objectAtIndex:indexPath.row];

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
    if (@available(iOS 11.0, *)) {
        return [UIColor colorNamed:@"chats"];
    } else {
       return [UIColor colorWithRed:239/255.0 green:238/255.0 blue:233/255.0 alpha:1];
    }
    
}

- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    BOOL toreturn = (self.contacts.count==0)?YES:NO;
    if(toreturn)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    return toreturn;
}

#pragma mark - date

-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
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
    
    NSString *dateString = [self.destinationDateFormat stringFromDate:sourceDate];
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
