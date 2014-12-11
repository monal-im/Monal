//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "tools.h"


static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation XMPPEdit


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	
	return true;
}


//this call is needed for tableview controller -7/19/13
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:@"XMPPEdit" bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(void) hideKeyboard
{
	[userText resignFirstResponder];
    [passText resignFirstResponder];
    [enableSwitch resignFirstResponder];
	
    [serverText resignFirstResponder];
    [portText resignFirstResponder];
    [resourceText resignFirstResponder];
}

#pragma mark view lifecylce

- (void)viewDidLoad
{
    [super viewDidLoad];
    _db= [DataLayer sharedInstance];
    
    self.sectionArray =  [NSArray arrayWithObjects:@"Account", @"Advanced Settings", nil];
	if(![_accountno isEqualToString:@"-1"])
	{
        _editing=true;
	} 
	
	DDLogVerbose(@"got account number %@", _accountno);
    

    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button
    [theTable addGestureRecognizer:gestureRecognizer];

    
	if(_originIndex.section==0)
	{
		//edit
        DDLogVerbose(@"reading account number %@", _accountno);
		NSDictionary* settings=[[_db accountVals:_accountno] objectAtIndex:0]; //only one row
		
        //allow blank domains.. dont show @ if so
        if([[settings objectForKey:@"domain"] length]>0)
            userText.text=[NSString stringWithFormat:@"%@@%@",[settings objectForKey:@"username"],[settings objectForKey:@"domain"]];
		else
            userText.text=[NSString stringWithFormat:@"%@",[settings objectForKey:@"username"]];
        
		PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",_accountno]];
		passText.text=[pass getPassword];
        
		serverText.text=[settings objectForKey:@"server"];
		
		portText.text=[NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
		resourceText.text=[settings objectForKey:@"resource"];
		
        sslSwitch.on=[[settings objectForKey:@"secure"] boolValue];
		enableSwitch.on=[[settings objectForKey:@"enabled"] boolValue];
        
        oldStyleSSLSwitch.on=[[settings objectForKey:@"oldstyleSSL"] boolValue];
		checkCertSwitch.on=[[settings objectForKey:@"selfsigned"] boolValue];
		
	
		if([[settings objectForKey:@"domain"] isEqualToString:@"gmail.com"])
		{
			JIDLabel.text=@"GTalk ID";
		}
		
	}
	else
	{
		
		if(_originIndex.row==1)
		{
			JIDLabel.text=@"GTalk ID";
			serverText.text=@"talk.google.com";
			userText.text=@"@gmail.com";
		}
		
		portText.text=@"5222";
		resourceText.text=@"Monal";
		sslSwitch.on=true;
		
        
		if(_originIndex.row==2)
		{
			serverText.text=@"chat.facebook.com";
			userText.text=@"@chat.facebook.com";
			sslSwitch.on=true;
		}
		
		oldStyleSSLSwitch.on=NO;
        checkCertSwitch.on=NO;
		
	}
    
    theTable.backgroundView=nil;
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        
    }
    else
    [theTable setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
	DDLogVerbose(@"xmpp edit view will appear");

	
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
	DDLogVerbose(@"xmpp edit view will hide");
	[self save];
	
   
    
}

-(void) dealloc
{
     [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark actions

-(void) save
{
	
	DDLogVerbose(@"Saving");

	if([userText.text length]==0)
	{
		return ;
	}
	
	NSString* domain;
	NSString* user;
	
	/*	 if([elements count]<2)
	 {
	 return;
	 }
	 if([[elements objectAtIndex:0] length]==0) return;
	 */
	
	
	if([userText.text characterAtIndex:0]=='@')
	{
		//first char =@ means no username in jid
		return;
	}
    
	NSArray* elements=[userText.text componentsSeparatedByString:@"@"];
	
    //default just use JID
	if([serverText.text length]==0)
	{
		if([elements count]>1)
            serverText.text=[elements objectAtIndex:1];
	}
	
	
	//if it is a JID
	if([elements count]>1)
	{
		user= [elements objectAtIndex:0];
		domain = [elements objectAtIndex:1];
	}
	else
	{
		user=userText.text;
		domain= @"";
	}
	
	if(!_editing)
	{
        
		if(([userText.text length]==0) &&
           ([passText.text length]==0)
           )
		{
			//ignoring blank
		}
		else
		{
			
			[_db addAccount:
             userText.text  :
             @"1":
                      user:
             @"":
             serverText.text:
             portText.text :
             sslSwitch.on:
             resourceText.text:
                     domain:
             enableSwitch.on:
             checkCertSwitch.on:
             oldStyleSSLSwitch.on
             ];
			
			
			// save password
			
		
			NSString* val = [NSString stringWithFormat:@"%@", [_db executeScalar:@"select max(account_id) from account"]];
            PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",val]];
            [pass setPassword:passText.text] ;
            
            [[MLXMPPManager sharedInstance]  connectIfNecessary];
			
		}
	}
    else
    {
        
		
        [_db updateAccount:
         userText.text  :
         @"1":
                    user :
         @"" :
         serverText.text:
         portText.text :
         sslSwitch.on:
         resourceText.text:
                   domain:
         enableSwitch.on:
                _accountno:
         checkCertSwitch.on:
         oldStyleSSLSwitch.on];
        
        //save password
        PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",_accountno]];
        [pass setPassword: passText.text] ;
        
   
        if(enableSwitch.on)
        {
            DDLogVerbose(@"calling connect... ");
            [[MLXMPPManager sharedInstance] connectAccount:_accountno];
        }
        else
        {
            [[MLXMPPManager sharedInstance] disconnectAccount:_accountno];
        }
    }
	
	
   
	
}



-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if(buttonIndex==0)
	{
		[_db removeAccount:_accountno];
        [[MLXMPPManager sharedInstance] disconnectAccount:_accountno];
		[self.navigationController popViewControllerAnimated:true];
		
	}
	
	
}

- (IBAction) delClicked: (id) sender
{
    DDLogVerbose(@"Deleting");
	
	//ask if you want to delete
	
    

	UIActionSheet *popupQuery = [[UIActionSheet alloc] initWithTitle:@"Delete this account?" delegate:self
												   cancelButtonTitle:@"No"
											  destructiveButtonTitle:@"Yes"
												   otherButtonTitles:nil, nil];
	
    popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
	
    // [popupQuery showInView:self.view];
	
    [popupQuery showFromTabBar:((UITabBarController*)self.navigationController.parentViewController).tabBar];
	
}





#pragma mark table view datasource methods

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    

	DDLogVerbose(@"xmpp edit view section %d, row %d", indexPath.section, indexPath.row);
    
	UITableViewCell* thecell;
    // load cells from interface builder
	if(indexPath.section==0)
	{
		//the user
		switch (indexPath.row)
		{
			case 0: thecell=usernameCell; break;
			case 1: thecell=passwordCell ;break;
			case 2: thecell=enableCell ;break;
		}
	}
	else
	{
		switch (indexPath.row)
		{
                //advanced
            case 0: thecell=serverCell; break;
            case 1: thecell=portCell ;break;
                
            case 2: thecell=resourceCell; break;
            case 3: thecell=SSLCell ;break;
             case 4: thecell=oldStyleSSLCell ;break;
                 case 5: thecell=checkCertCell ;break;
				
			case 6:
			{
				if(_editing==true)
				{
                    
                    thecell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DeleteCell"];
                    //thecell.selection=false;
                    CGRect cellRectangle = CGRectMake(32,3,225,40);
                    
                    //Initialize the label with the rectangle.
                    UIButton* theButton= [UIButton buttonWithType:UIButtonTypeRoundedRect];
					[theButton setBackgroundImage:[[UIImage imageNamed:@"orangeButton"]
                                                   stretchableImageWithLeftCapWidth:5 topCapHeight:5] forState:UIControlStateNormal];
                    
                    
                    theButton.frame=cellRectangle;
                    
					[theButton setTitle:@"Delete" forState: UIControlStateNormal ];
					[theButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
					theButton.titleLabel.font= [UIFont boldSystemFontOfSize:17.0];
                    [theButton addTarget:self action:@selector(delClicked:) forControlEvents:UIControlEventTouchUpInside];
					
                    
                    
                    //Add the label as a sub view to the cell.
                    [thecell.contentView addSubview:theButton];
                    //[theButton release];
                    
                    
				}
				break;
			}
                
		}
        
	}
    
    thecell.selectionStyle= UITableViewCellSelectionStyleNone;
    
	return thecell;
}



- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	
	//DDLogVerbose(@"xmpp edit counting # of sections %d",  [sectionArray count]);
	return [self.sectionArray count];
	
}


-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *tempView=[[UIView alloc]initWithFrame:CGRectMake(0,200,300,244)];
    tempView.backgroundColor=[UIColor clearColor];
    
    UILabel *tempLabel=[[UILabel alloc]initWithFrame:CGRectMake(15,0,300,44)];
    tempLabel.backgroundColor=[UIColor clearColor];
    tempLabel.shadowColor = [UIColor blackColor];
    tempLabel.shadowOffset = CGSizeMake(0,2);
    tempLabel.textColor = [UIColor whiteColor]; //here you can change the text color of header.
    tempLabel.font = [UIFont boldSystemFontOfSize:17.0f];
    tempLabel.text=[self tableView:tableView titleForHeaderInSection:section ];
    
    [tempView addSubview:tempLabel];
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        tempLabel.textColor=[UIColor darkGrayColor];
        tempLabel.text=  tempLabel.text.uppercaseString;
        tempLabel.shadowColor =[UIColor clearColor];
        tempLabel.font=[UIFont systemFontOfSize:[UIFont systemFontSize]];
        
    }
    
    
    return tempView;
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.sectionArray objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	//DDLogVerbose(@"xmpp edit counting section %d", section);
	
	if(section==0)
		return 3;
    else
    {
        if(_editing==false)
        {
            if(section==1)
                return 6;
        }else return 7;
        
    }
	
	return 0; //default
	
}



#pragma mark table view delegate

//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	DDLogVerbose(@"selected log section %d , row %d", newIndexPath.section, newIndexPath.row);
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    if(textField==userText)
    {    
        // Construct a new range using the object that adopts the UITextInput, our textfield
        if(textField.text.length>0) {
            UITextRange *newRange = [textField textRangeFromPosition:0 toPosition:0];
            
            // Set new range
            [textField setSelectedTextRange:newRange];
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	
	[textField resignFirstResponder];
    
    
	return true;
}





@end
