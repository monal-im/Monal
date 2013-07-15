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
	
   
    chatView =[[UIWebView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height-40-20)];
    
    pages = [[UIPageControl alloc] init]; 
    pages.frame=CGRectMake(0, self.view.frame.size.height - 40-20, self.view.frame.size.width, 20);
    
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
    pages.backgroundColor = [UIColor colorWithRed:.4 green:0.435 blue:0.498 alpha:1];
    
    pages.hidesForSinglePage=false; 
    pages.numberOfPages=0; 
    pages.currentPage=0; 
   
    
    [self.view addSubview:chatView];
    [self.view addSubview:pages];
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
    chatView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    pages.autoresizingMask= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    UISwipeGestureRecognizer* swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDetected:)];
    [swipe setDirection:(UISwipeGestureRecognizerDirectionRight )]; 
    [self.view addGestureRecognizer:swipe]; 
    
    UISwipeGestureRecognizer* swipe2 = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDetected:)];
    [swipe2 setDirection:( UISwipeGestureRecognizerDirectionLeft)]; 
    [self.view addGestureRecognizer:swipe2];
 
    chatInput.delegate=self;
}

-(id) initWithContact:(NSDictionary*) contact
{
    
    self=[super init];
    self.hidesBottomBarWhenPushed=YES;
    [self makeView];
    chatView.delegate=self;
	
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardDidShow:) name: UIKeyboardDidShowNotification object:nil];
   
    
    // handle messages to view someuser
    
	buddyIcon=nil;
	myIcon=nil; 
	HTMLPage=nil; 
	inHTML=nil; 
	outHTML=nil;
	
	_buddyName=[contact objectForKey:@"buddy_name"];
	buddyFullName=nil; 
	
	inNextHTML=nil; 
	outNextHTML=nil;
	
	lastFrom =nil; 
	lastDiv=nil; 
	
	webroot=[NSString stringWithFormat:@"%@/Themes/MonalStockholm/", [[NSBundle mainBundle] resourcePath]];
	NSError* error;
	topHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/top.html", [[NSBundle mainBundle] resourcePath]] encoding:NSUTF8StringEncoding error:&error];
	
	bottomHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/bottom.html", [[NSBundle mainBundle] resourcePath]] encoding:NSUTF8StringEncoding error:&error];

    [chatView loadHTMLString:topHTML  baseURL:[NSURL fileURLWithPath:webroot]];
	
	self.view.autoresizesSubviews=true; 

    
    self.accountNo=[NSString stringWithFormat:@"%d",[[contact objectForKey:@"account_id"] integerValue]];
    
    NSArray* accountVals =[[DataLayer sharedInstance] accountVals:self.accountNo];
    self.jid=[NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:@"username"], [[accountVals objectAtIndex:0] objectForKey:@"domain"]];
    
    return self;

}


#pragma mark view lifecycle

-(void)viewWillAppear:(BOOL)animated
{
    [self show];
}

-(void) viewDidLoad
{
        [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)resignTextView
{
    
  
    [chatInput.internalTextView resignFirstResponder];
    [chatInput.internalTextView becomeFirstResponder];
    
    if(([chatInput text]!=nil) && (![[chatInput text] isEqualToString:@""]) )
    {
        debug_NSLog(@"Sending message");
        // this should call the xmpp message
       // [NSThread detachNewThreadSelector:@selector(handleInput:) toTarget:self withObject:[chatInput text]];
        
        [[MLXMPPManager sharedInstance] sendMessage:[chatInput text] toContact:_buddyName fromAccount:_accountNo withCompletionHandler:nil];
        [self addMessageto:_buddyName withMessage:[chatInput text]];
        
    }
    
    [chatInput setText:@""];
    
    /* if([machine hasPrefix:@"iPad"] )
     {
     // no need to dismiss on every message for the ipad.
     }
     else
     [chatInput resignFirstResponder];*/
}


-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	
	/*UIApplication* app= [UIApplication sharedApplication];
	 
	 if((interfaceOrientation==UIInterfaceOrientationPortrait) ||(interfaceOrientation==UIInterfaceOrientationPortraitUpsideDown))
	 {
	 
	 [app setStatusBarHidden:NO animated:NO];
	 [self.navigationController setNavigationBarHidden:NO animated:NO];
	 debug_NSLog(@"Becoming Portrait.. "); 
	 
	 
	 
	 }else if((interfaceOrientation==UIInterfaceOrientationLandscapeLeft) ||(interfaceOrientation==UIInterfaceOrientationLandscapeRight))
	 
	 {
	 
	 
	 // landscape
	 [app setStatusBarHidden:YES animated:NO];
	 [self.navigationController setNavigationBarHidden:YES animated:NO];
	 debug_NSLog(@"Becoming Landscape.. "); 
	 
	 }*/
	[chatInput resignFirstResponder];
	
	
	return YES;
}


- (void)viewWillDisappear:(BOOL)animated 
{
	debug_NSLog(@"chat view will hide");
		[chatInput resignFirstResponder];
}

- (void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"chat view did hide"); 
	//[chatView stopLoading]; 
	
	dispatch_async(dispatch_get_main_queue(), ^{
        
        [chatView stopLoading];
    });
    
	
//    if(popOverController!=nil)
//	[popOverController dismissPopoverAnimated:true]; 
//	
//	
	
	HTMLPage =nil; 
	inHTML =nil;
	outHTML  =nil;

	
	lastFrom =nil; 
	lastDiv=nil;
	

	/*if(thelist!=nil) 
	{
		[thelist release];
		thelist=nil;
	}*/
	
	
	lastuser=_buddyName;
}

#pragma mark message signals

-(void) handleNewMessage:(NSNotification *)notification
{
    debug_NSLog(@"chat view got new message notice %@", notification.userInfo);
    
    if([[notification.userInfo objectForKey:@"accountNo"] isEqualToString:_accountNo]
      && [[notification.userInfo objectForKey:@"from"] isEqualToString:_buddyName]
       )
    {
        [self signalNewMessages];
    }
}


//this gets called if the currently chatting user went offline, online or away, back etc
-(void) signalStatus
//{
//	
//	if(groupchat==true) return; // doesnt parse names right at the moment
//	
//	
//	
//	debug_NSLog(@"status signal");
//	if([state isEqualToString:@""]) 
//	{
//		if(wasaway==true)
//	{
//		state=[NSString stringWithString:@"Available"];
//		wasaway=false;
//	}
//		else
//		{
//			; 
//			return; 
//		}
//	}
//	else
//	{
//		if(wasaway==false)
//		{
//			
//			wasaway=true;
//		}
//		else
//		{
//			; 
//			return; 
//		}
//	}
//	
//	NSString* statusmessage; 
//	
//	
//	if(buddyFullName!=nil)
//	{
//		
//		statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyFullName, state];
//	}
//	statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyName, state];
//	
//	/*NSMutableString* messageHTML= [NSMutableString stringWithString:statusHTML];
//	
//	
//		[messageHTML replaceOccurrencesOfString:@"%message%"
//									withString:statusmessage
//									   options:NSCaseInsensitiveSearch
//										 range:NSMakeRange(0, [messageHTML length])];
//	
//	*/
//	
//	
//	lastFrom=	@"";
//	
//	NSString* jsstring= [NSString stringWithFormat:@"InsertMessage('%@');",statusmessage ]; 
//	
//
//  dispatch_async(dispatch_get_main_queue(), ^{
//        
//        [chatView stringByEvaluatingJavaScriptFromString:jsstring];
//    });
//}
{}

-(void) signalOffline
//{
//	if(groupchat==true) return; // doesnt parse names right at the moment
//	
//	
//	debug_NSLog(@"offline signal"); 
//	NSString* state=@"";
//	int count=[db isBuddyOnline:buddyName: accountno];
//	if(count>0) 
//	{if(wasoffline==true)
//		{
//		state=@"Online";
//			wasoffline=false; 
//		}
//		else
//		{
//			; 
//			return; 
//		}
//	}
//	else 
//		
//	{
//		if(wasoffline==false)
//		{
//		state=@"Offline";
//			wasoffline=true; 
//		}
//		else
//		{
//			; 
//			return;
//		}
//	}	
//	
//	
//	NSString* statusmessage; 
//	
//	
//	if(buddyFullName!=nil)
//	{
//		statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyFullName, state];
//	}
//	statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyName, state];
//	
//
//	
//	NSString* jsstring= [NSString stringWithFormat:@"InsertMessage('%@');",statusmessage ]; 
//	
//	
//	
//    dispatch_async(dispatch_get_main_queue(), ^{
//        
//        [chatView stringByEvaluatingJavaScriptFromString:jsstring];
//    });
//}
{}

-(void) signalNewMessages
{

		//populate the list
		//[thelist release];
		NSArray* thelist =[[DataLayer sharedInstance] unreadMessagesForBuddy:_buddyName: _accountNo] ;

        if([thelist count]==0)
		{
			//multi threaded sanity checkf
			debug_NSLog(@"got 0 new messages");
			return;
		}
		else
        {
		if([[DataLayer sharedInstance] markAsRead:_buddyName:_accountNo])
		{
			debug_NSLog(@"marked new messages as read");
		}
		else
			debug_NSLog(@"could not mark new messages as read");
        }
	
		int msgcount=0; 
		 
		while(msgcount<[thelist count])
		{
			NSDictionary* therow=[thelist objectAtIndex:msgcount];
		
		if(groupchat==true)
		{
			inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
			
			unichar asciiChar = 10; 
			NSString *newline = [NSString stringWithCharacters:&asciiChar length:1];
		
			
			
			[inHTML replaceOccurrencesOfString:newline
									withString:@""
									   options:NSCaseInsensitiveSearch
										 range:NSMakeRange(0, [inHTML length])];
		
			
			
				[inHTML replaceOccurrencesOfString:@"%sender%"
										withString:[therow objectForKey:@"af"]
										   options:NSCaseInsensitiveSearch
											 range:NSMakeRange(0, [inHTML length])];
			
			
			[inHTML replaceOccurrencesOfString:@"%userIconPath%"
									withString:buddyIcon
									   options:NSCaseInsensitiveSearch
										 range:NSMakeRange(0, [inHTML length])];
			
	
			
			
		}
		
		
		NSString* thejsstring; 
		
        NSString* msg= [[therow objectForKey:@"message"] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] ;
         NSString* messageHTML= [self makeMessageHTMLfrom:[therow objectForKey:@"from"] withMessage:[msg stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]  andTime:[therow objectForKey:@"thetime"] isLive:YES];

			
	/*	if(([[lastFrom lowercaseString] isEqualToString:[[therow objectAtIndex:0] lowercaseString]]) &&(groupchat==false))
		{
		
			thejsstring= [NSString stringWithFormat:@"InsertNextMessage('%@','%@');", messagecontent,lastDiv]; 
		}
		else*/
		{
		
			thejsstring= [NSString stringWithFormat:@"InsertMessage('%@');", messageHTML];
	
		}
	/*		NSString* result=[chatView stringByEvaluatingJavaScriptFromString:thejsstring];
		if(result==nil) debug_NSLog(@"new message in js failed "); 
		else debug_NSLog(@"new message in js ok %@", thejsstring); 
	*/
		
		
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [chatView stringByEvaluatingJavaScriptFromString:thejsstring];
            });
            
            debug_NSLog(@"%@",thejsstring);
		
		lastFrom=	[NSString stringWithString:[therow objectForKey:@"af"]];
			
			
			msgcount++; 
		}
		
	
	
	
	;
		
	msgthread=false;
	
}


-(void) showLogDate:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc:(NSString*) date
//{
//	
//	
//    
//    //removeing the input stuff
//	[chatInput resignFirstResponder];
//    containerView.hidden=true;  
//    pages.hidden=true; 
//  
//    [chatView setFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
//    
//    
//
//	
//	buddyName=buddy; 
//	buddyFullName=fullname; 
//	if([buddyFullName isEqualToString:@""])	
//		self.title=buddyName;
//	else
//		self.title=buddyFullName;
//	
//	
//	
//	NSString* machine=[tools machine]; 
//	
//	if([machine hasPrefix:@"iPad"] )
//	{//if ipad..
//		self.hidesBottomBarWhenPushed=false; 
//	}
//	else
//	{
//		//ipone 
//		self.hidesBottomBarWhenPushed=true; 
//	}
//	
//	
//	// dont push it agian ( ipad..but stops crash in genreal)
//	if([vc topViewController]!=self)
//	{
//		[vc pushViewController:self animated:YES];
//	}
//	
//	debug_NSLog(@"show log"); 
//
//
//	
//	
//
//	
//	//populate the list
//	NSArray* thelist =[db messageHistoryDate :buddyName: accountno:date];
//	//[thelist retain];
//	
//	
//	myIcon = [self setIcon: [NSString stringWithFormat:@"%@@%@",myuser,domain]];
//	buddyIcon= [self setIcon: buddy];
//	
//	
//	inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
//	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  
//	
//	/*inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
//	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  
//	*/
//	
//	
//	
//	inNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/NextContent.html", [[NSBundle mainBundle] resourcePath]]]; 
//	outNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/NextContent.html", [[NSBundle mainBundle] resourcePath]]];  
//	
//	
//	
//	
//
//
//	
//	if([buddyFullName isEqualToString:@""])
//		[inHTML replaceOccurrencesOfString:@"%sender%"
//								withString:buddy
//								   options:NSCaseInsensitiveSearch
//									 range:NSMakeRange(0, [inHTML length])];
//	else
//		[inHTML replaceOccurrencesOfString:@"%sender%"
//								withString:buddyFullName
//								   options:NSCaseInsensitiveSearch
//									 range:NSMakeRange(0, [inHTML length])];
//	
//	[outHTML replaceOccurrencesOfString:@"%sender%"
//							 withString:jabber.ownName
//								options:NSCaseInsensitiveSearch
//								  range:NSMakeRange(0, [outHTML length])];
//	
//	[inHTML replaceOccurrencesOfString:@"%userIconPath%"
//							withString:buddyIcon
//							   options:NSCaseInsensitiveSearch
//								 range:NSMakeRange(0, [inHTML length])];
//	
//	[outHTML replaceOccurrencesOfString:@"%userIconPath%"
//							 withString:myIcon
//								options:NSCaseInsensitiveSearch
//								  range:NSMakeRange(0, [outHTML length])];
//	
//	
//	
//	
//	HTMLPage=[self createPage:thelist];
//	
//	
//	
//    dispatch_async(dispatch_get_main_queue(), ^{
//        
//        [chatView  loadHTMLString: HTMLPage baseURL:[NSURL fileURLWithPath:webroot]];
//        
//    });
//	
//	
//	
//	//debug_NSLog(@" HTML LOG: %@", HTMLPage); 
//	;
//	
//}
{}


-(NSString*) setIcon:(NSString*) msguser
{
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	NSString* theimage; 
	//note: default to png  we want to check a table/array to  look  up  what the file name really is...
//	NSString* buddyfile = [NSString stringWithFormat:@"%@/%@.png", iconPath,msguser ];
	
//	debug_NSLog(@"%@",buddyfile);
//	if([fileManager fileExistsAtPath:buddyfile])
//	{
//		
//		theimage= buddyfile;
//		
//	}
//	
//	else
//	{
		//jpg
		
	//	NSString* buddyfile2 = [NSString stringWithFormat:@"%@/%@.jpg", _iconPathmsguser];
//		debug_NSLog(@"%@",buddyfile2);
//		if([fileManager fileExistsAtPath:buddyfile2])
//		{
//			theimage= buddyfile2;
			
//		}
//		else
		{
			theimage= [NSString stringWithFormat:@"%@/noicon.png",[[NSBundle mainBundle] resourcePath]];
		}
		
//	}
//	
	;
	return theimage; 
}



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

//note fullname is overridden and ignored
-(void) show
{
	
    pages.hidden=false; 
    containerView.hidden=false;
    [chatView setFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height-40-20)];

	//query to get pages and position
    activeChats=[[DataLayer sharedInstance] activeBuddies:_accountNo];
    pages.numberOfPages=0;//[activeChats count];
    //set pos
    int dotCounter=0; 
    while(dotCounter<pages.numberOfPages)
    {
    if([_buddyName isEqualToString:[[activeChats objectAtIndex:dotCounter] objectAtIndex:0]])
    {
        pages.currentPage=dotCounter; 
        break;
    }
        dotCounter++;
        
    }
    
   /* if(dotCounter==pages.numberOfPages)
    {
        debug_NSLog(@"unable to find item.. abort show"); 
        return;
    }*/
    
	
	msgthread=false;
	
	firstmsg=true; 
	// replace parts of the string
	
	
//    if(dotCounter<pages.numberOfPages)
//    {
//    
//	buddyFullName=[[activeChats objectAtIndex:dotCounter] objectAtIndex:2]; //doesnt matter what full name is passed we will always check
//    }
//    else 
//        buddyFullName=fullname;
    
    buddyFullName=_buddyName;
    
    
    debug_NSLog(@"id: %@,  full: %@", _buddyName, buddyFullName);
if([buddyFullName isEqualToString:@""])	
	self.title=_buddyName;
	else
		self.title=buddyFullName;
	
//first check.. 
//    if([[DataLayer sharedInstance] isBuddyMuc:buddyFullName:_accountno])
//    {
//        groupchat=true; 
//    }
//    else
    {//fallback
    
	
	NSRange startrange=[_buddyName rangeOfString:@"@conference"
						
										options:NSCaseInsensitiveSearch range:NSMakeRange(0, [_buddyName length])];
	
	
	if (startrange.location!=NSNotFound) 
	{
		groupchat=true; 
	}
	else 
	{

	
	NSRange startrange2=[_buddyName rangeOfString:@"@groupchat"
						
									options:NSCaseInsensitiveSearch range:NSMakeRange(0, [_buddyName length])];
	
	
	if (startrange2.location!=NSNotFound) 
	{
		groupchat=true; 
	}
	else groupchat=false;
	}
	
    }
	
	
	chatInput.hidden=false; 
	//chatInput.editable=true; 
	
	[chatInput setText:@""];

	
	[chatInput setDelegate:self];
	
	
	//mark any messages in from this user as  read
	[[DataLayer sharedInstance] markAsRead:_buddyName :_accountNo];
	
	//populate the list
//	if(thelist!=nil) [thelist release];
	NSArray* thelist =[[DataLayer sharedInstance] messageHistory:_buddyName forAccount: _accountNo];
	//[thelist retain];
	
	//get icons 
	// need a faster methos here..
	
	
	myIcon = [self setIcon: self.jid];
	buddyIcon= [self setIcon: _buddyName];
	
	
	[chatInput resignFirstResponder];
	
	
	inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  

/*	
	inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  
	*/
	
	
	inNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/NextContent.html", [[NSBundle mainBundle] resourcePath]]]; 
	outNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/NextContent.html", [[NSBundle mainBundle] resourcePath]]];  
	
	
	
	
	
	unichar asciiChar = 10; 
	NSString *newline = [NSString stringWithCharacters:&asciiChar length:1];
	
	
	[outNextHTML replaceOccurrencesOfString:newline
							 withString:@""
								options:NSCaseInsensitiveSearch
								  range:NSMakeRange(0, [outNextHTML length])];
	
	[inNextHTML replaceOccurrencesOfString:newline
							 withString:@""
								options:NSCaseInsensitiveSearch
								  range:NSMakeRange(0, [inNextHTML length])];
	
	
	[inHTML replaceOccurrencesOfString:newline
							withString:@""
							   options:NSCaseInsensitiveSearch
								 range:NSMakeRange(0, [inHTML length])];
	
    
    if(groupchat!=true) //we want individualized names
    {
	if([buddyFullName isEqualToString:@""])
	[inHTML replaceOccurrencesOfString:@"%sender%"
							withString:_buddyName
							   options:NSCaseInsensitiveSearch
								 range:NSMakeRange(0, [inHTML length])];
	else
		[inHTML replaceOccurrencesOfString:@"%sender%"
								withString:buddyFullName
								   options:NSCaseInsensitiveSearch
									 range:NSMakeRange(0, [inHTML length])];
	
	}
	
		
	[outHTML replaceOccurrencesOfString:newline
							 withString:@""
								options:NSCaseInsensitiveSearch
								  range:NSMakeRange(0, [outHTML length])];
	
	[outHTML replaceOccurrencesOfString:@"%sender%"
							 withString:self.jid
								options:NSCaseInsensitiveSearch
								  range:NSMakeRange(0, [outHTML length])];
	
	[inHTML replaceOccurrencesOfString:@"%userIconPath%"
							withString:buddyIcon
							   options:NSCaseInsensitiveSearch
								 range:NSMakeRange(0, [inHTML length])];
	
	[outHTML replaceOccurrencesOfString:@"%userIconPath%"
							 withString:myIcon
								options:NSCaseInsensitiveSearch
								  range:NSMakeRange(0, [outHTML length])];
	
	
	HTMLPage=[self createPage:thelist];
	
	
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [chatView  loadHTMLString: HTMLPage baseURL:[NSURL fileURLWithPath:webroot]];
        
    });
	
}

//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message
{
	
	if([[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:_accountNo withMessage:message actuallyFrom:self.jid ])
	{
		debug_NSLog(@"added message"); 
		
		NSString* new_msg =[message stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
		
		//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
		NSString* jsstring; 
	
		if(groupchat!=true) //  message will come back 
		{
	
		
            jsstring= [NSString stringWithFormat:@"InsertMessage('%@');",
                       [self makeMessageHTMLfrom:self.jid
                                     withMessage:[new_msg stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]
                                         andTime:nil isLive:YES]];
                                                                    
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [chatView stringByEvaluatingJavaScriptFromString:jsstring];
                
            });
        
        }
		
	}
	else
		debug_NSLog(@"failed to add message"); 
	
	lastFrom=self.jid;
	
	// make sure its in active
	if(firstmsg==true)
	{
	[[DataLayer sharedInstance] addActiveBuddies:to :_accountNo];
		firstmsg=false; 
	}
	
    msgthread=false;

}

//
//- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
//{
//	
//	debug_NSLog(@"clicked button %d", buttonIndex); 
//	//login or initial error
//	
//		
//		//otherwise 
//		if(buttonIndex==0) 
//		{
//			debug_NSLog(@"do nothing"); 
//
//		}
//		else
//			
//		{
//			debug_NSLog(@"sending reconnect signal"); 
//			
//			// pop the top view controller .. if it was a message send failure then it has to have it on top on all devices
//			[navController popViewControllerAnimated:NO];
//			
//			[[NSNotificationCenter defaultCenter] 
//			 postNotificationName: @"Reconnect" object: self];
//		}
//		
//		 
//	
//	
//	
//	
//	
//	
//	
//	
//	
//	;
//}



//-(void) handleInput:(NSString *)text
//{
//
//	
//    
// 
//	
//    NSMutableString* brtext= [NSMutableString stringWithString:text];
//    /*[brtext replaceOccurrencesOfString:@"\n" withString:@"<br>"
//                                               options:NSCaseInsensitiveSearch
//                                                 range:NSMakeRange(0, [text length])];
//    
//	*/
//    
//			if([jabber message:buddyName:brtext:groupchat])
//			{
//				if(!groupchat)
//				[self addMessage:buddyName:brtext];
//				
//				
//				
//			}
//			else
//			{
//				//reset the text value
//				//[chatInput setText:text];
//				
//				debug_NSLog(@"Message failed to send"); 
//				
//				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Message Send Failed"
//																 message:@"Could not send the message. You may be disconnected."
//																delegate:self cancelButtonTitle:@"Close"
//													   otherButtonTitles:@"Reconnect", nil];
//				[alert show];
//				
//				
//				
//			}
//		
//		
//		
//		
//   
//	
//	
//	;
//	[NSThread exit]; 
//	
//}



//handles the taop on the sliding message notifiction
//-(void) showSignal:(NSNotification*) note
//{
//
//   
//       debug_NSLog(@"show signal reached  chatwin %@", [[note userInfo] objectForKey:@"username"] );
//    
//    //drop extension and . on file name to get username 
//    [self show: [[note userInfo] objectForKey:@"username"] 
//              :@"" :navController];
//
//}
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




# pragma mark Textview delegeate functions 




-(void) keyboardDidHide: (NSNotification *)notif 
{
	debug_NSLog(@"kbd did hide "); 

}

-(void) keyboardWillHide:(NSNotification *) note
{
//     keyboardVisible=NO;
//    if(dontscroll==false)
//    {	
	
	//move down
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.3];
	self.view.frame = oldFrame;
	
	
	
	[UIView commitAnimations];
	
	debug_NSLog(@"kbd will hide scroll: %f", oldFrame.size.height); 

//	}
	
}

-(void) keyboardDidShow:(NSNotification *) note
{
	//if(dontscroll==false)

    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [chatView  stringByEvaluatingJavaScriptFromString:@" document.getElementById('bottom').scrollIntoView(true)"];
        
    });

}

-(void) keyboardWillShow:(NSNotification *) note
{
 //   keyboardVisible=YES;
   // if(dontscroll==false)
    {
	//bigger text view
	//CGRect oldTextFrame= chatInput.frame; 
	//chatInput.frame=CGRectMake(oldTextFrame.origin.x, oldTextFrame.origin.y, oldTextFrame.size.width, oldTextFrame.size.height+30);
	
    
	CGRect r,t;
    [[note.userInfo valueForKey:UIKeyboardBoundsUserInfoKey] getValue: &t];
	r=self.view.frame;
	r.size.height -=  t.size.height;
	
//		NSString* machine=[tools machine]; 
//	if([machine hasPrefix:@"iPad"] )
//	{//if ipad..
//		r.size.height+=50; //tababar
//	}
//	
	
		
	//resizing frame for keyboard movie up
	[UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
	oldFrame=self.view.frame;
	self.view.frame =r; 
	[UIView commitAnimations];
	
	
	debug_NSLog(@"kbd will show : %d  scroll: %f", t.size.height, r.size.height); 
	}
	
	
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
- (void)textViewDidBeginEditing:(UITextView *)textView
{
	
	
	//[chatInput setFont:[UIFont systemFontOfSize:14]];
	
	
}


- (void)textViewDidEndEditing:(UITextView *)textView
{
	
}*/

#pragma mark HTML generation


-(NSString*) emoticonsHTML:(NSString*) message
{
	NSMutableString* body=[[NSMutableString alloc] initWithString: message]; 

	//fix % issue
	/*[body replaceOccurrencesOfString:@"%" withString:@"%%"
							  options:NSCaseInsensitiveSearch
								range:NSMakeRange(0, [body length])];
	
	*/
	
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
        /*if([from isEqualToString:lastFrom])
			tmpout=[NSMutableString stringWithString:outNextHTML]; 
		else
        */
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


//this is the first time creation 
-(NSMutableString*) createPage:(NSArray*)thelist
{
	
	NSMutableString* page=[[NSMutableString alloc] initWithString:topHTML];
	// prefix
	debug_NSLog(@"creating page Called");
	
	//debug_NSLog(@" page top %@", page); 
	// iterate through  list
	int counter=0; 
	int nextInsertPoint=0;
	while(counter<[thelist count])
	{
		NSDictionary* dic =[thelist objectAtIndex:counter];
		NSString* from =[dic objectForKey:@"af"] ;
		NSString* message=[dic objectForKey:@"message"] ;
		NSString* time=[dic objectForKey:@"thetime"];
        //debug_NSLog(@"from %@", from);
		
//		if([from isEqualToString:lastFrom])
//		{
//			// find location of last insert point
//			int insertpoint=0; 
//			
//			if((nextInsertPoint==0) && (groupchat==false))
//			{
//			NSString* target=@"<div id=\"insert\" border=\"1\">"; // this is for stockholm only.. renkoo has another
//			NSRange thepoint=[page rangeOfString:target options:NSBackwardsSearch];
//				if(thepoint.location!=NSNotFound)
//			insertpoint=thepoint.location+thepoint.length;
//				else insertpoint=0; // preventing a segfault really after a sanity check fail
//			}
//			else insertpoint=nextInsertPoint; 
//			
//			
//	
//			
//			NSString* payload=[self makeMessageHTMLfrom:from withMessage:message andTime:time isLive:NO];
//			debug_NSLog(@"%@", payload);
//			[page insertString:payload atIndex:insertpoint];
//			nextInsertPoint=insertpoint+[payload length];
//			
//		}
//			else
			{
				[page appendString:[self makeMessageHTMLfrom:from withMessage:message andTime:time isLive:NO]];
				nextInsertPoint=0;
			}
		
		lastFrom=from;
		
		counter++; 
	}
	//dont append when swingin back into chat
	if(lastFrom!=nil)
	{
		lastFrom=nil; 
	}
	[page appendString:bottomHTML]; 
//	debug_NSLog(@"got page %@", page); 
	//suffix
	;
	return page; 
}



- (void)webViewDidStartLoad:(UIWebView *)webView
{
//	[spinner startAnimating];
	//	chatInput.editable=false;
	
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	debug_NSLog(@"webview finished loading"); 
//	[spinner stopAnimating];
	//chatInput.editable=true;
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	
	if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        NSURL *url = [request URL];
		
		//if([[UIDevice currentDevice].model isEqualToString:@"iPhone"])
		debug_NSLog(@"url : %@", [url absoluteString]); 
		
		//[url scheme] give if file of http type
		
        if (![[url scheme] hasPrefix:@"file"]) {
			//load in safari
            [[UIApplication sharedApplication] openURL:url];

            return NO;
        }
    }

    return YES; 
}




@end
