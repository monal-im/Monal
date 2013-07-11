//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"


@implementation XMPPEdit


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	
	return true;
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
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	
	
	if(![_accountno isEqualToString:@"-1"])
	{
        _editing=true;
	} 
	
	debug_NSLog(@"got account number %@", _accountno);
    

    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button
    [theTable addGestureRecognizer:gestureRecognizer];

    
	if(_originIndex.section==0)
	{
		//edit
        debug_NSLog(@"reading account number %@", _accountno);
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
        
        oldStyleSSLSwitch.on=[[settings objectForKey:@"oldStyleSSL"] boolValue];
		checkCertSwitch.on=[[settings objectForKey:@"selfsigned"] boolValue];
		
	
		if([[settings objectForKey:@"domain"] isEqualToString:@"gmail.com"])
		{
			JIDLabel.text=@"Gtalk ID";
		}
		
	}
	else
	{
		
		if(_originIndex.row==1)
		{
			JIDLabel.text=@"Gtalk ID";
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
		
		
		
	}
    
}

- (void)viewWillAppear:(BOOL)animated
{
	debug_NSLog(@"xmpp edit view will appear");
	
	
}

- (void)viewWillDisappear:(BOOL)animated
{
	debug_NSLog(@"xmpp edit view will hide");
	[self save];
	
   
    
}

-(void) dealloc
{
     [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark actions

-(void) save
{
	
	debug_NSLog(@"Saving");

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
                     domain: enableSwitch.on:
             checkCertSwitch.on:
             oldStyleSSLSwitch.on
             ];
			
			
			// save password
			
		
			NSString* val = [NSString stringWithFormat:@"%@", [_db executeScalar:@"select max(account_id) from account"]];
            PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",val]];
            [pass setPassword:passText.text] ;
			
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
        
    }
	
	
	
}



-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if(buttonIndex==0)
	{
		[_db removeAccount:_accountno];
		[self.navigationController popViewControllerAnimated:true];
		
	}
	
	;
}

- (IBAction) delClicked: (id) sender
{
    debug_NSLog(@"Deleting");
	
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

//required
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


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
	
	
	
	debug_NSLog(@"xmpp edit view section %d, row %d", indexPath.section, indexPath.row);
    
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
                    CGRect cellRectangle = CGRectMake(32,3,225,[tableView rowHeight]-6);
                    
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
	
	//debug_NSLog(@"xmpp edit counting # of sections %d",  [sectionArray count]);
	return [self.sectionArray count];
	
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	
	
	//debug_NSLog(@"xmpp edit title for  section %d", section);
	return [self.sectionArray objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	//debug_NSLog(@"xmpp edit counting section %d", section);
	
	if(section==0)
		return 3;
    else
    {
        if(_editing==false)
        {if(section==1)
            return 4;
        }else return 7;
        
    }
	
	return 0; //default
	
}



#pragma mark table view delegate

//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected log section %d , row %d", newIndexPath.section, newIndexPath.row);
    
	
	
}

#pragma mark txtview delegate



-(void) keyboardWillHide:(NSNotification *) note
{
	
    
	//move down
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.3];
	self.view.frame = oldFrame;
	
	[UIView commitAnimations];
	debug_NSLog(@"kbd will hide scroll: %f", oldFrame.size.height);
	
	
}



-(void) keyboardWillShow:(NSNotification *) note
{
    
	CGRect r,t;
    [[note.userInfo valueForKey:UIKeyboardBoundsUserInfoKey] getValue: &t];
	r=self.view.frame;
	r.size.height -=  t.size.height-50; //tabbar
    
	//resizing frame for keyboard movie up
	[UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
	oldFrame=self.view.frame;
	self.view.frame =r;
	
	
	[UIView commitAnimations];
	
	debug_NSLog(@"kbd will show : %d  scroll: %f ", t.size.height, r.size.height);
	
    
	
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
	/*debug_NSLog(@"scolling correct");
     
     if(textField==serverText)
     {
     debug_NSLog(@"editing server");
     unsigned  int  indexlist[] = { 1,0  };
     [theTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
     atScrollPosition:UITableViewScrollPositionNone animated:NO];
     
     
     }
     
     
     if(textField==portText)
     {
     debug_NSLog(@"editing port");
     unsigned  int  indexlist[] = { 1,1  };
     [theTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
     atScrollPosition:UITableViewScrollPositionNone animated:NO];
     }
     
     
     
     if(textField==resourceText)
     {
     debug_NSLog(@"editing resource");
     unsigned  int  indexlist[] = { 1,2  };
     [theTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
     atScrollPosition:UITableViewScrollPositionNone animated:NO];
     }
     
     */
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	
	[textField resignFirstResponder];
    
    
	return true;
}





@end
