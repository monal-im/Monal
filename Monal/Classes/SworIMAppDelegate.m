//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "SworIMAppDelegate.h"

@implementation SworIMAppDelegate

@synthesize db;
@synthesize chatwin;
@synthesize accountno; 
@synthesize morenav; 
@synthesize iconPath; 
@synthesize activeNavigationController; 
@synthesize accountsNavigationController;
@synthesize  logsNavigationControlleriPad; 
@synthesize  aboutNavigationControlleriPad; 
@synthesize tabcontroller;

@synthesize activeTab; 

@synthesize jabber;






#pragma mark UI display 



-(void)initalMusicWatcher
{

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];		
	debug_NSLog(@"music watcher thread"); 
	[[MPMusicPlayerController iPodMusicPlayer] beginGeneratingPlaybackNotifications];
	
	
	
	//call once to update current song if any 
	[self handleNowPlayingItemChanged];
	
	[pool release]; 
	[NSThread exit];
}



- (void)uiUpdateThread:(id)sender
{
    uithreadrunning=true;  
	[self uiUpdater];
    uithreadrunning=false;
}

-(void) uiUpdater
{
	
	debug_NSLog(@"Updating UI"); 
	if(jabber==nil) return; 
	if(jabber.loggedin!=true) return; 
	
NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];		
	
	if((uiIter==1) && ([[NSUserDefaults standardUserDefaults] boolForKey:@"MusicStatus"]==true))
	{
		[NSThread detachNewThreadSelector:@selector(initalMusicWatcher) toTarget:self withObject:nil];	
	
			
	}
	

	

	
		NSMutableArray* indexPaths=[[[NSMutableArray alloc] init] autorelease];
	
	NSArray* dblist=nil;
	NSArray* dblistOffline=[db offlineBuddies:accountno]; 
	

	
	
	if((jabber.presenceFlag==true)  &&(screenLock==true))
	{
		buddylistdirty=true; // when it comes back to the forefront it needs to refresh	
	}
	
	if(((jabber.presenceFlag==true) || (buddylistDS.thelist==nil) ||([buddylistDS.thelist count]==0)) &&(screenLock!=true)
	   )
	{
		buddylistdirty=false; // reset it
		jabber.presenceFlag=false;
	dblist=[jabber getBuddyListArray];
		
		
	
		
	
	NSArray* buddyListRemoved =[jabber getBuddyListRemoved]; 
	NSArray* buddyListUpdated =[jabber getBuddyListUpdated]; 
	
	NSArray* buddyListAdded =[jabber getBuddyListAdded]; 
	
		
	// get a total count
	
	

//	bool setDblist=false; 

	
	 bool needtoupdate=false; 
	
	//([buddylistDS count]==0) || buddy list empty 
	
	if ( (([buddyListAdded count]>0) ||
									 ([buddyListRemoved count]>0)  ) 
	    //||( setDblist==true)
		)
	{
		debug_NSLog(@"messages read, messages in, or both added and removed. setting quick " ); 
		[buddylistDS setList:dblist];
		[buddylistDS setOfflineList:dblistOffline];
        
        //this determines whether we should just reload here or later
        if([buddyListUpdated count]==0)
         [buddyTable reloadData];
        else
            needtoupdate=true; 
		
	} 
		else // assume it might be an empty list
		{
            bool hasSetLists=false; 
			if(([buddylistDS.thelist count]==0) && ([dblist count]>0) )
			{
				[buddylistDS setList:dblist];
                hasSetLists=true; 
			}
			
			if(([buddylistDS.theOfflineList count]==0) && ([dblistOffline count]>0) )
			{
				[buddylistDS setOfflineList:dblistOffline];
                hasSetLists=true; 
			}
            
            //only refresh if something has changed
            if(hasSetLists==true)
            {
                if([buddyListUpdated count]==0)
                    [buddyTable reloadData];
                else
                    needtoupdate=true; 
            }
		}
		
		 
			if ([buddyListUpdated count]>0)
		{
			
			
			
			debug_NSLog(@"buddies updated: %d",[buddyListUpdated count] ); 
			
			
			int counter=0; 
			int counter2=0; 
			
			
			while(counter<[buddyListUpdated count])
			{
				counter2=0; 
				
				while(counter2<[buddylistDS.thelist count])
				{
					if([[[buddylistDS.thelist objectAtIndex:counter2] objectAtIndex:0] isEqualToString:
						
						[[buddyListUpdated objectAtIndex:counter]objectAtIndex:0 ]])
					{
						
						[[buddylistDS.thelist objectAtIndex:counter2] replaceObjectAtIndex:1 withObject:
						 [[buddyListUpdated objectAtIndex:counter] objectAtIndex:1] 
						 ];
						
						[[buddylistDS.thelist objectAtIndex:counter2] replaceObjectAtIndex:2 withObject:
						 [[buddyListUpdated objectAtIndex:counter] objectAtIndex:2] 
						 ];
						
						[[buddylistDS.thelist objectAtIndex:counter2] replaceObjectAtIndex:3 withObject:
						 [[buddyListUpdated objectAtIndex:counter] objectAtIndex:3] 
						 ];
						
						[[buddylistDS.thelist objectAtIndex:counter2] replaceObjectAtIndex:5 withObject:
						 [[buddyListUpdated objectAtIndex:counter] objectAtIndex:5] 
						 ];
						
					
                       
                        
						
						NSUInteger indexArr[] = {0,counter2};
						
						NSIndexPath *indexSet = [NSIndexPath indexPathWithIndexes:indexArr length:2];
							[indexPaths addObject:indexSet];
						
						//currently chatting user changes status	
					
						if([[[buddylistDS.thelist objectAtIndex:counter2] objectAtIndex:0] isEqualToString:
							
							chatwin.buddyName])
							if([buddyNavigationController visibleViewController]==chatwin)
								
							{
								
								//[chatwin performSelectorOnMainThread:@selector(signalStatus)
								//						  withObject:nil  
								//					   waitUntilDone:NO];
								[chatwin signalStatus];
								
							}
						
						
						
						
					}
					counter2++; 
				}
				counter++; 
			}
			
			
			
			
		}
        
        
		
        if(needtoupdate==true)
        {
              [buddyTable reloadData];
            //multiple changes, just refresh
        }
		else
            //this is just a small update. refresh a row
         
            {
                
                debug_NSLog(@"indexpath count %d",[indexPaths count] ); 
              
                
                //done below in another thread
          
                
            }
		
		[jabber buddyListUpdateRead];
		
		

	}
		

	
		
	if (jabber.messagesFlag==true)
	{
		
		//check if messages are in
		
		int unnoticed=[db countUnnoticedMessages:accountno];	
		
		debug_NSLog(@"count of unnoticed messages %d", unnoticed); 
		if(unnoticed>0)
		{
			
			
			if(screenLock||backGround) // only when not active (bg or lock screen)
			{
				//vibration by default for iphone
				
				
				
				// make sure it is visible ie iphone
				if(
				   ( [[NSUserDefaults standardUserDefaults] boolForKey:@"Vibrate"]==true))
				{
                    
					AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
					
				}
				if(
                  
				   ( [[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"]==true))
				{
					
					
					SystemSoundID pmph;
					id sndpath = [[NSBundle mainBundle] 
								  pathForResource:@"Tritone" 
								  ofType:@"aif" 
								  inDirectory:@"/"];
					CFURLRef baseURL = (CFURLRef) [[[NSURL alloc] initFileURLWithPath:sndpath] autorelease];
					AudioServicesCreateSystemSoundID (baseURL, &pmph);
                  
					AudioServicesPlaySystemSound(pmph);	
					
					
				}
				
				
			}
			
			
			
			
			NSArray* unnoticedMessages=[db unnoticedMessages:accountno];
			
			int msgcount=0; 
			while (msgcount<[unnoticedMessages count])
			{
				//[chatwin addMessage:[[messages objectAtIndex:msgcount] objectForKey:@"from"]
				//				   :[[messages objectAtIndex:msgcount] objectForKey:@"message"]];
				
				NSArray* msgrow=[unnoticedMessages objectAtIndex:msgcount];
				NSString* msgusr=[msgrow objectAtIndex:0];
				NSString* msgMess=[tools flattenHTML:[msgrow objectAtIndex:1] trimWhiteSpace:true];
				NSString* userfile=[msgrow objectAtIndex:2];
				NSString* userfull=[msgrow objectAtIndex:3];
				
				NSString* msgfrom; 
				if([userfull isEqualToString:@""])
				{
					msgfrom=msgusr;
				}
				else
					msgfrom=userfull; 
				
				
				
				[db addActiveBuddies:msgusr :accountno];
				// OS4 if the screen is locked push out a message 
				
				if(screenLock)
					
				{
					NSString* ver=[[UIDevice currentDevice] systemVersion];
					if([ver characterAtIndex:0]!='3')
					{
						
						
						
						
						NSDate* theDate=[NSDate dateWithTimeIntervalSinceNow:0]; //immediate fire
						
						UIApplication* app = [UIApplication sharedApplication];
						NSArray*    oldNotifications = [app scheduledLocalNotifications];
						
						// Clear out the old notification before scheduling a new one.
						if ([oldNotifications count] > 0)
							[app cancelAllLocalNotifications];
						
						// Create a new notification
						UILocalNotification* alarm = [[[UILocalNotification alloc] init] autorelease];
						if (alarm)
						{
							//setting badge
							alarm.applicationIconBadgeNumber=[UIApplication sharedApplication].applicationIconBadgeNumber+1;   
							
							//scehdule info 
							alarm.fireDate = theDate;
							alarm.timeZone = [NSTimeZone defaultTimeZone];
							alarm.repeatInterval = 0;
							
                            if([[NSUserDefaults standardUserDefaults] boolForKey:@"MessagePreview"])
							alarm.alertBody = [NSString stringWithFormat: @"%@: %@", msgfrom, msgMess];
							else
                                alarm.alertBody = [NSString stringWithFormat: @"Message from %@:", msgfrom];
							
                            
							[app scheduleLocalNotification:alarm];
							
						//	[app presentLocalNotificationNow:alarm];
							debug_NSLog(@"Scheduled local message alert "); 
							
							
							
						}
					}
				} else
				{
					//slide
					
					if(!(([buddyNavigationController visibleViewController]==chatwin)
						 || ([activeNavigationController visibleViewController]==chatwin) ))
					{
						//prepare filename
						NSString* fullfile; 
						
						if([userfile isEqualToString:@"ok"] || [userfile isEqualToString:@""] )
						{
							fullfile=[NSString stringWithString:@"noicon"];
							
						}
						else
						{
							fullfile=[NSString stringWithFormat:@"%@/%@", iconPath,userfile];
						}
						
						
						SlidingMessageViewController* slider = 
						[[SlidingMessageViewController alloc]
						 initWithTitle:msgfrom message:msgMess:fullfile];   
						[window addSubview:slider.view];
						
						// Show the message 
						[slider showMsg];
						
						
					}
					else if (!([[msgusr lowercaseString] isEqualToString: [chatwin.buddyName lowercaseString]]))
					{
						//prepare filename
						NSString* fullfile; 
						
						if([userfile isEqualToString:@"ok"] || [userfile isEqualToString:@""] )
						{
							fullfile=[NSString stringWithString:@"noicon"];
							
						}
						else
						{
							fullfile=[NSString stringWithFormat:@"%@/%@", iconPath,userfile];
						}
						
						
						
						
						SlidingMessageViewController* slider = [[SlidingMessageViewController alloc] correctSlider:msgfrom :msgMess:fullfile];
						
						[window addSubview:slider.view];
						
						// Show the message 
						[slider showMsg];
						
					}
					
					
				}
				
				
				
				
				
				
				
				msgcount++;
			}
			
			
			
			
			[db markAsNoticed:accountno];
			
			//only send singals if it is in the chat view
			if(([buddyNavigationController visibleViewController]==chatwin)
			   || ([activeNavigationController visibleViewController]==chatwin))
			{
				
				//[chatwin performSelectorOnMainThread:@selector(signalNewMessages) withObject:nil waitUntilDone:NO];
				[chatwin signalNewMessages];
		
			
			}
			
		
			
		}   
		
	}
	
	//need to do seeprateley or else same cell might n aimate twice
	//could be count or update
	if([indexPaths count]>0)
	{
		[self performSelectorOnMainThread:@selector(reloadBuddies:) withObject:indexPaths waitUntilDone:NO];
	}
	
	
	
// after everything has been added and removed
	NSMutableArray* indexPaths2=[[[NSMutableArray alloc] init] autorelease];
	
	int totalunread=0;
	if(buddylistDS!=nil)
		if(buddylistDS.thelist!=nil)
	if([buddylistDS.thelist count]>0)
	{
	if(jabber.messagesFlag==true)
	{
		jabber.messagesFlag=false;
		debug_NSLog(@"unread count");
		totalunread=[db countUnreadMessages:accountno]; 	
		
		if(activeTab!=nil)
			if(totalunread>0)
			{
				// for some reason this has crashed in the past here.. might be am ulti update issue
				// show a badge
				activeTab.badgeValue=[NSString stringWithFormat:@"%d",totalunread]; 
			}
			else
			{
				// show no  badge
				activeTab.badgeValue=nil; 
			}
		
		
	
	// need to check refresh for all since there might have been one set to 0
	if(dblist==nil) dblist=[jabber getBuddyListArray];
		
		int usercount=0; 
		while ((usercount<[dblist count]) && (usercount<[buddylistDS.thelist count]) )
		{
			 int msgcount=
			[db countUserUnreadMessages:[[dblist objectAtIndex:usercount] objectAtIndex:0] 
													:accountno] ;
			
			
			
			debug_NSLog(@"%@ old object %d new %d",[[dblist objectAtIndex:usercount] objectAtIndex:0],
						[[[buddylistDS.thelist objectAtIndex:usercount] objectAtIndex:4] intValue], msgcount ); 

			// for each budfdy find out how many messages they have and set it in the list is differnt 
			if([[[buddylistDS.thelist objectAtIndex:usercount] objectAtIndex:4] intValue]  !=msgcount)
			{
								
				[[buddylistDS.thelist objectAtIndex:usercount] replaceObjectAtIndex:4 withObject:
				 [NSNumber numberWithInt:msgcount]];
				NSUInteger indexArr[] = {0,usercount};
				
				NSIndexPath *indexSet = [NSIndexPath indexPathWithIndexes:indexArr length:2];
				
				//[[buddyTable cellForRowAtIndexPath:indexSet] setNeedsLayout];
			
				[indexPaths2 addObject:indexSet];
			
				
			
			}
			usercount++; 
		}
	}
	
		
		
	}	
	
		//could be count or update
	if([indexPaths2 count]>0)
	{
		
		 [self performSelectorOnMainThread:@selector(reloadBuddies:) withObject:indexPaths2 waitUntilDone:NO];
		
	}
		
	
	
	
	uiIter++; // allow ui update to be called 2 times before pulling buddy icons.. this will allow the list to load first hopefully



	
	listLoad=true; 

	[pool release];	
	
}

-(void) reloadBuddies:(NSArray*) indexpaths
{
    
    
     [buddyTable beginUpdates];
     [buddyTable reloadRowsAtIndexPaths: indexpaths
     withRowAnimation:UITableViewRowAnimationNone];
     
     
     
     [buddyTable endUpdates];
    
     
}

//alert view delegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	//login or initial error
	if(([[alertView title] isEqualToString:@"Login Error"])
		||([[alertView title] isEqualToString:@"Error in Inititation"]))
	{
		
		[activitySun stopAnimating];
	//	[activityView removeFromSuperview];
		[pool release]; 
		return; 
	}
	
	
	
	[pool release];
}



-(void) addBuddy
{
	if(jabber==nil) return; 
		if(jabber.loggedin!=true) return; 
	debug_NSLog(@"adding buddy");
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	

	
	
	buddyAdd* addwin=[[buddyAdd alloc] autorelease];
	if([[tools machine] hasPrefix:@"iPad"])
    {
        [addwin init:nil:nil];
    addwin.bbiOpenPopOver=buddyNavigationController.navigationBar.topItem.leftBarButtonItem;
        [addwin showiPad:jabber];
        
    }
    else
    {
        [addwin init:buddyNavigationController:tabcontroller];
        [addwin show:jabber];
    }
    
    
   
		
    
	[pool release];
	
	
}

#pragma mark connectivity 

-(void) keepAlive
{
		debug_NSLog(@"keep alive starts");
	if(jabber==nil) return; 
	
    
    // keep alive is more forgiving than reachability
/*	Reachability* internetReach = [[Reachability reachabilityForInternetConnection] retain];
	
	reachable=[internetReach currentReachabilityStatus]; 
	if((reachable==NotReachable) || ([internetReach connectionRequired]))
	{
		[self reconnect];
		return; 
	}
*/
	
    
	//if there is a stream error then always run keep alive
	if(jabber.streamError==false)
	{
	if(jabber.loggedin!=true) return; 	
	}
	debug_NSLog(@"keep alive.. "); 
	
	if(![jabber keepAlive])
	{
		debug_NSLog(@"Connection drop detected. Reconnecting.."); 
		// reconnect.. 
		[self reconnect];
	}
	
	
	
}





-(void) showLoggedIn:(id)sender
{
	debug_NSLog(@"Sending defalt status commands" );
	
	//send commands 
	if([[[NSUserDefaults standardUserDefaults] stringForKey:@"StatusMessage"] length]>0) 
    {[jabber setStatus:[[NSUserDefaults standardUserDefaults] stringForKey:@"StatusMessage"]];} //message first to not override away status
	if(([[NSUserDefaults standardUserDefaults] boolForKey:@"Away"]==true) ) {[statuscon setAway];}
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"Visible"]==false) { [statuscon invisible];}
	
	[activityMsg setText:@"Logged in"];
	[activitySun stopAnimating];
	[activityView removeFromSuperview];
	
	 statuscon.jabber=jabber; 
     statuscon.iconPath=iconPath; 
    statuscon.contactsTable=buddyTable;
    joinGroup.jabber=jabber;
    
   
        //there is no morenav on ipad
        //joinGroup.nav=morenav; 
   
	//update ui
	[[NSNotificationCenter defaultCenter] 
	 postNotificationName: @"UpdateUI" object: self];
	
}


-(void) showLoginFailed:(id)sender
{
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	[activityMsg setText:@"Error Logging in"];
	[activitySun stopAnimating];
	
	
		[pool release];
}


-(void) Connect
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	//connection
	[db resetBuddies]; // forget buddy states
	activeTab.badgeValue=nil; 
	
	
	[jabber setPriority:[[[NSUserDefaults standardUserDefaults] stringForKey:@"XMPPPriority"] integerValue]]; // set to 0 if invalid
	
	if([jabber connect]) // only if it connects
		// we want to get a signal here from the xmpp that the connection was complete and then these things are run
	{
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uiUpdateThread:) name: @"UpdateUI" object:nil];
		
		
			
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showLoggedIn:) name: @"LoggedIn" object:nil];		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showLoginFailed:) name: @"LoginFailed" object:nil];
		
		
		
		listLoad=false; 
				
		
		
		
		
		
		
	}
	else
	{
		
	/*	[activityMsg setText:@"Error connecting to server"];
		[activitySun stopAnimating];
		Login.on=false;
		//[activityView removeFromSuperview];
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error connecting to server"
														message:@"Could not connect to server. Make sure settings are correct"
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] autorelease];
		
		[alert show];
		
		*/
		
		
	}
	[pool release];
	[NSThread exit];
}





-(bool)forceNet{
	NSString *connected = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"http://apple.com/robots.txt"]];
	wait(20000);
	if (connected == NULL) {
		debug_NSLog(@"Not connected");
		return false;
	} else {
		debug_NSLog(@"Connected - %@",connected);
		return true; 
	}
}

-(void) disconnect
{
	if(jabber==nil) return; 
	debug_NSLog(@"disconnecting"); 
	activeTab.badgeValue=nil;
	

	
	[accountno release]; 
	[chatwin release]; 

	[buddylistDS release];
	
	[jabber disconnect]; 	// ***make sure all listener threads are dead***
	[jabber release]; 
	jabber=nil ; 
	
	

	
	chatwin = [chat alloc]; 
	[chatwin init:jabber:buddyNavigationController:@"":db];
	chatwin.iconPath=iconPath; 
	chatwin.domain=@"";
	chatwin.accountno=@""; 
	
	
	
	buddylistDS=[buddylist alloc];
	[buddylistDS initList:chatwin];
buddylistDS.tabcontroller=tabcontroller;
	buddylistDS.iconPath=iconPath; 
	buddylistDS.jabber=nil;
	
	
	buddylistDS.viewController=buddyNavigationController;
	
	
	

	
	
	//buddy list
    [buddyTable setDelegate:buddylistDS]; 
	[buddyTable setDataSource:buddylistDS];
	
	
	
	[buddyTable reloadData]; 
	
	
	
}

-(void) reconnect
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	/// check reachbility
	debug_NSLog(@"checking reachability"); 
	
    Reachability* wifireach = [[Reachability reachabilityForLocalWiFi] retain];	
    NetworkStatus reachable1 =[wifireach currentReachabilityStatus]; 
    
	Reachability* internetReach = [[Reachability reachabilityForInternetConnection] retain];	
	NetworkStatus reachable=[internetReach currentReachabilityStatus]; 
	if(((reachable==NotReachable) || ([internetReach connectionRequired]))&&
       ((reachable1==NotReachable) || ([wifireach connectionRequired]))
       )
	{
		
		
		if(![self forceNet]) 
		{
		
		
		{
			sleep(2); 
			if(![self forceNet]) 
			{
				sleep(2);
				if(![self forceNet]) 
				{
					//no netowkr connection
                // dont show if screen locked
                    if((screenLock==true) || (backGround==true))
                    {
                    }
                    else
                    {
                    
					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Network Error"
																	message:@"Could not detect a network connection. If you are connected, try clicking 'reconnect' in the accounts tab to try again."
																   delegate:self cancelButtonTitle:nil
														  otherButtonTitles:@"Close", nil] autorelease];
					[alert show];
					}
                    
					[pool release];
					return; 
				}
			}
		}
		}
	}
	
	[pool release]; 
	
	//pop the tabbar view controller if need be
	//if(navigationController.topViewController!=tabcontroller)
	//	[navigationController popViewControllerAnimated:NO];
	NSArray* enabledAccounts=[db enabledAccountList];
	if([enabledAccounts count]<1)
	{
		@try
		{
		tabcontroller.selectedIndex = 3;
		}
		@catch(NSException* err) {}
		
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Enable an account"
														message:@"You need to enable at least one account"
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		
		
		
		return; 
		
	}
	if(connectLock==true) return; 
	
	connectLock=true; 
	
    //wait for thread to finsh
    while( uithreadrunning==true)
    {
        sleep(2); // 2 seconds
    }
    
	@try
	{
	tabcontroller.selectedIndex = 0;
	}
	@catch(NSException* err) {}
	 
	 //login progress notification
	[buddyTable addSubview: activityView];
	activityView.center=buddyTable.center; 
	[activitySun startAnimating];
	[activityMsg setText:@"Logging in..."];	
		
	
	if(jabber!=nil)
	{
		
		
		
	
		debug_NSLog(@"disconnecting"); 
		
		[accountno release]; 
		[chatwin release]; 
	
		[buddylistDS release];
		
		
		
		[jabber disconnect]; 	// ***make sure all listener threads are dead***
		[jabber release]; 
		debug_NSLog(@"reconnecting "); 
		
	}
	
	NSString* accountNo=[NSString stringWithFormat:@"%@",[[enabledAccounts objectAtIndex:0] objectAtIndex: 0]];
	bool secure=false; 
	if([[[enabledAccounts objectAtIndex:0] objectAtIndex: 7] intValue]==1) secure=true; 
	
	//AIM is 3
		if([[[enabledAccounts objectAtIndex:0] objectAtIndex: 2] intValue]==3) 
		{
			jabber= [[AIMTOC2 alloc] 
					 init
					 :[[enabledAccounts objectAtIndex:0] objectAtIndex: 3]
					 :[[[enabledAccounts objectAtIndex:0] objectAtIndex: 4] intValue]
					 : [[enabledAccounts objectAtIndex:0] objectAtIndex: 5]
					// : [[enabledAccounts objectAtIndex:0] objectAtIndex: 6]
					 :[[enabledAccounts objectAtIndex:0] objectAtIndex: 8]
					 : [[enabledAccounts objectAtIndex:0] objectAtIndex: 9]
					 : secure
			: db : accountNo];
		}
	else // everything else is XMPP
	{
        debug_NSLog(@" domain: %@", [[enabledAccounts objectAtIndex:0] objectAtIndex: 9]); 
        
	jabber= [[xmpp alloc] 
			 init
			 :[[enabledAccounts objectAtIndex:0] objectAtIndex: 3]
			 :[[[enabledAccounts objectAtIndex:0] objectAtIndex: 4] intValue]
			 : [[enabledAccounts objectAtIndex:0] objectAtIndex: 5]
			// : [[enabledAccounts objectAtIndex:0] objectAtIndex: 6]
			 :[[enabledAccounts objectAtIndex:0] objectAtIndex: 8]
			 : [[enabledAccounts objectAtIndex:0] objectAtIndex: 9]
			 : secure
			 : db: accountNo ];
	}


	accountno=[NSString stringWithFormat:@"%@",[[enabledAccounts objectAtIndex:0] objectAtIndex: 0] ];
	[accountno retain];
	debug_NSLog(@"account number %@", accountno); 
	
	chatwin = [chat alloc]; 
    
	[chatwin init:jabber:buddyNavigationController:[jabber getAccount]:db];
	chatwin.iconPath=iconPath; 
	chatwin.domain=[[enabledAccounts objectAtIndex:0] objectAtIndex: 9];
	chatwin.accountno=accountno; 
	
	
	
	buddylistDS=[buddylist alloc];
	[buddylistDS initList:chatwin];
	buddylistDS.tabcontroller=tabcontroller;
	buddylistDS.iconPath=iconPath; 
	buddylistDS.jabber=jabber;
	
	
	buddylistDS.viewController=buddyNavigationController;
	
	
	


	
	//buddy list
    [buddyTable setDelegate:buddylistDS]; 
	[buddyTable setDataSource:buddylistDS];
	


	
	[buddyTable reloadData]; 


	//[self Connect];
	[NSThread detachNewThreadSelector:@selector(Connect) toTarget:self withObject:nil];
	
	

	
	
	
		
	connectLock=false; 


}

#pragma mark media

-(void) toggleMusic
{
    
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
	
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"MusicStatus"]==true)
	{
		
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(handleNowPlayingItemChanged)
													 name:MPMusicPlayerControllerNowPlayingItemDidChangeNotification 
												   object:[MPMusicPlayerController iPodMusicPlayer] ];
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(handleNowPlayingItemStateChanged)
													 name:MPMusicPlayerControllerPlaybackStateDidChangeNotification 
												   object:[MPMusicPlayerController iPodMusicPlayer] ];
		
		[[MPMusicPlayerController iPodMusicPlayer] beginGeneratingPlaybackNotifications];
		
        
	}
	else {
		debug_NSLog(@" no  song"); 
		
		[[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:MPMusicPlayerControllerNowPlayingItemDidChangeNotification 
                                                      object:[MPMusicPlayerController iPodMusicPlayer] ];
		[[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:MPMusicPlayerControllerPlaybackStateDidChangeNotification 
                                                      object:[MPMusicPlayerController iPodMusicPlayer] ];
		[[MPMusicPlayerController iPodMusicPlayer] endGeneratingPlaybackNotifications];
		
		
		[jabber setStatus:@""];
	}
    
	[pool release];

}


- (void)handleNowPlayingItemStateChanged {
	// Ask the music player for the current song.
    
	debug_NSLog(@" checking song start or stop"); 
	
	
	if(jabber==nil) return; 
	if(jabber.loggedin!=true) return; 
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	
	if([[MPMusicPlayerController iPodMusicPlayer] playbackState]==MPMusicPlaybackStatePlaying)
	{
		playing=true; 
		debug_NSLog(@" updating  song"); 
		MPMediaItem * song = [[MPMusicPlayerController iPodMusicPlayer] nowPlayingItem];
		NSString * title   = [song valueForProperty:MPMediaItemPropertyTitle];
		//NSString * album   = [song valueForProperty:MPMediaItemPropertyAlbumTitle];
		NSString * artist  = [song valueForProperty:MPMediaItemPropertyArtist];
		
		
		// Display album artwork. self.artworkImageView is a UIImageView.
		/* CGSize artworkImageViewSize = self.artworkImageView.bounds.size;
		 MPMediaItemArtwork *artwork = [currentItem valueForProperty:MPMediaItemPropertyArtwork];
		 if (artwork != nil) {
		 self.artworkImageView.image = [artwork imageWithSize:artworkImageViewSize];
		 } else {
		 self.artworkImageView.image = nil;
		 */
		
		//set everywhere
		SlidingMessageViewController* slider ;
		if(!([buddyNavigationController visibleViewController]==chatwin))
		{
			
			slider = 
			[[SlidingMessageViewController alloc]
			 initWithTitle:@"♫ Status" message:[NSString stringWithFormat: @"%@-%@",title,artist]: @""];   
		}
		else
		{
			slider = 
			[[SlidingMessageViewController alloc]
			 correctSlider:@"♫ Status" :[NSString stringWithFormat: @"%@-%@",title,artist]: @""];
		}
		[window addSubview:slider.view];
		
		// Show the message 
		[slider showMsg];
		
		[jabber setStatus:[NSString stringWithFormat: @"♫ %@-%@",title,artist]];
	}
	else {
		
		if(playing==true) //only do this once..
		{
			debug_NSLog(@" no  song"); 
			[jabber setStatus:@""];	
			
			playing=false; 
		}
		
	}
	
}

- (void)handleNowPlayingItemChanged {
    // Ask the music player for the current song.
    
	debug_NSLog(@" checking song"); 


	if(jabber==nil) return; 
	if(jabber.loggedin!=true) return; 
	
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	
	if([[MPMusicPlayerController iPodMusicPlayer] playbackState]==MPMusicPlaybackStatePlaying)
	{
		playing=true; 
		debug_NSLog(@" updating  song"); 
	MPMediaItem * song = [[MPMusicPlayerController iPodMusicPlayer] nowPlayingItem];
	NSString * title   = [song valueForProperty:MPMediaItemPropertyTitle];
	//NSString * album   = [song valueForProperty:MPMediaItemPropertyAlbumTitle];
	NSString * artist  = [song valueForProperty:MPMediaItemPropertyArtist];
	
	
    // Display album artwork. self.artworkImageView is a UIImageView.
   /* CGSize artworkImageViewSize = self.artworkImageView.bounds.size;
    MPMediaItemArtwork *artwork = [currentItem valueForProperty:MPMediaItemPropertyArtwork];
    if (artwork != nil) {
        self.artworkImageView.image = [artwork imageWithSize:artworkImageViewSize];
    } else {
        self.artworkImageView.image = nil;
		*/
	
		//set everywhere
		SlidingMessageViewController* slider ;
		if(!([buddyNavigationController visibleViewController]==chatwin))
		{
	
		slider = 
		[[SlidingMessageViewController alloc]
		 initWithTitle:@"♫ Status" message:[NSString stringWithFormat: @"%@-%@",title,artist]: @""];   
		}
		else
		{
			slider = 
			[[SlidingMessageViewController alloc]
			 correctSlider:@"♫ Status" :[NSString stringWithFormat: @"%@-%@",title,artist]: @""];
		}
		[window addSubview:slider.view];
		
		// Show the message 
		[slider showMsg];
		
		[jabber setStatus:[NSString stringWithFormat: @"♫ %@-%@",title,artist]];
	}
			
	

	[pool release];
		

}


#pragma mark app load

- (void)applicationDidFinishLaunching:(UIApplication *)application 
{

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
    vibrateenabled=false; 
	uithreadrunning=false;

	
	//debug_NSLog([[NSTimeZone systemTimeZone] name]);
	
	NSString* machine=[tools machine]; 

	if([machine hasPrefix:@"iPad"] )
	{//if ipad..
	//default
	buddyTable=buddyTable1;
       
	}
    
  	 
	if([[UIDevice currentDevice].model isEqualToString:@"iPhone"])
	{
        vibrateenabled=true;  
		
	}
	
	tabcontroller.moreNavigationController.navigationBar.barStyle=UIBarStyleBlack; 
	//tabcontroller.moreNavigationController.navigationBar.hidden=true; 
		
	
	
	
	moreControl=[TabMoreController alloc]; 
	tabcontroller.moreNavigationController.delegate=moreControl;
	morenav=tabcontroller.moreNavigationController;
	
	
		buddyNavigationController.navigationBar.barStyle=UIBarStyleBlack;
		activeNavigationController.navigationBar.barStyle=UIBarStyleBlack;
		accountsNavigationController.navigationBar.barStyle=UIBarStyleBlack;
		statusNavigationController.navigationBar.barStyle=UIBarStyleBlack;
	
	//navigationController.navigationBar.translucent=true; 
	
   
    
	lasttitle=@""; 
	[lasttitle retain];
	bgTask=nil; 
	screenLock=false; 
		backGround=false; 
	
	

	gotOwnIcon=0;
	uiIter=0; 
	
	activityView.layer.cornerRadius = 10; // round corners on login view iphone 3 and above only
	
    statuscon.jabber=nil; 
   
    
	
	
	
	// initilize database
	db = [DataLayer alloc] ;
	[db initDB];
	
	
		
	//add button to navigation controller
		//tabcontroller.navigationItem.rightBarButtonItem=[self editButtonItem];
	
	UIBarButtonItem* addBuddyButton = [UIBarButtonItem alloc]; 
	[addBuddyButton initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addBuddy)];
	
	//tabcontroller.navigationItem.leftBarButtonItem=addBuddyButton; 
	
	
	buddylistDS.plusButton=addBuddyButton; 
	buddylistDS.viewController=buddyNavigationController;
	

	//version info in about tab

		
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reconnect) name: @"Reconnect" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(disconnect) name: @"Disconnect" object:nil];
	

	//listen for music toggle change
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toggleMusic) name: @"ToggleMusic" object:nil];
	
	
	

	// make the icons directory if it isnt there
	
	
	NSString* filename=[NSString stringWithFormat:@"/buddyicons"];
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	iconPath = [documentsDirectory stringByAppendingPathComponent:filename];
	[iconPath retain];
	debug_NSLog(@"checking : %@",iconPath);
	if( ![fileManager fileExistsAtPath:iconPath])
	{
		// The buddy icon dir
		
		if([fileManager createDirectoryAtPath:iconPath attributes:nil]) debug_NSLog(@"created dir : %@",iconPath);  else
			debug_NSLog(@"coud not create : %@",iconPath) ;
		
		
	}
	inIconThread=false; 
	

	//start keep alive 5 min
	[NSTimer scheduledTimerWithTimeInterval:300
									 target:self
								   selector:	@selector(keepAlive)
								   userInfo:nil
									repeats:YES];
	

	
	//account table

	NSArray* accountList=[db accountList];
	if([accountList count]<1)
	{
		
		
	
		tabcontroller.selectedIndex = 3;
	
		
		if([machine hasPrefix:@"iPad"] )
		{//if ipad..
			
			[window addSubview:split.view];
			[window makeKeyAndVisible];
		}
		else
			
		{
			//if iphone
			
			[window addSubview:tabcontroller.view];
			[window makeKeyAndVisible];
			
		}
	
		//defaults
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"Visible"]; 
	[[NSUserDefaults standardUserDefaults] setBool:true forKey:@"Sound"];
        
        	[[NSUserDefaults standardUserDefaults] setBool:true forKey:@"OfflineContact"];
        	[[NSUserDefaults standardUserDefaults] setBool:true forKey:@"MessagePreview"];
        	[[NSUserDefaults standardUserDefaults] setBool:true forKey:@"Logging"];
        

		
		
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Welcome"
														message:@"Welcome to Monal. Please set up an account. You may have multiple accounts set up,  but only one can be logged in at once.  "
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		

	
		[pool release];
		
	
		return; 
		
	}
	
	

			
	NSArray* enabledAccounts=[db enabledAccountList]; 

	
	if([enabledAccounts count]<1)
	{
		// set before assing views
		tabcontroller.selectedIndex = 3;
	
		if([machine hasPrefix:@"iPad"] )
		{//if ipad..
			
			[window addSubview:split.view];
			

			[window makeKeyAndVisible];
		}
		else
			
		{
			//if iphone
			
			[window addSubview:tabcontroller.view];
			[window makeKeyAndVisible];
			
		}
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Enable an account"
														message:@"You should set an account to login"
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		
		[pool release];
		
		
		return; 
		
	}
	
	

	


	// Configure and show the window
	if([machine hasPrefix:@"iPad"] )
	{//if ipad..
		
		[window addSubview:split.view];
		[window makeKeyAndVisible];
	}
	else
		
	{
		//if iphone
		
		[window addSubview:tabcontroller.view];
		[window makeKeyAndVisible];
		
	}
	
	[self reconnect]; 
	
	//[self performSelector:@selector(reconnect) withObject:nil afterDelay:0.0f];
	
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"MusicStatus"]==true)
	{
		debug_NSLog(@"setting up song checker"); 
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(handleNowPlayingItemChanged)
													 name:MPMusicPlayerControllerNowPlayingItemDidChangeNotification 
												   object:[MPMusicPlayerController iPodMusicPlayer] ];
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(handleNowPlayingItemStateChanged)
													 name:MPMusicPlayerControllerPlaybackStateDidChangeNotification 
												   object:[MPMusicPlayerController iPodMusicPlayer] ];
		
		//[[MPMusicPlayerController iPodMusicPlayer] beginGeneratingPlaybackNotifications];
		
	
	}

	
	[pool release];
	
	}



// view delegate function
- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{

	debug_NSLog(@"Set editing called "); 
	[super setEditing:editing animated:animated]; // this changes it to Done/Edit
	[buddyTable setEditing:editing animated:animated];
	
	
}







#pragma mark multi tasking os4 stuff *****

//this should come up when a notification happens and you click on view
- (void)application:(UIApplication *)application 
didReceiveLocalNotification:(UILocalNotification *)notification 
{
	[[UIApplication sharedApplication] cancelAllLocalNotifications];
	debug_NSLog(@"got notification.. dismissing all scheduled ones"); 
	
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
debug_NSLog(@"Entering background"); 
	idleMsgShown=false; 
	
	[chatwin hideKeyboard];
	
// dont do anything special if not logged in
	if(jabber==nil) return; 
	if(jabber.loggedin!=true) return; 
	
	
	 //******* VOIP .. to be removed when going to normal task completion ********  

    /*
void (^myBlock)(void) = ^(void){
		debug_NSLog(@"OS keep alive hander called"); 
		[self keepAlive];
	};
    
   
    
    	 if([[UIApplication sharedApplication] setKeepAliveTimeout:(NSTimeInterval)600 handler: myBlock])
	 {
	 debug_NSLog(@"set keep alive hander"); 
	 }
	
*/
    
	buddylistdirty=false; // reset 
	
	
	
	
	NSString* ver=[[UIDevice currentDevice] systemVersion];
	if([ver characterAtIndex:0]!='3')
	{
	
		
	 backGround=true; 
	
        
        //******** this needs to be removed when i go back to VOIP socket
	 bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
       debug_NSLog(@"OS background expire hander"); 
		 
		 // Clear out the old notification before scheduling a new one
			 [[UIApplication sharedApplication] cancelAllLocalNotifications];
		
		 
		[[UIApplication sharedApplication] endBackgroundTask:bgTask];
		 bgTask=UIBackgroundTaskInvalid;
    }];

	}

    [[NSUserDefaults standardUserDefaults] synchronize];
    
}



- (void)applicationWillEnterForeground:(UIApplication *)application
{
	debug_NSLog(@"Entering foreground"); 
	// nothing special if not logged in
	if(jabber==nil) return; 
	if(jabber.loggedin!=true) return; 

	
	
		backGround=false; 
	[[UIApplication sharedApplication] clearKeepAliveTimeout];
	
	debug_NSLog(@"cleared keep alive hander"); 
	
	//send a keep alive to see if we are still connected
	[self keepAlive];

	// see if there are unread messages and refresh active chat if true
    
    debug_NSLog(@"unread count");
    int totalunread=[db countUnreadMessages:accountno]; 	
    
    if(activeTab!=nil)
        if(totalunread>0)
        {
            // for some reason this has crashed in the past here.. might be am ulti update issue
            // show a badge
            activeTab.badgeValue=[NSString stringWithFormat:@"%d",totalunread]; 
        }
        else
        {
            // show no  badge
            activeTab.badgeValue=nil; 
        }
    
    
    


	
	      //******** this needs to be removed when i go back to VOIP socket


	
	

	 
	if((bgTask!=UIBackgroundTaskInvalid) && (bgTask!=nil))
	{
		[[UIApplication sharedApplication] endBackgroundTask:bgTask];
		 bgTask=UIBackgroundTaskInvalid;
	};
	 
	
}

#pragma mark ipad stuff

- (void)splitViewController:(UISplitViewController*)svc
	 willHideViewController:(UIViewController *)aViewController
		  withBarButtonItem:(UIBarButtonItem*)barButtonItem
	   forPopoverController:(UIPopoverController*)pc {
	
	debug_NSLog(@"hiding master");
	buddyTable=buddyTable1; 
	[buddyTable2 setDelegate:nil]; 
	[buddyTable2 setDelegate:nil]; 
	
	buddyTable1.hidden=false;
	
	[buddyTable setDelegate:buddylistDS]; 
	[buddyTable setDataSource:buddylistDS];
	[buddyTable reloadData];
	
	buddyTab.title=@"Contacts"; 
	buddyTab.image=[UIImage imageNamed:@"Buddies.png"]; 
   
}

//the master view will be shown again
- (void)splitViewController:(UISplitViewController*)svc
	 willShowViewController:(UIViewController *)aViewController
  invalidatingBarButtonItem:(UIBarButtonItem *)button {
	
	
		debug_NSLog(@"showing master");
		buddyTable=buddyTable2; 
	[buddyTable1 setDelegate:nil]; 
	[buddyTable1 setDelegate:nil]; 
		buddyTable1.hidden=true;
	
	
	[buddyTable setDelegate:buddylistDS]; 
	[buddyTable setDataSource:buddylistDS];
	[buddyTable reloadData];
	
	buddyTab.title=@"Chats"; 
	buddyTab.image=[UIImage imageNamed:@"chatsicon.png"]; 
     
}

// the master view controller will be displayed in a popover
- (void)splitViewController:(UISplitViewController*)svc
		  popoverController:(UIPopoverController*)pc
  willPresentViewController:(UIViewController *)aViewController {
	
	//empty for now
	
}


#pragma mark regular os stuff**

- (void)didReceiveMemoryWarning
{
	debug_NSLog(@"Got low memory warning. ."); 
	//[self dealloc]; 
	//exit(0); 
	[super didReceiveMemoryWarning];

}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
	debug_NSLog(@"Becoming Active"); 
	
	//reset
	[[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
	
	screenLock=false; 
	
	if(buddylistdirty==true)
	{
		jabber.presenceFlag=true;
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"UpdateUI" object: self];	
	}
	
	
	NSString* ver=[[UIDevice currentDevice] systemVersion];
	if([ver characterAtIndex:0]!='3')
	{
	
        // when the screen unlocks or the person comes back, stop anymore popups
		[[UIApplication sharedApplication] cancelAllLocalNotifications];
	}
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	debug_NSLog(@"Resigning Active"); 
	
		screenLock=true; 
}

- (void)applicationWillTerminate:(UIApplication *)application
{
 
    debug_NSLog(@"will terminate"); 
    //clean out messages if logging off
    if(![[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"])
    {
        [db messageHistoryCleanAll:jabber.accountNumber];
    }
	
	// 	[db resetBuddies]; // forget buddy states
	
	
	[jabber disconnect]; 
    
  
}


#pragma mark cleanup

- (void)dealloc {
	
	[tabcontroller release];
	[window release];
	[chatwin release]; 
	[buddylistDS release];
	
	[super dealloc];
}

@end
