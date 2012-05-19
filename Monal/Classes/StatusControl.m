//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "statusControl.h"


@implementation statusControl

@synthesize jabber; 
@synthesize iconPath; 
@synthesize contactsTable;





-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}


#pragma mark tableview stuff

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	
	
	
	UITableViewCell* thecell=statuscell;//default 


    
    switch(indexPath.section)
    {
        case 0:
        {
            thecell=topcell; 
            break; 
        }
        case 1:
        { 
            thecell=statuscell;
            break;
        }
        case 2:
        {//3
            switch(indexPath.row)
            {
                case 0:{
                    thecell=awaycell; break;
                }
                case 1:
                {thecell=visiblecell; break;}
                case 2:
                {thecell=prioritycell; break;}
                case 3:
                {thecell=musiccell; break;}
            }
            break; 
        }
        case 3:
        {//3
            switch(indexPath.row)
            {
                case 0:
                {thecell=alertcell; break;}
                    
                    
                    //now redundant 
                /*case 1:
                { thecell=vibratecell; break;}*/
              
            
            }
            break; 
        }
            
        case 4:
        {//3
            switch(indexPath.row)
            {
               
                case 0:
                {thecell=previewcell; break;}
                case 1:
                {thecell=loggingcell; break;}
                case 2:
                {thecell=offlinecontactcell; break;}
            }
            break; 
        }
            
       
    }
    
        debug_NSLog(@"got cell for section  %d row %d", indexPath.section, indexPath.row);
 
    
	;

	
//tableView.frame.size.width;
	
	return thecell; 

}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(indexPath.section==0) //top
	{
		return topcell.frame.size.height; 
	}
	
    else
        return 44; // default cell height 
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    NSInteger toreturn;
    toreturn=0;
    switch(section)
    {
        case 0:
        {
            toreturn =1; 
            break; 
        }
        case 1:
        {
            toreturn =1; 
            break; 
        }
        case 2:
            
        {
            toreturn =4; 
            break; 
        }
        case 3:
        {
            toreturn =1; //removed vibrate
            break; 
        }
            
        case 4:
        {
            toreturn =3;
            break; 
        }
      
    }
	
	
        debug_NSLog(@"section %d size %d", section, toreturn);
	return toreturn; 
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView 
{
	
	    debug_NSLog(@"number of sections");
	return 5;
	
}

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section 
{
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)] ;
     
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)] ;
    label.text = [self tableView:theTable titleForHeaderInSection:section];
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView addSubview:label];
    
       // [headerView setBackgroundColor:[UIColor clearColor]];
    return headerView;
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section 
{
	NSString* toreturn; 
    toreturn=0; //default
    switch(section)
    {
        case 0:
        {
            toreturn =@"Current Status"; 
            break; 
        }
        case 1:
        {
            toreturn =@"Set Status"; 
            break; 
        }
        case 2:
        {
            toreturn =@"Presence"; 
            break; 
        }
        case 3:
        {
            toreturn =@"Alerts"; 
            break; 
        }
        case 4:
        {
            toreturn =@"General"; 
            break; 
        }
       
    }
	
	
    debug_NSLog(@"section name %@", toreturn);
	return toreturn; 
	
    
}




#pragma mark status actions

-(IBAction) offlineContacs
{
[[NSUserDefaults standardUserDefaults] setBool:OfflineContact.on forKey:@"OfflineContact"];
    [contactsTable reloadData];
    
}

-(IBAction) previewOn
{
[[NSUserDefaults standardUserDefaults] setBool:MessagePreview.on forKey:@"MessagePreview"];
}
-(IBAction) loggingOn
{
[[NSUserDefaults standardUserDefaults] setBool:Logging.on forKey:@"Logging"];
}



-(IBAction) musicOn
{	
    [[NSUserDefaults standardUserDefaults] setBool:MusicStatus.on forKey:@"MusicStatus"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ToggleMusic" object:self];
}




-(IBAction) soundOn
{
	[[NSUserDefaults standardUserDefaults] setBool:soundSwitch.on forKey:@"Sound"];
}

-(IBAction) vibrateOn
{
	[[NSUserDefaults standardUserDefaults] setBool:soundSwitch.on forKey:@"Vibrate"];
}

-(IBAction) setAway
{
	if(jabber==nil) return; 
    debug_NSLog(@"toggle away"); 
	[[NSUserDefaults standardUserDefaults] setBool:Away.on forKey:@"Away"]; 
	if (Away.on)
	{
		
		[jabber setAway];
       
	}	else 
	{
		[jabber setAvailable];
       
	}
    
}





-(IBAction) invisible
{
	if(jabber==nil) return; 
	[[NSUserDefaults standardUserDefaults] setBool:Visible.on forKey:@"Visible"]; 
	if (!Visible.on)
	{
		debug_NSLog(@"Setting invisible"); 
		[jabber setInvisible]; 
		
	}
	else
	{
		
		[jabber setAvailable];
	}
}


#pragma mark uitextfield delegate



//text delatgate fn
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	
	
    switch(textField.tag)
	{// status
        case 0:
        {
            
                debug_NSLog(@"Setting Status Message"); 
                [jabber setStatus:[textField text]]; 
                [[NSUserDefaults standardUserDefaults] setObject:[textField text] forKey:@"StatusMessage"]; 
            break; 
            

        }
        case 1:
        {
            //priority
			debug_NSLog(@"Setting xmpp priority"); 
            [jabber setPriority:[[textField text] integerValue]]; // set to 0 if invalid
            [jabber setAvailable];
            [[NSUserDefaults standardUserDefaults] setObject:[textField text]  forKey:@"XMPPPriority"]; 
        }
	}
	//hide keyboard
	[textField resignFirstResponder];
	
	
	return true;
}




#pragma mark view stuff
- (void) hideKeyboard 
{
    [statusval resignFirstResponder]; 
    [priority resignFirstResponder];
}


-(void) viewDidLoad
{
    [super viewDidLoad];
    [theTable setBackgroundView:nil];
    [theTable setBackgroundView:[[UIView alloc] init] ];
    theTable.backgroundColor = [[UIColor alloc] initWithPatternImage:[UIImage imageNamed:@"carbon3.jpg"]];

}

-(void) viewDidAppear:(BOOL)animated
{
    
    if(jabber==nil) return; 
    
   
  
	debug_NSLog(@"status did  appear");
    currentStatus.text=jabber.statusMessage; 
    debug_NSLog(@"current message %@", jabber.statusMessage);
   
    /*
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
      gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button
    
    [theTable addGestureRecognizer:gestureRecognizer];
    */
	
    //for id 
    priority.tag=1; 
    statusval.tag=0; 
    
    
	//set own icon 
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	
	NSString* buddyfile = [NSString stringWithFormat:@"%@/%@@%@.png", 
						   iconPath,jabber.account, jabber.domain ]; 
	if([fileManager fileExistsAtPath:buddyfile])
	{
		UIImage* image=[UIImage imageWithContentsOfFile:buddyfile];
        
		ownIcon.image=image; 
	}
	else
	{
		NSString* buddyfile = [NSString stringWithFormat:@"%@/%@@%@.jpg", 
							   iconPath,jabber.account, jabber.domain ]; 
		UIImage* image=[UIImage imageWithContentsOfFile:buddyfile];
		ownIcon.image=image; 
	}

    debug_NSLog(@"icon path %@", buddyfile);
	//[scroll setContentSize:CGSizeMake(320, 509)];
    
    
    //****ipod, ipad vs iphone
	debug_NSLog([UIDevice currentDevice].model); 
	if([[UIDevice currentDevice].model isEqualToString:@"iPhone"])
	{
        //for vibrataion 
		vibrateSwitch.hidden=false; 
		vibrateLabel.hidden=false; 
		
		//soundSwitch.hidden=false; 
		//soundLabel.hidden=false; 
		
	}
    
    //**** loading the default settings 
	Away.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"Away"];
	Visible.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"Visible"];
	MusicStatus.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"MusicStatus"];
	
	vibrateSwitch.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"Vibrate"];
	soundSwitch.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"];
    
    OfflineContact.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"];
	MessagePreview.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"MessagePreview"];
    Logging.on=[[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"];
    
	statusval.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"StatusMessage"];
	priority.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"XMPPPriority"];

    
    ;
	
}

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"status did  disappear");
	[[NSUserDefaults standardUserDefaults]  synchronize];

	
	
}


@end
