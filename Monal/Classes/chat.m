//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chat.h"


@implementation chat

@synthesize chatInput;
@synthesize chatView;
@synthesize iconPath; 
@synthesize domain; 
@synthesize tabController;
@synthesize accountno;
@synthesize buddyName;
@synthesize contactList; 


-(void) hideKeyboard
{
	[chatInput resignFirstResponder];
}


-(void) init: (protocol*) jabberIn:(UINavigationController*) nav:(NSString*)username: (DataLayer*) thedb
{
	//navigationController=nav;
	
	// if ipad then bigger input box
	NSString* machine=[tools machine]; 
	if([machine hasPrefix:@"iPad"] )
	{//if ipad..
		[self initWithNibName:@"chatviewiPad" bundle:nil];
	}
	else
	{
	[self initWithNibName:@"chatview" bundle:nil];
	}
		
		jabber=jabberIn;
//	thelist;
	myuser=[NSString stringWithString:username];
	[myuser retain];
	db=thedb;


	chatView.delegate=self;
	groupchat=false;
	
	wasaway=false; 
	wasoffline=false;
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	
	[nc addObserver:self selector:@selector(keyboardDidShow:) name: UIKeyboardDidShowNotification object:nil];
	
	buddyIcon=nil; 
	myIcon=nil; 
	HTMLPage=nil; 
	inHTML=nil; 
	outHTML=nil; 
	
	buddyName=nil; 
	buddyFullName=nil; 
	
	inNextHTML=nil; 
	outNextHTML=nil; 
	
	lastFrom =nil; 
	lastDiv=nil; 
	
	webroot=[NSString stringWithFormat:@"%@/Themes/MonalStockholm/", [[NSBundle mainBundle] resourcePath]];
	[webroot retain];
	
	topHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/top.html", [[NSBundle mainBundle] resourcePath]]]; 
	[topHTML retain]; 
	
	bottomHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/bottom.html", [[NSBundle mainBundle] resourcePath]]]; 
	[bottomHTML retain]; 
	
	

/*	statusHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Status.html", [[NSBundle mainBundle] resourcePath]]]; 
	[statusHTML retain]; 
*/
	
	//	[chatView loadHTMLString:topHTML  baseURL:[NSURL fileURLWithPath:webroot]];
	
	self.view.autoresizesSubviews=true; 

	
/*		webroot=[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/", [[NSBundle mainBundle] resourcePath]];
	[webroot retain];
	
	topHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/top.html", [[NSBundle mainBundle] resourcePath]]]; 
	[topHTML retain]; 
	
	
	bottomHTML=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/bottom.html", [[NSBundle mainBundle] resourcePath]]]; 
	[bottomHTML retain]; */
	
	
	

	
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


- (void)viewDidAppear:(BOOL)animated
{
    NSString* machine=[tools machine]; 
    if([machine hasPrefix:@"iPad"] )
	{
        //refresh UI
        
        
        
        //if vertical or upsidedown
        UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
        
        
        if
            ((orientation==UIInterfaceOrientationPortraitUpsideDown) || 
             (orientation==UIInterfaceOrientationPortrait)
             )
        {
            contactsButton= [[[UIBarButtonItem alloc] initWithTitle:@"Show Contacts"
                                                              style:UIBarButtonItemStyleBordered
                                                             target:self action:@selector(popContacts)] autorelease];
            navController.navigationBar.topItem.rightBarButtonItem =contactsButton; 
            
        }
    }
    
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
	
	[chatView performSelectorOnMainThread:@selector(stopLoading) withObject:nil waitUntilDone:NO];
	
    if(popOverController!=nil)
	[popOverController dismissPopoverAnimated:true]; 
	
	
	[HTMLPage release]; 
	[inHTML release]; 
	[outHTML release]; 
	
	HTMLPage =nil; 
	inHTML =nil;
	outHTML  =nil;

	
	if(lastFrom!=nil)	[lastFrom release]; 
	lastFrom =nil; 
		if(lastDiv!=nil) [lastDiv release];
	lastDiv=nil;
	

	/*if(thelist!=nil) 
	{
		[thelist release];
		thelist=nil;
	}*/
	
	
	lastuser=buddyName;
	
	jabber.messagesFlag=true; // for message count
	[[NSNotificationCenter defaultCenter] 
	 postNotificationName: @"UpdateUI" object: self];	
	
}


//this gets called if the currently chatting user went offline, online or away, back etc
-(void) signalStatus
{
	
	if(groupchat==true) return; // doesnt parse names right at the moment
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	debug_NSLog(@"status signal"); 
	NSString* state=[db buddyState:buddyName: accountno];
	if([state isEqualToString:@""]) 
	{
		if(wasaway==true)
	{
		state=[NSString stringWithString:@"Available"]; 
		wasaway=false;
	}
		else
		{
			[pool release]; 
			return; 
		}
	}
	else
	{
		if(wasaway==false)
		{
			
			wasaway=true;
		}
		else
		{
			[pool release]; 
			return; 
		}
	}
	
	NSString* statusmessage; 
	
	
	if(buddyFullName!=nil)
	{
		
		statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyFullName, state];
	}
	statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyName, state];
	
	/*NSMutableString* messageHTML= [NSMutableString stringWithString:statusHTML];
	
	
		[messageHTML replaceOccurrencesOfString:@"%message%"
									withString:statusmessage
									   options:NSCaseInsensitiveSearch
										 range:NSMakeRange(0, [messageHTML length])];
	
	*/
	
	
	if(lastFrom!=nil) [lastFrom release]; 
	lastFrom=	@"";
	
	NSString* jsstring= [NSString stringWithFormat:@"InsertMessage('%@');",statusmessage ]; 
	

	
	[chatView performSelectorOnMainThread:@selector(stringByEvaluatingJavaScriptFromString:) withObject:jsstring waitUntilDone:NO];
	
	
	[pool release];
}

-(void) signalOffline
{
	if(groupchat==true) return; // doesnt parse names right at the moment
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"offline signal"); 
	NSString* state=@"";
	int count=[db isBuddyOnline:buddyName: accountno];
	if(count>0) 
	{if(wasoffline==true)
		{
		state=[NSString stringWithString:@"Online"]; 
			wasoffline=false; 
		}
		else
		{
			[pool release]; 
			return; 
		}
	}
	else 
		
	{
		if(wasoffline==false)
		{
		state=[NSString stringWithString:@"Offline"]; 
			wasoffline=true; 
		}
		else
		{
			[pool release]; 
			return;
		}
	}	
	
	
	NSString* statusmessage; 
	
	
	if(buddyFullName!=nil)
	{
		statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyFullName, state];
	}
	statusmessage=[NSString stringWithFormat:@"%@ is now %@<br>", buddyName, state];
	

	
	NSString* jsstring= [NSString stringWithFormat:@"InsertMessage('%@');",statusmessage ]; 
	
	[chatView performSelectorOnMainThread:@selector(stringByEvaluatingJavaScriptFromString:) withObject:jsstring waitUntilDone:NO];
	
	
	[pool release];
}


-(void) signalNewMessages
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"new message signal"); 
	
	while(msgthread==true)
		{
			debug_NSLog(@" new message thread sleeping onlock"); 
			usleep(500000); 
			
			
		}
		
		msgthread=true;
		
	debug_NSLog(@" new message  thread got lock"); 
	

		//populate the list
		//[thelist release];
		NSArray* thelist =[db unreadMessagesForBuddy:buddyName: accountno] ;
		if(thelist==nil)
		{
			//multi threaded sanity checkf
			debug_NSLog(@"MT ni check failed. returning");
			[pool release]; 
			msgthread=false;
			return;
		}
		
		if([thelist count]==0)
		{
			//multi threaded sanity checkf
			debug_NSLog(@"MT count check failed. returning");
			[pool release]; 
			msgthread=false;
			return;
		}
		
	if([thelist count]>0)
	{
		if([db markAsRead:buddyName:accountno])
		{
			debug_NSLog(@"marked new messages as read");
			
		}
		else
			debug_NSLog(@"could not mark new messages as read");
	}
	
		int msgcount=0; 
		 
		while(msgcount<[thelist count])
		{
			NSArray* therow=[thelist objectAtIndex:msgcount]; 
		
		if(groupchat==true)
		{
			if(inHTML!=nil) [inHTML release];
			inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
			
			unichar asciiChar = 10; 
			NSString *newline = [NSString stringWithCharacters:&asciiChar length:1];
		
			
			
			[inHTML replaceOccurrencesOfString:newline
									withString:@""
									   options:NSCaseInsensitiveSearch
										 range:NSMakeRange(0, [inHTML length])];
		
			
			
				[inHTML replaceOccurrencesOfString:@"%sender%"
										withString:[therow objectAtIndex:0] 
										   options:NSCaseInsensitiveSearch
											 range:NSMakeRange(0, [inHTML length])];
			
			
			[inHTML replaceOccurrencesOfString:@"%userIconPath%"
									withString:buddyIcon
									   options:NSCaseInsensitiveSearch
										 range:NSMakeRange(0, [inHTML length])];
			
			[inHTML retain]; 
	
			
			
		}
		
		
		NSString* thejsstring; 
		
	NSString* msg= [[therow objectAtIndex:1]stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] ;
		NSString* messagecontent=[self makeMessageHTML: [therow objectAtIndex:0]
														  : [msg stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"] 
														  : [therow objectAtIndex:2]:YES];	
			
	/*	if(([[lastFrom lowercaseString] isEqualToString:[[therow objectAtIndex:0] lowercaseString]]) &&(groupchat==false))
		{
		
			thejsstring= [NSString stringWithFormat:@"InsertNextMessage('%@','%@');", messagecontent,lastDiv]; 
		}
		else*/
		{
		
			thejsstring= [NSString stringWithFormat:@"InsertMessage('%@');", messagecontent]; 
	
		}
	/*		NSString* result=[chatView stringByEvaluatingJavaScriptFromString:thejsstring];
		if(result==nil) debug_NSLog(@"new message in js failed "); 
		else debug_NSLog(@"new message in js ok %@", thejsstring); 
	*/
		
		[chatView performSelectorOnMainThread:@selector(stringByEvaluatingJavaScriptFromString:) withObject:thejsstring waitUntilDone:NO];
			debug_NSLog(thejsstring); 
		
		if(lastFrom!=nil) [lastFrom release]; 
		lastFrom=	[NSString stringWithString:[therow objectAtIndex:0]];
			[lastFrom retain];
			
			
			msgcount++; 
		}
		
	
	
	
	[pool release];
		
	msgthread=false;
	
}

-(void) showLog:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if(buddyName!=nil) [buddyName release]; 
	if(buddyFullName!=nil) [buddyFullName release]; 
	
	[chatInput resignFirstResponder];
	
	buddyName=buddy; 
	buddyFullName=fullname; 
	[buddyName retain]; 
	[buddyFullName retain];
	if([buddyFullName isEqualToString:@""])	
		self.title=buddyName;
	else
		self.title=buddyFullName;
	
	
	
	NSString* machine=[tools machine]; 
	
	if([machine hasPrefix:@"iPad"] )
	{//if ipad..
		self.hidesBottomBarWhenPushed=false; 
	}
	else
	{
		//ipone 
		self.hidesBottomBarWhenPushed=true; 
	}
	
	
	// dont push it agian ( ipad..but stops crash in genreal)
	if([vc topViewController]!=self)
	{
		[vc pushViewController:self animated:YES];
	}
	
	debug_NSLog(@"show log"); 
	//[chatInput setEnabled:false];
	//[chatInput setText:@"Input disabled in log view"];
	chatInput.hidden=true; 
	//	chatInput.editable=false;
	
	//expand web biew
	
	CGRect r;
	r=self.view.frame;
	
		//chatView.frame =r; 
	
	

	
	//populate the list
	NSArray* thelist =[db messageHistoryAll:buddyName: accountno];
	//[thelist retain];
	
	if(myIcon!=nil) [myIcon release]; 
	if(buddyIcon!=nil) [buddyIcon release]; 
	
	myIcon = [self setIcon: [NSString stringWithFormat:@"%@@%@",myuser,domain]];
	buddyIcon= [self setIcon: buddy];
	
	
	if(inHTML!=nil) [inHTML release];
	if(outHTML!=nil) [outHTML release];
	inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  
	
	/*inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  
	*/
	
	
	
	if(inNextHTML!=nil) [inNextHTML release];
	if(outNextHTML!=nil) [outNextHTML release];
	inNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/NextContent.html", [[NSBundle mainBundle] resourcePath]]]; 
	outNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/NextContent.html", [[NSBundle mainBundle] resourcePath]]];  
	
	[inNextHTML retain]; 
	[outNextHTML retain];
	
	
	[inHTML retain]; 
	[outHTML retain]; 
	


	
	if([buddyFullName isEqualToString:@""])
		[inHTML replaceOccurrencesOfString:@"%sender%"
								withString:buddy
								   options:NSCaseInsensitiveSearch
									 range:NSMakeRange(0, [inHTML length])];
	else
		[inHTML replaceOccurrencesOfString:@"%sender%"
								withString:buddyFullName
								   options:NSCaseInsensitiveSearch
									 range:NSMakeRange(0, [inHTML length])];
	
	[outHTML replaceOccurrencesOfString:@"%sender%"
							 withString:myuser
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
	
	
	
	
	if(HTMLPage!=nil) [HTMLPage release];
	HTMLPage=[self createPage:thelist];
	
	
	[HTMLPage retain];
	//[chatView  loadHTMLString: HTMLPage baseURL:[NSURL fileURLWithPath:webroot]];
	
	[self performSelectorOnMainThread:@selector(htmlonMainThread:) withObject:HTMLPage waitUntilDone:NO];
	
	
	
	
	
	//debug_NSLog(@" HTML LOG: %@", HTMLPage); 
	[pool release];
	
}


-(NSString*) setIcon:(NSString*) msguser
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	NSString* theimage; 
	//note: default to png  we want to check a table/array to  look  up  what the file name really is...
	NSString* buddyfile = [NSString stringWithFormat:@"%@/%@.png", iconPath,msguser ]; 
	
	debug_NSLog(buddyfile);
	if([fileManager fileExistsAtPath:buddyfile])
	{
		
		theimage= buddyfile;
		
	}
	
	else
	{
		//jpg
		
		NSString* buddyfile2 = [NSString stringWithFormat:@"%@/%@.jpg", iconPath,msguser]; 
		debug_NSLog(buddyfile2);
		if([fileManager fileExistsAtPath:buddyfile2])
		{
			theimage= buddyfile2;
			
		}
		else
		{
			theimage= [NSString stringWithFormat:@"%@/noicon.png",[[NSBundle mainBundle] resourcePath]];
		}
		
	}
	
	[theimage retain]; 
	[pool release]; 
	return theimage; 
}


-(void) htmlonMainThread:(NSString*) theText
{
	[chatView  loadHTMLString: theText baseURL:[NSURL fileURLWithPath:webroot]];
	

}

-(void) popContacts
{
    debug_NSLog(@"pop out contacts"); 
    
    UITableViewController* tbv = [UITableViewController alloc]; 
    tbv.tableView=contactList; 
    popOverController = [[UIPopoverController alloc] initWithContentViewController:tbv];
    
    popOverController.popoverContentSize = CGSizeMake(320, 480);
    [popOverController presentPopoverFromBarButtonItem:contactsButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
 	
    
  
}

-(void) show:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc
{
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	CGRect r;
	r=self.view.frame;
	r.size.height=r.size.height-chatInput.frame.size.height-5; 
	
	//chatView.frame =r; 
	
	msgthread=false;
	
	firstmsg=true; 
	// replace parts of the string
	
	if(buddyName!=nil) [buddyName release]; 
	if(buddyFullName!=nil) [buddyFullName release]; 
	
	buddyName=buddy; 
	buddyFullName=fullname; 
	[buddyName retain]; 
	[buddyFullName retain];
if([buddyFullName isEqualToString:@""])	
	self.title=buddyName;
	else
		self.title=buddyFullName;
	
//first check.. 
    if([db isBuddyMuc:buddyFullName:accountno])
    {
        groupchat=true; 
    }
    else
    {//fallback
    
	
	NSRange startrange=[buddy rangeOfString:@"@conference"
						
										options:NSCaseInsensitiveSearch range:NSMakeRange(0, [buddy length])];
	
	
	if (startrange.location!=NSNotFound) 
	{
		groupchat=true; 
	}
	else 
	{

	
	NSRange startrange2=[buddy rangeOfString:@"@groupchat"
						
									options:NSCaseInsensitiveSearch range:NSMakeRange(0, [buddy length])];
	
	
	if (startrange2.location!=NSNotFound) 
	{
		groupchat=true; 
	}
	else groupchat=false;
	}
	
    }
	
	NSString* machine=[tools machine]; 
	
	if([machine hasPrefix:@"iPad"] )
	{//if ipad..
			self.hidesBottomBarWhenPushed=false;
        
              
        
	}
	else
	{
		//ipone 
		self.hidesBottomBarWhenPushed=true; 
	}
		
	
	
	// dont push it agian ( ipad..but stops crash in genreal)
	if([vc topViewController]!=self)
		{
			[vc popViewControllerAnimated:false]; //  getof aythign on top 
	[vc pushViewController:self animated:YES];
		}
	
	navController=vc; 
	
	chatInput.hidden=false; 
	//chatInput.editable=true; 
	
	[chatInput setText:@""];

	
	[chatInput setDelegate:self];
	
	
	//mark any messages in from this user as  read
	[db markAsRead:buddyName :accountno];
	
	//populate the list
//	if(thelist!=nil) [thelist release];
	NSArray* thelist =[db messageHistory:buddyName: accountno];
	//[thelist retain];
	
	//get icons 
	// need a faster methos here.. 
	if(myIcon!=nil) [myIcon release]; 
	if(buddyIcon!=nil) [buddyIcon release]; 
	
	
	myIcon = [self setIcon: [NSString stringWithFormat:@"%@@%@",myuser,domain]];
	buddyIcon= [self setIcon: buddy];
	
	
	[chatInput resignFirstResponder];
	
	
	if(inHTML!=nil) [inHTML release];
	if(outHTML!=nil) [outHTML release];
	inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  

/*	
	inHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Incoming/Content.html", [[NSBundle mainBundle] resourcePath]]]; 
	outHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalRenkooNaked/Outgoing/Content.html", [[NSBundle mainBundle] resourcePath]]];  
	*/
	
	
	if(inNextHTML!=nil) [inNextHTML release];
	if(outNextHTML!=nil) [outNextHTML release];
	inNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Incoming/NextContent.html", [[NSBundle mainBundle] resourcePath]]]; 
	outNextHTML=[NSMutableString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/Themes/MonalStockholm/Outgoing/NextContent.html", [[NSBundle mainBundle] resourcePath]]];  
	
	[inNextHTML retain]; 
	[outNextHTML retain];
	
	
	[inHTML retain]; 
	[outHTML retain]; 
	
	
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
							withString:buddy
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
							 withString:[NSString stringWithFormat:@"%@@%@",myuser, domain]
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
	
	
	if(HTMLPage!=nil) [HTMLPage release];
	HTMLPage=[self createPage:thelist];
	
	
	[HTMLPage retain];
	//[chatView  loadHTMLString: HTMLPage baseURL:[NSURL fileURLWithPath:webroot]];
	[self performSelectorOnMainThread:@selector(htmlonMainThread:) withObject:HTMLPage waitUntilDone:NO];
	

	
	
	if([machine hasPrefix:@"iPad"] )
	{
	//refresh UI
	
	
        
        //if vertical or upsidedown
        UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
        
        
        if
            ((orientation==UIInterfaceOrientationPortraitUpsideDown) || 
             (orientation==UIInterfaceOrientationPortrait)
             )
        {
            contactsButton= [[[UIBarButtonItem alloc] initWithTitle:@"Show Contacts"
                                                         style:UIBarButtonItemStyleBordered
                                                        target:self action:@selector(popContacts)] autorelease];
            vc.navigationBar.topItem.rightBarButtonItem =contactsButton; 
            
        }
        else
        {
        	// for the landscape view really
            jabber.messagesFlag=true; 
            [[NSNotificationCenter defaultCenter] 
             postNotificationName: @"UpdateUI" object: self];
        }

        
	}
	
	[pool release]; 
	
}

//always messages going out
-(void) addMessage:(NSString*) to:(NSString*) message
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	

	while(msgthread==true)
	{
		debug_NSLog(@" addmessage thread sleeping onlock"); 
		usleep(500000); 
		
		
	}
	
	msgthread=true;
	debug_NSLog(@" addmessage thread got lock"); 
	
	//escape message

	
	if([db addMessageHistory:myuser:to:accountno:message:myuser])
	{
		debug_NSLog(@"added message"); 
		
		NSString* new_msg =[message stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
		
		//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
		NSString* jsstring; 
	
		if(groupchat!=true) //  message will come back 
		{
	/*	if([lastFrom isEqualToString:myuser])
			
		{
			NSString* html=[self makeMessageHTML:myuser :[new_msg stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"] :nil:YES];
			jsstring= [NSString stringWithFormat:@"InsertNextMessage('%@', '%@');", 
					   html , 
					   lastDiv ]; 
			
			
		}
		else*/
		{
		 jsstring= [NSString stringWithFormat:@"InsertMessage('%@');", [self makeMessageHTML:myuser :[new_msg stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"] :nil:YES]  ]; 
		
		}
		
		
			/*NSString* result=[chatView stringByEvaluatingJavaScriptFromString:jsstring];
		if(result==nil) debug_NSLog(@"new message js failed "); 
		else debug_NSLog(@"new message js ok %@", jsstring); */
			
			
			[chatView performSelectorOnMainThread:@selector(stringByEvaluatingJavaScriptFromString:) withObject:jsstring waitUntilDone:NO];
			
		}
		
	}
	else
		debug_NSLog(@"failed to add message"); 
	
	if(lastFrom!=nil) [lastFrom release]; 
	lastFrom=	[NSString stringWithString:myuser];
	[lastFrom retain];
	
	// make sure its in active
	if(firstmsg==true)
	{
	[db addActiveBuddies:to :accountno];
		firstmsg=false; 
	}
	
	
	msgthread=false;
	[pool release];
	
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	debug_NSLog(@"clicked button %d", buttonIndex); 
	//login or initial error
	
		
		//otherwise 
		if(buttonIndex==0) 
		{
			debug_NSLog(@"do nothing"); 

		}
		else
			
		{
			debug_NSLog(@"sending reconnect signal"); 
			
			// pop the top view controller .. if it was a message send failure then it has to have it on top on all devices
			[navController popViewControllerAnimated:NO];
			
			[[NSNotificationCenter defaultCenter] 
			 postNotificationName: @"Reconnect" object: self];
		}
		
		 
	
	
	
	
	
	
	
	
	
	[pool release];
}



-(void) handleInput:(NSString *)text
{

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	
			if([jabber message:buddyName:text:groupchat])
			{
				if(!groupchat)
				[self addMessage:buddyName:text];
				
				
				//clear the message text
				
				
				//hide keyboard.. 
				//not hiudden for rapid chat
				//[textField resignFirstResponder];
				
				
				
			}
			else
			{
				//reset the text value
				//[chatInput setText:text];
				
				debug_NSLog(@"Message failed to send"); 
				
				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Message Send Failed"
																 message:@"Could not send the message. You may be disconnected."
																delegate:self cancelButtonTitle:@"Close"
													   otherButtonTitles:@"Reconnect", nil] autorelease];
				[alert show];
				
				
				
			}
		
		
		
		
   
	
	
	[pool release];
	[NSThread exit]; 
	
}




/**** Textview delegeate functions ****/
- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
	if([text isEqualToString:@"\n"]) 
	{
		if(([textView text]!=nil) && (![[textView text] isEqualToString:@""]) )
		{
			debug_NSLog(@"Sending message"); 
			// this should call the xmpp message 
			[NSThread detachNewThreadSelector:@selector(handleInput:) toTarget:self withObject:[textView text]];

		}
			 [textView setText:@""];
				return NO;
		 
    }
	
	// iphone vertical
	
	
	UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
	
	int thresh=50; 
		
			if((orientation==UIInterfaceOrientationLandscapeLeft) || (orientation==UIInterfaceOrientationLandscapeRight) )
			{
				thresh=100;
			}

	if([chatInput.text length]>thresh) 
		[chatInput setScrollEnabled:YES];
	else [chatInput setScrollEnabled:NO];
	
	
	
    	
    return YES;
}



-(void) keyboardDidHide: (NSNotification *)notif 
{
	debug_NSLog(@"kbd did hide "); 

}

-(void) keyboardWillHide:(NSNotification *) note
{
	//bigger text view
	//CGRect oldTextFrame= chatInput.frame; 
	//chatInput.frame=CGRectMake(oldTextFrame.origin.x, oldTextFrame.origin.y, oldTextFrame.size.width, oldTextFrame.size.height-30);
	
	
	//move down
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.3];
	self.view.frame = oldFrame;
	
	
	
	[UIView commitAnimations];
	
	debug_NSLog(@"kbd will hide scroll: %f", oldFrame.size.height); 

	
	
}

-(void) keyboardDidShow:(NSNotification *) note
{
	
	//[chatView  stringByEvaluatingJavaScriptFromString:@" document.getElementById('bottom').scrollIntoView(true)"];
	[chatView performSelectorOnMainThread:@selector(stringByEvaluatingJavaScriptFromString:) withObject:@" document.getElementById('bottom').scrollIntoView(true)" waitUntilDone:NO];
	

}

-(void) keyboardWillShow:(NSNotification *) note
{
	//bigger text view
	//CGRect oldTextFrame= chatInput.frame; 
	//chatInput.frame=CGRectMake(oldTextFrame.origin.x, oldTextFrame.origin.y, oldTextFrame.size.width, oldTextFrame.size.height+30);
	
    
	CGRect r,t;
    [[note.userInfo valueForKey:UIKeyboardBoundsUserInfoKey] getValue: &t];
	r=self.view.frame;
	r.size.height -=  t.size.height;
	
		NSString* machine=[tools machine]; 
	if([machine hasPrefix:@"iPad"] )
	{//if ipad..
		r.size.height+=50; //tababar
	}
	
	
		
	//resizing frame for keyboard movie up
	[UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
	oldFrame=self.view.frame;
	self.view.frame =r; 
	
	
	
	
	
	
	[UIView commitAnimations];
	
	
	debug_NSLog(@"kbd will show : %d  scroll: %f", t.size.height, r.size.height); 
	
	
	
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
	
	
	//[chatInput setFont:[UIFont systemFontOfSize:14]];
	
	
}


- (void)textViewDidEndEditing:(UITextView *)textView
{
	
}

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
							withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Smile.png>",[[NSBundle mainBundle] resourcePath]]
							   options:NSCaseInsensitiveSearch
								 range:NSMakeRange(0, [body length])];
	
	[body replaceOccurrencesOfString:@":-)"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Smile.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":D"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Grin.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	[body replaceOccurrencesOfString:@":-D"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Grin.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":O"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Surprised.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	[body replaceOccurrencesOfString:@":-O"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Surprised.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	
	
	[body replaceOccurrencesOfString:@":*"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Kiss.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	[body replaceOccurrencesOfString:@":-*"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Kiss.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	
	
	
	[body replaceOccurrencesOfString:@":("
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sad.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":-("
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sad.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":\'("
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Crying.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":\'-("
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Crying.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	

	
	[body replaceOccurrencesOfString:@";-)"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Wink.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@";)"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Wink.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	
	[body replaceOccurrencesOfString:@":-/"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":/"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	

	
	[body replaceOccurrencesOfString:@":-\\"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":\\"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":-p"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Tongue.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	[body replaceOccurrencesOfString:@":p"
						  withString:[NSString stringWithFormat:@"<img src=../../Emoticons/AdiumEmoticons/Tongue.png>",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	
	
	//changes to avoid having :// as in  http:// turned into an emoticon
	[body replaceOccurrencesOfString:@"<img src=../../Emoticons/AdiumEmoticons/Sarcastic.png>/"
						  withString:[NSString stringWithFormat:@"://",[[NSBundle mainBundle] resourcePath]]
							 options:NSCaseInsensitiveSearch
							   range:NSMakeRange(0, [body length])];
	}
	
	
	
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

-(NSString*) makeMessageHTML:(NSString*) from:(NSString*) themessage:(NSString*) time:(BOOL) liveChat
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"HH:mm:ss"];
	
	
	//strip html from message to prevent XSS
	NSString* message=[tools flattenHTML:themessage trimWhiteSpace:true];
	
	NSString *dateString;
	if(time!=nil)
	{
		NSDateFormatter* formatter = [[[NSDateFormatter alloc] init] autorelease];
	[formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	NSDate* sourceDate=[formatter dateFromString:time];

	NSTimeZone* sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
	NSTimeZone* destinationTimeZone = [NSTimeZone systemTimeZone];
		
	//	debug_NSLog(@"system timezone: %@", [destinationTimeZone  name]); 
	
	NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
	NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
	NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
	
	NSDate* destinationDate = [[[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate] autorelease];
	
	// note: if it isnt the same day we want to show tehful day
	

	dateString = [dateFormatter stringFromDate:destinationDate];
	}
	else
	{
		dateString =  [dateFormatter stringFromDate:[NSDate date]];
	}
	
	if([from isEqualToString:myuser])
	{
		
		NSMutableString* tmpout; 
		
        // commneted out because of the occasional bug
        /*if([from isEqualToString:lastFrom])
			tmpout=[NSMutableString stringWithString:outNextHTML]; 
		else
        */
        {
			//new block
			if(lastDiv!=nil) [lastDiv release];
			lastDiv=[NSString stringWithFormat:@"insert%@",dateString];
			[lastDiv retain];
			
			tmpout=[NSMutableString stringWithString:outHTML]; 
			if(liveChat==true)
			[tmpout replaceOccurrencesOfString:@"insert"
								   withString:lastDiv
									  options:NSCaseInsensitiveSearch
										range:NSMakeRange(0, [tmpout length])];
		}
	
		
        
        
		[tmpout replaceOccurrencesOfString:@"%message%"
								withString:[self emoticonsHTML:message]
								   options:NSCaseInsensitiveSearch
									 range:NSMakeRange(0, [tmpout length])];
		
		
		

		
		[tmpout replaceOccurrencesOfString:@"%time%"
								withString:dateString
								   options:NSCaseInsensitiveSearch
									 range:NSMakeRange(0, [tmpout length])];
		
		
	
		
		
		
		[tmpout retain]; 
		[pool release];
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
			if(lastDiv!=nil) [lastDiv release];
			lastDiv=[NSString stringWithFormat:@"insert%@",dateString];
			[lastDiv retain];
			
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
							   withString:[self emoticonsHTML:message]
								  options:NSCaseInsensitiveSearch
									range:NSMakeRange(0, [tmpin length])];
		[tmpin replaceOccurrencesOfString:@"%time%"
							   withString:dateString
								  options:NSCaseInsensitiveSearch
									range:NSMakeRange(0, [tmpin length])];
		
		[tmpin retain];
		[pool release];
		return [tmpin autorelease];
		
	}		
}


//this is the first time creation 
-(NSMutableString*) createPage:(NSArray*)thelist
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableString* page=[[[NSMutableString alloc] initWithString:topHTML] autorelease];
	// prefix
	debug_NSLog(@"creating page Called");
	
	//debug_NSLog(@" page top %@", page); 
	// iterate through  list
	int counter=0; 
	int nextInsertPoint=0;
	while(counter<[thelist count])
	{
		NSArray* dic =[thelist objectAtIndex:counter];
		NSString* from =[dic objectAtIndex:0] ; 
		NSString* message=[dic objectAtIndex:1] ;
		NSString* time=[dic objectAtIndex:2];
        //debug_NSLog(@"from %@", from);
		
		/*if([from isEqualToString:lastFrom])
		{
			// find location of last insert point
			int insertpoint=0; 
			
			if((nextInsertPoint==0) && (groupchat==false))
			{
			NSString* target=@"<div id=\"insert\" border=\"1\">"; // this is for stockholm only.. renkoo has another
			NSRange thepoint=[page rangeOfString:target options:NSBackwardsSearch];
				if(thepoint.location!=NSNotFound)
			insertpoint=thepoint.location+thepoint.length;
				else insertpoint=0; // preventing a segfault really after a sanity check fail
			}
			else insertpoint=nextInsertPoint; 
			
			
	
			
			NSString* payload=[self makeMessageHTML:from:message:time:NO]; 
			debug_NSLog(payload);
			[page insertString:payload atIndex:insertpoint];
			nextInsertPoint=insertpoint+[payload length];
			
		}
			else*/
			{
				[page appendString:[self makeMessageHTML:from:message:time:NO]];
				nextInsertPoint=0;
			}
		
		if(lastFrom!=nil) [lastFrom release]; 
		lastFrom=	[NSString stringWithString:from];
		
		counter++; 
	}
	//dont append when swingin back into chat
	if(lastFrom!=nil)
	{
		[lastFrom release]; 
		lastFrom=nil; 
	}
	[page appendString:bottomHTML]; 
//	debug_NSLog(@"got page %@", page); 
	//suffix
	[page retain];
	[pool release];
	return [page autorelease]; 
}



- (void)webViewDidStartLoad:(UIWebView *)webView
{
	[spinner startAnimating];
	//	chatInput.editable=false; 
	
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	debug_NSLog(@"webview finished loading"); 
	[spinner stopAnimating];
	//chatInput.editable=true; 
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        NSURL *url = [request URL];
		
		//for OS less than 4  load locally
		NSString* ver=[[UIDevice currentDevice] systemVersion];
		if([ver characterAtIndex:0]=='3')
		{
			
			[pool release];
            return YES;
		}
		else
		//OS4 and above but no MT
		//if([ver characterAtIndex:0]=='4')
		{
			NSString* machine=[tools machine]; 
			if([machine isEqual:@"iPhone1,2"] || [machine isEqual:@"iPod2,1"])
			{
				[pool release]; 
				return YES; 
			}
		}
		
		
		//if([[UIDevice currentDevice].model isEqualToString:@"iPhone"])
		debug_NSLog(@"url : %@", [url absoluteString]); 
		
		//[url scheme] give if file of http type
		
        if (![[url scheme] hasPrefix:@"file"]) {
			//load in safari
            [[UIApplication sharedApplication] openURL:url];
            
			[pool release];
            return NO;
        }
    }
    
	[pool release];
    return YES; 
}



-(void) dealloc
{
	chatView.delegate=nil; 
	
	
	[webroot release];
	if(HTMLPage!=nil) [HTMLPage release];
	if(inHTML!=nil)[inHTML release]; 
	if(outHTML!=nil)[outHTML release]; 
	//if(statusHTML!=nil)[statusHTML release]; 
	
	//[thelist release];
	[myuser release];
	[super dealloc]; 
}
@end
