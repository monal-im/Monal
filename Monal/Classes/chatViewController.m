//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chatViewController.h"

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
     
	
    UIImage *rawEntryBackground = [UIImage imageNamed:@"MessageEntryInputField.png"];
    UIImage *entryBackground = [rawEntryBackground stretchableImageWithLeftCapWidth:13 topCapHeight:22];
    UIImageView *entryImageView = [[UIImageView alloc] initWithImage:entryBackground];
    entryImageView.frame = CGRectMake(5, 0, self.view.frame.size.width-72, 40);
    entryImageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    
    UIImage *rawBackground = [UIImage imageNamed:@"MessageEntryBackground.png"];
    UIImage *background = [rawBackground stretchableImageWithLeftCapWidth:13 topCapHeight:22];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:background];
    imageView.frame = CGRectMake(0, 0, containerView.frame.size.width, containerView.frame.size.height);
    imageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    
    chatInput.autoresizingMask = UIViewAutoresizingFlexibleWidth;
   
    // view hierachy
    
    [containerView addSubview:imageView];
    [containerView addSubview:chatInput];
    [containerView addSubview:entryImageView];
    
    UIImage *sendBtnBackground = [[UIImage imageNamed:@"MessageEntrySendButton.png"] stretchableImageWithLeftCapWidth:13 topCapHeight:0];
    UIImage *selectedSendBtnBackground = [[UIImage imageNamed:@"MessageEntrySendButton.png"] stretchableImageWithLeftCapWidth:13 topCapHeight:0];
    
	UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	doneBtn.frame = CGRectMake(containerView.frame.size.width - 69, 8, 63, 27);
    doneBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
	[doneBtn setTitle:@"Send" forState:UIControlStateNormal];
    
    [doneBtn setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
    doneBtn.titleLabel.shadowOffset = CGSizeMake (0.0, -1.0);
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18.0f];
    
    [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[doneBtn addTarget:self action:@selector(resignTextView) forControlEvents:UIControlEventTouchUpInside];
    [doneBtn setBackgroundImage:sendBtnBackground forState:UIControlStateNormal];
    [doneBtn setBackgroundImage:selectedSendBtnBackground forState:UIControlStateSelected];
	[containerView addSubview:doneBtn];
    
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
    _topName.textColor=[UIColor whiteColor];
    _topName.backgroundColor=[UIColor clearColor];
    
    [_topBarView addSubview:_topIcon];
    [_topBarView addSubview:_topName];
    
    self.navigationItem.titleView=_topBarView;
    
}

-(id) initWithContact:(NSDictionary*) contact
{
    self=[super init];
    _contact=contact;
    // handle messages to view someuser
    _contactName=[contact objectForKey:@"buddy_name"];
	_contactFullName=[contact objectForKey:@"full_name"];;
    self.accountNo=[NSString stringWithFormat:@"%d",[[contact objectForKey:@"account_id"] integerValue]];
    self.hidesBottomBarWhenPushed=YES;
    
#warning this should be smarter...
    NSArray* accountVals =[[DataLayer sharedInstance] accountVals:self.accountNo];
    self.jid=[NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:@"username"], [[accountVals objectAtIndex:0] objectForKey:@"domain"]];
        
    return self;

}


#pragma mark view lifecycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self makeView];
    

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
       [nc addObserver:self selector:@selector(handleTap) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardDidShow:) name: UIKeyboardDidShowNotification object:nil];

    self.hidesBottomBarWhenPushed=YES;
    _messageTable.delegate=self;
    _messageTable.dataSource=self;
    self.view.autoresizesSubviews=true;
    _messageTable.separatorColor=[UIColor whiteColor];
    
    _tap =[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    [_messageTable addGestureRecognizer:_tap];
    
  
}

-(void)viewWillAppear:(BOOL)animated
{
    
    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
    [MLNotificationManager sharedInstance].currentContact=self.contactName;
    
    _messagelist =[[DataLayer sharedInstance] messageHistory:_contactName forAccount: _accountNo];
    int unread =[[DataLayer sharedInstance] countUserUnreadMessages:_contactName forAccount: _accountNo];
    
    if([_messagelist count]>0)
    {
     NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
        if(![_messageTable.indexPathsForVisibleRows containsObject:path1])
        {
            
            [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        }
    }
    
    if(unread==0)
        _firstmsg=YES;
    
    if(![_contactFullName isEqualToString:@"(null)"])
       {
           _topName.text=_contactFullName;
       }
    else
        _topName.text=_contactName;
    
    _topIcon.image=[[MLImageManager sharedInstance] getIconForContact:_contactName andAccount:_accountNo];
    
}

-(void) viewWillDisappear:(BOOL)animated
{
    [MLNotificationManager sharedInstance].currentAccountNo=nil;
    [MLNotificationManager sharedInstance].currentContact=nil;
    
    [[DataLayer sharedInstance] markAsReadBuddy:self.contactName forAccount:self.accountNo];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


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

#pragma mark gestures
-(void) handleTap
{
    [chatInput resignFirstResponder];
}


#pragma mark textview

-(void)resignTextView
{
    if(([chatInput text]!=nil) && (![[chatInput text] isEqualToString:@""]) )
    {
        debug_NSLog(@"Sending message");
        [[MLXMPPManager sharedInstance] sendMessage:[chatInput text] toContact:_contactName fromAccount:_accountNo withCompletionHandler:nil];
        [self addMessageto:_contactName withMessage:[chatInput text]];
        
    }
    [chatInput setText:@""];
}


#pragma mark message signals

-(void)refreshDisplay
{
}


//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message
{
	
	if([[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:_accountNo withMessage:message actuallyFrom:self.jid ])
	{
		debug_NSLog(@"added message");
        
		if(groupchat!=true) //  message will come back
		{
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                               NSDictionary* userInfo = @{@"af": self.jid,
                                                          @"message": message ,
                                                          @"thetime": @""  };
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
		debug_NSLog(@"failed to add message");
	
	// make sure its in active
	if(_firstmsg==YES)
	{
        [[DataLayer sharedInstance] addActiveBuddies:to forAccount:_accountNo];
        _firstmsg=NO;
	}
	

    
}

-(void) handleNewMessage:(NSNotification *)notification
{
    debug_NSLog(@"chat view got new message notice %@", notification.userInfo);
    
    if([[notification.userInfo objectForKey:@"accountNo"] isEqualToString:_accountNo]
      && [[notification.userInfo objectForKey:@"from"] isEqualToString:_contactName]
       )
    {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           NSDictionary* userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                                      @"message": [notification.userInfo objectForKey:@"messageText"],
                                                      @"thetime": @"" };
                           [_messagelist addObject:userInfo];
                           
                           [_messageTable beginUpdates];
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
                           [_messageTable insertRowsAtIndexPaths:@[path1]
                                                 withRowAnimation:UITableViewRowAnimationTop];
                           [_messageTable endUpdates];
                           
                            [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:YES];
                           
                       });
    }
}


#pragma mark MUC display elements
-(void) popContacts
{
    debug_NSLog(@"pop out contacts");
    
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


/*
#pragma mark gestures
//handle swipe
- (void)swipeDetected:(UISwipeGestureRecognizer *)recognizer {
     debug_NSLog(@"pages was   %d", pages.currentPage);
    
    if(recognizer.direction==UISwipeGestureRecognizerDirectionRight)
    {
        debug_NSLog(@"swiped  right in chat"); 
       
        if(pages.currentPage==0) pages.currentPage=pages.numberOfPages-1; 
        else
             pages.currentPage--; 
    }
        else
             if(recognizer.direction==UISwipeGestureRecognizerDirectionLeft)
             {
                 debug_NSLog(@"swiped   left in chat "); 
                 
                 if(pages.currentPage==pages.numberOfPages-1) pages.currentPage=0; 
                else
                 pages.currentPage++; 
                
             }
            
    
    debug_NSLog(@"pages now set to %d", pages.currentPage);
    [pages updateCurrentPageDisplay];
    
    //dont keep reloading if only one page
    if(pages.numberOfPages!=0)
    {
    
//    [self show:[[activeChats objectAtIndex:pages.currentPage] objectAtIndex:0]
//              :[[activeChats objectAtIndex:pages.currentPage] objectAtIndex:2] :navController];
    }
    
}

*/

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
        cell =[[MLChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ChatCell"];
    }
   
    cell.textLabel.text =[row objectForKey:@"message"];
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
    return [MLChatCell heightForText:[row objectForKey:@"message"] inWidth:tableView.frame.size.width-20];
    
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES; // for now
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [chatInput resignFirstResponder];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary* message= [_messagelist objectAtIndex:indexPath.row];
        
        debug_NSLog(@"%@", message); 
        
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


# pragma mark Textview delegeate functions
- (void)textFieldDidBeginEditing:(UITextField *)textField
{
}

-(void) keyboardDidHide: (NSNotification *)notif 
{
	debug_NSLog(@"kbd did hide "); 
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

    
	debug_NSLog(@"kbd will hide scroll: %f", oldFrame.size.height);
}

-(void) keyboardDidShow:(NSNotification *) note
{
    

}

-(void) keyboardWillShow:(NSNotification *) notification
{
   
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    CGRect r;
	r=self.view.frame;
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;

    if(orientation==UIInterfaceOrientationLandscapeLeft|| orientation==UIInterfaceOrientationLandscapeRight)
    {
        r.size.height -= keyboardSize.width;
    }
    else
    r.size.height -= keyboardSize.height;
	oldFrame=self.view.frame;
    
    NSTimeInterval animationDuration =[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:animationDuration
                     animations:^{
                         	self.view.frame =r;
                         
                     } completion:^(BOOL finished) {
                         
                         if([_messagelist count]>0)
                         {
                             NSIndexPath *path1 = [NSIndexPath indexPathForRow:[_messagelist count]-1  inSection:0];
                             if(![_messageTable.indexPathsForVisibleRows containsObject:path1])
                             {
                                 
                                 [_messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
                             }
                         }
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

	NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"HH:mm:ss"];
	
	
	//strip html from message to prevent XSS
//	NSString* message=[tools flattenHTML:themessage trimWhiteSpace:true];
//	
	NSString *dateString;
	if(time!=nil)
	{
		NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        
        
	NSDate* sourceDate=[formatter dateFromString:time];

	NSTimeZone* sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
	NSTimeZone* destinationTimeZone = [NSTimeZone systemTimeZone];
		
	//	debug_NSLog(@"system timezone: %@", [destinationTimeZone  name]); 
	
	NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
	NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
	NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
	
	NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
	
        
        NSDateFormatter* tmpformatter= [[NSDateFormatter alloc] init];
        
        [tmpformatter setDateFormat:@"yyyy"];
        int thisyear = [[tmpformatter stringFromDate:[NSDate date]] intValue];
           int msgyear = [[tmpformatter stringFromDate:sourceDate] intValue];
        
        [tmpformatter setDateFormat:@"MM"];
        int thismonth = [[tmpformatter stringFromDate:[NSDate date]] intValue];
           int msgmonth = [[tmpformatter stringFromDate:sourceDate] intValue];
        
        [tmpformatter setDateFormat:@"dd"];
        int thisday = [[tmpformatter stringFromDate:[NSDate date]] intValue];
           int msgday = [[tmpformatter stringFromDate:sourceDate] intValue];
        
        
    if ((thisday!=msgday) || (thismonth!=msgmonth) || (thisyear!=msgyear))
        {
        
	// note: if it isnt the same day we want to show the full  day
	 [formatter setDateStyle: kCFDateFormatterMediumStyle];
        }
        
        [formatter setTimeStyle: kCFDateFormatterMediumStyle];
        [formatter setLocale:[NSLocale currentLocale] ];
        
	dateString = [formatter stringFromDate:destinationDate];
	}
	else
	{
        [dateFormatter setLocale:[NSLocale currentLocale] ];
         [dateFormatter setTimeStyle: kCFDateFormatterMediumStyle];
		dateString =  [dateFormatter stringFromDate:[NSDate date]];
	}
	
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
