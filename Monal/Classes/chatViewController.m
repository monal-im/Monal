//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chatViewController.h"
#import "MLConstants.h"
#import "MonalAppDelegate.h"
#import <QuartzCore/QuartzCore.h>


static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface chatViewController()

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign) NSInteger thisyear;
@property (nonatomic, assign) NSInteger thismonth;
@property (nonatomic, assign) NSInteger thisday;

@end

@implementation chatViewController


- (void)makeView {
	
    self.view.backgroundColor=[UIColor whiteColor];
    _messageTable =[[UITableView alloc] initWithFrame:CGRectMake(0, 2, self.view.frame.size.width, self.view.frame.size.height-42)];
    
    //    pages = [[UIPageControl alloc] init];
    //    pages.frame=CGRectMake(0, self.view.frame.size.height - 40-20, self.view.frame.size.width, 20);
    //
    containerView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 40, self.view.frame.size.width, 40)];
    
	chatInput = [[HPGrowingTextView alloc] initWithFrame:CGRectMake(6, 3, self.view.frame.size.width-80, 40)];
    chatInput.contentInset = UIEdgeInsetsMake(0, 5, 0, 5);
    
	chatInput.minNumberOfLines = 1;
	chatInput.maxNumberOfLines = 8;
	
	chatInput.font = [UIFont systemFontOfSize:15.0f];
	chatInput.delegate = self;
    chatInput.internalTextView.scrollIndicatorInsets = UIEdgeInsetsMake(5, 0, 5, 0);
    chatInput.backgroundColor = [UIColor whiteColor];
    
    //page control
    //    pages.backgroundColor = [UIColor colorWithRed:.4 green:0.435 blue:0.498 alpha:1];
    //
    //    pages.hidesForSinglePage=false;
    //    pages.numberOfPages=0;
    //    pages.currentPage=0;
    //
    
    [self.view addSubview:_messageTable];
    //    [self.view addSubview:pages];
    [self.view addSubview:containerView];
    
    if(SYSTEM_VERSION_LESS_THAN(@"7.0"))
    {
        UIImage *rawBackground = [UIImage imageNamed:@"MessageEntryBackground.png"];
        UIImage *background = [rawBackground stretchableImageWithLeftCapWidth:13 topCapHeight:22];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:background];
        imageView.frame = CGRectMake(0, 0, containerView.frame.size.width, containerView.frame.size.height);
        imageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [containerView addSubview:imageView];
        
    }
    
    [containerView addSubview:chatInput];
    
    if(SYSTEM_VERSION_LESS_THAN(@"7.0"))
    {
        UIImage *rawEntryBackground = [UIImage imageNamed:@"MessageEntryInputField.png"];
        UIImage *entryBackground = [rawEntryBackground stretchableImageWithLeftCapWidth:13 topCapHeight:22];
        UIImageView *entryImageView = [[UIImageView alloc] initWithImage:entryBackground];
        entryImageView.frame = CGRectMake(5, 0, self.view.frame.size.width-72, 40);
        entryImageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [containerView addSubview:entryImageView];
    }
    
    chatInput.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // view hierachy
    
    if(SYSTEM_VERSION_LESS_THAN(@"7.0"))
    {
        
        UIImage *sendBtnBackground = [[UIImage imageNamed:@"MessageEntrySendButton.png"] stretchableImageWithLeftCapWidth:13 topCapHeight:0];
        UIImage *selectedSendBtnBackground = [[UIImage imageNamed:@"MessageEntrySendButton.png"] stretchableImageWithLeftCapWidth:13 topCapHeight:0];
        
        
        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        doneBtn.frame = CGRectMake(containerView.frame.size.width - 69, 8, 63, 27);
        doneBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
        [doneBtn setTitle:@"Send" forState:UIControlStateNormal];
        
        [doneBtn addTarget:self action:@selector(resignTextView) forControlEvents:UIControlEventTouchUpInside];
        
        
        [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [doneBtn setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
        doneBtn.titleLabel.shadowOffset = CGSizeMake (0.0, -1.0);
        [doneBtn.titleLabel setFont:[UIFont boldSystemFontOfSize:18.0f]];
        [doneBtn setBackgroundImage:sendBtnBackground forState:UIControlStateNormal];
        [doneBtn setBackgroundImage:selectedSendBtnBackground forState:UIControlStateSelected];
        
        [containerView addSubview:doneBtn];
	}
    else
    {
        
        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        doneBtn.frame = CGRectMake(containerView.frame.size.width - 69, 8, 63, 27);
        doneBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
        [doneBtn setTitle:@"Send" forState:UIControlStateNormal];
        doneBtn.titleLabel.font=[UIFont boldSystemFontOfSize:19.0f];
        
        [doneBtn addTarget:self action:@selector(resignTextView) forControlEvents:UIControlEventTouchUpInside];
        [containerView addSubview:doneBtn];
        
        containerView.backgroundColor=[UIColor colorWithRed:248/255.0f green:248/255.0f blue:248/255.0f alpha:1.0];
        
        chatInput.layer.cornerRadius=5.0f;
        chatInput.layer.borderWidth = 1.0f;
        chatInput.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        
        CGRect lineFrame = containerView.frame;
        lineFrame.size.height=1;
        lineFrame.origin.x=0;
        lineFrame.origin.y=0;
        UIView* lineView=[[UIView alloc] initWithFrame:lineFrame];
        lineView.backgroundColor=[UIColor colorWithRed:206/255.0f green:206/255.0f blue:206/255.0f alpha:1.0];
        
        [containerView addSubview:lineView];
        lineView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
    }
    
    
    
    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    _messageTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    //    pages.autoresizingMask= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    
    //    UISwipeGestureRecognizer* swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDetected:)];
    //    [swipe setDirection:(UISwipeGestureRecognizerDirectionRight )];
    //    [self.view addGestureRecognizer:swipe];
    //
    //    UISwipeGestureRecognizer* swipe2 = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDetected:)];
    //    [swipe2 setDirection:( UISwipeGestureRecognizerDirectionLeft)];
    //    [self.view addGestureRecognizer:swipe2];
    
    chatInput.delegate=self;
    
    
    //set up nav bar view
    _topBarView =[[UIView alloc] initWithFrame:CGRectMake(30, 5, _messageTable.frame.size.width-30, 44)];
    CGRect imageFrame=CGRectMake(0, 5, 32, 32);
    CGRect nameFrame=CGRectMake(37, 5, _topBarView.frame.size.width-37, imageFrame.size.height);
    
    _topIcon =[[UIImageView alloc] initWithFrame:imageFrame];
    _topIcon.layer.cornerRadius=7.0f;
    _topIcon.clipsToBounds=YES;
    
    _topName=[[UILabel alloc] initWithFrame:nameFrame];
    _topName.font=[UIFont boldSystemFontOfSize:15.0f];
    
    if(SYSTEM_VERSION_LESS_THAN(@"7.0"))
    {
        _topName.textColor=[UIColor whiteColor];
    }
    _topName.backgroundColor=[UIColor clearColor];
    
    [_topBarView addSubview:_topIcon];
    [_topBarView addSubview:_topName];
    
    self.navigationItem.titleView=_topBarView;
    
}

-(void) setup
{
    _contactName=[_contact objectForKey:@"buddy_name"];
    if(!_contactName)
    {
        _contactName=[_contact objectForKey:@"message_from"];
    }
	_contactFullName=[_contact objectForKey:@"full_name"];;
    self.accountNo=[NSString stringWithFormat:@"%d",[[_contact objectForKey:@"account_id"] integerValue]];
    self.hidesBottomBarWhenPushed=YES;
    
#warning this should be smarter...
    NSArray* accountVals =[[DataLayer sharedInstance] accountVals:self.accountNo];
    if([accountVals count]>0)
    {
        self.jid=[NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:@"username"], [[accountVals objectAtIndex:0] objectForKey:@"domain"]];
    }
}

-(id) initWithContact:(NSDictionary*) contact
{
    self=[super init];
    if(self){
        _contact=contact;
        [self setup];
    }
    return self;
    
}

-(id) initWithContact:(NSDictionary*) contact  andDay:(NSString* )day;
{
    self = [super init];
    if(self){
        _contact=contact;
        _day=day;
        [self setup];
    }
    
    return self;
}


#pragma mark view lifecycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self makeView];
    [self setupDateObjects];
    self.navigationController.view.backgroundColor=[UIColor whiteColor];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleTap) name:UIApplicationDidEnterBackgroundNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardDidShow:) name: UIKeyboardDidShowNotification object:nil];
    
    self.hidesBottomBarWhenPushed=YES;
    _messageTable.delegate=self;
    _messageTable.dataSource=self;
    self.view.autoresizesSubviews=true;
    _messageTable.separatorColor=[UIColor whiteColor];
    
    //    UIMenuItem *openMenuItem = [[UIMenuItem alloc] initWithTitle:@"Open in Safari" action:@selector(openlink:)];
    //    [[UIMenuController sharedMenuController] setMenuItems: @[openMenuItem]];
    //    [[UIMenuController sharedMenuController] update];
    
    
    
}

-(void)viewWillAppear:(BOOL)animated
{
    
    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
    [MLNotificationManager sharedInstance].currentContact=self.contactName;
    
    if(!_day) {
        _messagelist =[[DataLayer sharedInstance] messageHistory:_contactName forAccount: _accountNo];
        int unread =[[DataLayer sharedInstance] countUserUnreadMessages:_contactName forAccount: _accountNo];
        _isMUC=[[DataLayer sharedInstance] isBuddyMuc:_contactName forAccount: _accountNo];
        
        if(unread==0)
            _firstmsg=YES;
    }
    else
    {
        _messagelist =[[[DataLayer sharedInstance] messageHistoryDate:_contactName forAccount: _accountNo forDate:_day] mutableCopy];
        
    }
    
    
    if(![_contactFullName isEqualToString:@"(null)"] && [[_contactFullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0)
    {
        _topName.text=_contactFullName;
    }
    else {
        _topName.text=_contactName;
    }
    
    if(_day) {
        _topName.text= [NSString stringWithFormat:@"%@(%@)", _topName.text, _day];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [containerView removeFromSuperview];
        [_topIcon removeFromSuperview];
    }
    else
    {
        _topIcon.image=[[MLImageManager sharedInstance] getIconForContact:_contactName andAccount:_accountNo];
        
    }
    [self refreshCounter];
    
}

-(void) viewDidAppear:(BOOL)animated
{
    [self scrollToBottom];
    [self refreshCounter];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [MLNotificationManager sharedInstance].currentAccountNo=nil;
    [MLNotificationManager sharedInstance].currentContact=nil;
    
    [self refreshCounter];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark rotation
-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	[chatInput resignFirstResponder];
	return YES;
}

- (BOOL)shouldAutorotate
{
   	[chatInput resignFirstResponder];
    return YES;
}

-(void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [chatInput resignFirstResponder];
}

#pragma mark gestures
-(void) handleTap
{
    [chatInput resignFirstResponder];
}

#pragma mark message signals


-(void) refreshCounter
{
    
    //coming in  from abckgroun
    if(!_day) {
        [[DataLayer sharedInstance] markAsReadBuddy:self.contactName forAccount:self.accountNo];
        
        MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
        [appDelegate updateUnread];
    }
    
}


#pragma mark textview

-(void)resignTextView
{
    if(([chatInput text]!=nil) && (![[chatInput text] isEqualToString:@""]) )
    {
        DDLogVerbose(@"Sending message");
        [[MLXMPPManager sharedInstance] sendMessage:[chatInput text] toContact:_contactName fromAccount:_accountNo isMUC:_isMUC
                              withCompletionHandler:nil];
        [self addMessageto:_contactName withMessage:[chatInput text]];
        
    }
    [chatInput setText:@""];
}


#pragma mark message signals

//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message
{
	
	if([[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:_accountNo withMessage:message actuallyFrom:self.jid ])
	{
		DDLogVerbose(@"added message");
        
		if(_isMUC) //  message will come back
		{
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                               NSDictionary* userInfo = @{@"af": self.jid,
                                                          @"message": message ,
                                                          @"thetime": [self currentGMTTime] };
                               [_messagelist addObject:userInfo];
                               
                               [_messageTable beginUpdates];
                               NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
                               [_messageTable insertRowsAtIndexPaths:@[path1]
                                                    withRowAnimation:UITableViewRowAnimationBottom];
                               [_messageTable endUpdates];
                               
                               
                               if(![_messageTable.indexPathsForVisibleRows containsObject:path1])
                               {
                                   
                                   [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
                               }
                           });
            
            
        }
		
	}
	else
		DDLogVerbose(@"failed to add message");
	
	// make sure its in active
	if(_firstmsg==YES)
	{
        [[DataLayer sharedInstance] addActiveBuddies:to forAccount:_accountNo];
        _firstmsg=NO;
	}
	
    
    
}

-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    
    if([[notification.userInfo objectForKey:@"accountNo"] isEqualToString:_accountNo]
       && [[notification.userInfo objectForKey:@"from"] isEqualToString:_contactName]
       )
    {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           NSDictionary* userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                                      @"message": [notification.userInfo objectForKey:@"messageText"],
                                                      @"thetime": [self currentGMTTime]};
                           [_messagelist addObject:userInfo];
                           
                           [_messageTable beginUpdates];
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
                           [_messageTable insertRowsAtIndexPaths:@[path1]
                                                withRowAnimation:UITableViewRowAnimationTop];
                           [_messageTable endUpdates];
                           
                           [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:YES];
                           
                           //mark as read
                           [[DataLayer sharedInstance] markAsReadBuddy:_contactName forAccount:_accountNo];
                       });
    }
}


#pragma mark MUC display elements
-(void) popContacts
{
    DDLogVerbose(@"pop out contacts");
    
    //    UITableViewController* tbv = [UITableViewController alloc];
    //    tbv.tableView=contactList;
    //    popOverController = [[UIPopoverController alloc] initWithContentViewController:tbv];
    //
    //    popOverController.popoverContentSize = CGSizeMake(320, 480);
    //    [popOverController presentPopoverFromBarButtonItem:contactsButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    //
    //
    //
}


-(void) scrollToBottom
{
    if([_messagelist count]>0)
    {
        NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
        if(![_messageTable.indexPathsForVisibleRows containsObject:path1])
        {
            [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        }
    }
    
}
#pragma mark date time

-(void) setupDateObjects
{
    self.destinationDateFormat = [[NSDateFormatter alloc] init];
    [self.destinationDateFormat setLocale:[NSLocale currentLocale]];
    [self.destinationDateFormat setDoesRelativeDateFormatting:YES];
    
    self.sourceDateFormat = [[NSDateFormatter alloc] init];
    [self.sourceDateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
   
    self.gregorian = [[NSCalendar alloc]
                             initWithCalendarIdentifier:NSGregorianCalendar];
    
    NSDate* now =[NSDate date];
    self.thisday =[self.gregorian components:NSDayCalendarUnit fromDate:now].day;
    self.thismonth =[self.gregorian components:NSMonthCalendarUnit fromDate:now].month;
    self.thisyear =[self.gregorian components:NSYearCalendarUnit fromDate:now].year;

    
}

-(NSString*) currentGMTTime
{
    NSDate* sourceDate =[NSDate date];
    
    NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
    NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
    NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
    NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
    NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
    
    return [self.sourceDateFormat stringFromDate:destinationDate];
}

-(NSString*) formattedDateWithSource:(NSString*) sourceDateString
{
    NSString* dateString;
    
    if(sourceDateString!=nil)
    {
        
        NSDate* sourceDate=[self.sourceDateFormat dateFromString:sourceDateString];
        
        NSTimeZone* sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        NSTimeZone* destinationTimeZone = [NSTimeZone systemTimeZone];
        NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
        NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
        NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
        NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
        
        NSInteger msgday =[self.gregorian components:NSDayCalendarUnit fromDate:destinationDate].day;
        NSInteger msgmonth=[self.gregorian components:NSMonthCalendarUnit fromDate:destinationDate].month;
        NSInteger msgyear =[self.gregorian components:NSYearCalendarUnit fromDate:destinationDate].year;
        
        if ((self.thisday!=msgday) || (self.thismonth!=msgmonth) || (self.thisyear!=msgyear))
        {
    
            //no more need for seconds
            [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
            
            // note: if it isnt the same day we want to show the full  day
            [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
            
            //cache date
           
        }
        else
        {
            //today just show time
            [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
            [self.destinationDateFormat setTimeStyle:NSDateFormatterMediumStyle];
        }
      
        dateString = [ self.destinationDateFormat stringFromDate:destinationDate];
    }
    
    return dateString;
}


#pragma mark tableview datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    int toReturn=0;
    
    switch (section) {
        case 0:
        {
            toReturn=[_messagelist count];
            break;
        }
        default:
            break;
    }
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLChatCell* cell;
    NSDictionary* row= [_messagelist objectAtIndex:indexPath.row];
    
    if([[row objectForKey:@"af"] isEqualToString:_jid])
    {
        cell=[tableView dequeueReusableCellWithIdentifier:@"ChatCellOut"];
    }
    else
    {
        cell=[tableView dequeueReusableCellWithIdentifier:@"ChatCellIn"];
    }
    
    if(!cell)
    {
        cell =[[MLChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ChatCell" andMuc:_isMUC];
    }
    
    if(_isMUC)
    {
        cell.showName=YES;
        cell.name.text=[row objectForKey:@"af"];
    }
    
    
    cell.date.text= [self formattedDateWithSource:[row objectForKey:@"thetime"]];
    
    NSString* lowerCase= [[row objectForKey:@"message"] lowercaseString];
    NSRange pos = [lowerCase rangeOfString:@"http://"];
    if(pos.location==NSNotFound)
        pos=[lowerCase rangeOfString:@"https://"];
    
    NSRange pos2;
    if(pos.location!=NSNotFound)
    {
        NSString* urlString =[[row objectForKey:@"message"] substringFromIndex:pos.location];
        pos2= [urlString rangeOfString:@" "];
        if(pos2.location!=NSNotFound)
            urlString=[urlString substringToIndex:pos2.location];
        
        cell.link=urlString;
    }
    else
    {
        cell.link=nil;
    }
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"6.0"))
    {
        if(pos.location!=NSNotFound)
        {
            NSDictionary *underlineAttribute = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
            NSAttributedString* underlined = [[NSAttributedString alloc] initWithString:cell.link
                                                                             attributes:underlineAttribute];
            
            
            if ([underlined length]==[[row objectForKey:@"message"] length])
            {
                cell.textLabel.attributedText=underlined;
            }
            else
            {
                NSMutableAttributedString* stitchedString  = [[NSMutableAttributedString alloc] init];
                [stitchedString appendAttributedString:
                 [[NSAttributedString alloc] initWithString:[[row objectForKey:@"message"] substringToIndex:pos.location] attributes:nil]];
                [stitchedString appendAttributedString:underlined];
                if(pos2.location!=NSNotFound)
                {
                    NSString* remainder = [[row objectForKey:@"message"] substringFromIndex:pos.location+[underlined length]];
                    [stitchedString appendAttributedString:[[NSAttributedString alloc] initWithString:remainder attributes:nil]];
                }
                cell.textLabel.attributedText=stitchedString;
            }
            
        }
        else
        {
            cell.textLabel.text =[row objectForKey:@"message"];
        }
    }
    else
    {
        cell.textLabel.text =[row objectForKey:@"message"];
    }
    
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    
    if([[row objectForKey:@"af"] isEqualToString:_jid])
    {
        cell.outBound=YES;
    }
    
    return cell;
}

#pragma mark tableview delegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* row=[_messagelist objectAtIndex:indexPath.row];
    CGFloat height= [MLChatCell heightForText:[row objectForKey:@"message"] inWidth:tableView.frame.size.width-20];
    height+=kNameLabelHeight;
    
    return height;
    
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES; // for now
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}


-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [chatInput resignFirstResponder];
    
    MLChatCell* cell = (MLChatCell*)[tableView cellForRowAtIndexPath:indexPath];
    if(cell.link)
    {
        [cell openlink:self];
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary* message= [_messagelist objectAtIndex:indexPath.row];
        
        DDLogVerbose(@"%@", message);
        
        if([message objectForKey:@"message_history_id"])
        {
            [[DataLayer sharedInstance] deleteMessageHistory:[NSString stringWithFormat:@"%@",[message objectForKey:@"message_history_id"]]];
        }
        else if ([message objectForKey:@"message_id"])
        {
            [[DataLayer sharedInstance] deleteMessage:[NSString stringWithFormat:@"%@",[message objectForKey:@"message_id"]]];
        }
        else
        {
            return;
        }
        [_messagelist removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
        
        
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    return YES;
}

//dummy function needed to remove warnign
-(void) openlink: (id) sender {
    
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    
}


# pragma mark Textview delegeate functions
- (void)textFieldDidBeginEditing:(UITextField *)textField
{
}

-(void) keyboardDidHide: (NSNotification *)notif
{
	DDLogVerbose(@"kbd did hide ");
}

-(void) keyboardWillHide:(NSNotification *) notification
{
    
    NSTimeInterval animationDuration =[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	[UIView animateWithDuration:animationDuration
                     animations:^{
                         self.view.frame =oldFrame;
                         if([_messagelist count]>0)
                         {
                             NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
                             if(![_messageTable.indexPathsForVisibleRows containsObject:path1])
                             {
                                 
                                 [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
                             }
                         }
                         
                     } completion:^(BOOL finished) {
                         
                         
                     }
     ];
    
    _keyboardVisible=NO;
	DDLogVerbose(@"kbd will hide scroll: %f", oldFrame.size.height);
}

-(void) keyboardDidShow:(NSNotification *) note
{
    
    
}

-(void) keyboardWillShow:(NSNotification *) notification
{
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
   // CGSize keyboardNewPos = [[[notification userInfo] objectForKey:] CGRectValue].size;
    
    CGRect r;
	
    //chiense keybaord might call this multiple times ony set for inital
    if(!_keyboardVisible) {
        oldFrame=self.view.frame;
    }
    _keyboardVisible=YES;
    r=oldFrame;
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    
    if(orientation==UIInterfaceOrientationLandscapeLeft|| orientation==UIInterfaceOrientationLandscapeRight)
    {
        r.size.height -= keyboardSize.width;
    }
    else {
        r.size.height -= keyboardSize.height;
    }
    
    NSTimeInterval animationDuration =[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:animationDuration
                     animations:^{
                         self.view.frame =r;
                         
                     } completion:^(BOOL finished) {
                         
                         [self scrollToBottom];
                     }
     ];
	
}

- (void)growingTextView:(HPGrowingTextView *)growingTextView willChangeHeight:(float)height
{
    float diff = (growingTextView.frame.size.height - height);
    
	CGRect r = containerView.frame;
    r.size.height -= diff;
    r.origin.y += diff;
	containerView.frame = r;
}




/*
 #pragma mark HTML generation
 
 -(NSString*) emoticonsHTML:(NSString*) message
 {
 NSMutableString* body=[[NSMutableString alloc] initWithString: message];
 
 //fix % issue
 //[body replaceOccurrencesOfString:@"%" withString:@"%%"
 //							  options:NSCaseInsensitiveSearch
 //								range:NSMakeRange(0, [body length])];
 
 
 
 //only do search if there an emoticon
 NSRange pos = [message rangeOfString:@":"];
 NSRange pos2 = [message rangeOfString:@";"];
 if((pos.location!=NSNotFound) ||
 (pos2.location!=NSNotFound))
 {
 
 [body replaceOccurrencesOfString:@":)"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Smile.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 [body replaceOccurrencesOfString:@":-)"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Smile.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":D"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Grin.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 [body replaceOccurrencesOfString:@":-D"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Grin.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":O"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Surprised.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 [body replaceOccurrencesOfString:@":-O"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Surprised.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 
 
 [body replaceOccurrencesOfString:@":*"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Kiss.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 [body replaceOccurrencesOfString:@":-*"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Kiss.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 
 
 
 [body replaceOccurrencesOfString:@":("
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sad.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":-("
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sad.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":\'("
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Crying.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":\'-("
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Crying.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 
 
 [body replaceOccurrencesOfString:@";-)"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Wink.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@";)"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Wink.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 
 [body replaceOccurrencesOfString:@":-/"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":/"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 
 [body replaceOccurrencesOfString:@":-\\"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":\\"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":-p"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Tongue.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 [body replaceOccurrencesOfString:@":p"
 withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Tongue.png>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 //changes to avoid having :// as in  http:// turned into an emoticon
 [body replaceOccurrencesOfString:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>/"
 withString:[NSString stringWithFormat:@"://"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 }
 
 //handle carriage return
 [body replaceOccurrencesOfString:@"\n"
 withString:[NSString stringWithFormat:@"<br>"]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 //this is link handling text
 
 int linkstart=0;
 int linkend=0;
 
 NSString* linktext;
 NSRange urlpos;
 NSRange urlpos2;
 bool hasHttp=true;
 bool hasHttps=true;
 
 //find http
 urlpos=[body rangeOfString:@"http://" options:NSCaseInsensitiveSearch];
 if(urlpos.location==NSNotFound)
 {
 hasHttp=false;
 //find  www
 urlpos=[body rangeOfString:@"www." options:NSCaseInsensitiveSearch];
 }
 
 //find http
 urlpos2=[body rangeOfString:@"https://" options:NSCaseInsensitiveSearch];
 if(urlpos2.location==NSNotFound)
 {
 hasHttps=false;
 //find  www
 //urlpos=[body rangeOfString:@"www." options:NSCaseInsensitiveSearch];
 }
 
 if((hasHttp==true) || (hasHttps==true))
 {
 // look for <a already there
 NSRange ahrefPos=[body rangeOfString:@"<a" options:NSCaseInsensitiveSearch];
 if(ahrefPos.location==NSNotFound)
 {
 
 //get length
 if(urlpos.location!=NSNotFound)
 linkstart=urlpos.location;
 else
 if(urlpos2.location!=NSNotFound)
 linkstart=urlpos2.location;
 
 //find space after that
 urlpos=[body rangeOfString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(linkstart, [body length]-linkstart)];
 if(urlpos.location==NSNotFound)
 {
 linkend=[body length];
 } else linkend=urlpos.location;
 
 
 linktext=[body substringWithRange:NSMakeRange(linkstart, linkend-linkstart)];
 
 
 // replace linktext with <a href=linktext> linktext  </a>
 
 
 
 if((hasHttp==true) || (hasHttps==true))
 [body replaceOccurrencesOfString:linktext
 withString:[NSString stringWithFormat:@"<a href=%@> %@ </a>",linktext, linktext]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 else
 [body replaceOccurrencesOfString:linktext
 withString:[NSString stringWithFormat:@"<a href=http://%@> %@ </a>",linktext, linktext]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [body length])];
 
 
 }
 }
 return body;
 
 }
 
 -(NSString*) makeMessageHTMLfrom:(NSString*) from withMessage:(NSString*) themessage andTime:(NSString*) time isLive:(BOOL) liveChat
 {
 
 if([from isEqualToString:self.jid])
 {
 
 NSMutableString* tmpout;
 
 // commneted out because of the occasional bug
 //       if([from isEqualToString:lastFrom])
 //			tmpout=[NSMutableString stringWithString:outNextHTML];
 //		else
 
 {
 //new block
 lastDiv=[NSString stringWithFormat:@"insert%@",dateString];
 
 tmpout=[NSMutableString stringWithString:outHTML];
 if(liveChat==true)
 [tmpout replaceOccurrencesOfString:@"insert"
 withString:lastDiv
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpout length])];
 }
 
 
 
 
 [tmpout replaceOccurrencesOfString:@"%message%"
 withString:[self emoticonsHTML:themessage]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpout length])];
 
 
 
 
 
 [tmpout replaceOccurrencesOfString:@"%time%"
 withString:dateString
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpout length])];
 
 return tmpout;
 
 }
 else
 {
 NSMutableString* tmpin;
 
 //commented out because of bugs
 //if([from isEqualToString:lastFrom])
 //	tmpin=[NSMutableString stringWithString:inNextHTML];
 //else
 {
 //new block
 lastDiv=[NSString stringWithFormat:@"insert%@",dateString];
 
 tmpin=[NSMutableString stringWithString:inHTML];
 
 if(liveChat==true)
 [tmpin replaceOccurrencesOfString:@"insert"
 withString:lastDiv
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpin length])];
 }
 
 if(groupchat==true) //we want individualized names
 {
 
 [tmpin replaceOccurrencesOfString:@"%sender%"
 withString:from
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpin length])];
 }
 
 [tmpin replaceOccurrencesOfString:@"%message%"
 withString:[self emoticonsHTML:themessage]
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpin length])];
 
 [tmpin replaceOccurrencesOfString:@"%time%"
 withString:dateString
 options:NSCaseInsensitiveSearch
 range:NSMakeRange(0, [tmpin length])];
 
 ;
 return tmpin;
 
 }
 }
 */

@end
