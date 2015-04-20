//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "MLAccountCell.h"
#import "tools.h"


static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface XMPPEdit()
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSString *port;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL useSSL;
@property (nonatomic, assign) BOOL oldStyleSSL;
@property (nonatomic, assign) BOOL selfSignedSSL;

@property (nonatomic, weak) UITextField *currentTextField;

@end
    

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
    [self.currentTextField resignFirstResponder];
}

#pragma mark view lifecylce

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLAccountCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"AccountCell"];
    
    _db= [DataLayer sharedInstance];
    
    self.sectionArray =  [NSArray arrayWithObjects:@"Account", @"Advanced Settings", nil];
	if(![_accountno isEqualToString:@"-1"])
	{
        self.editMode=true;
	} 
	
	DDLogVerbose(@"got account number %@", _accountno);
    

    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button
    [self.tableView addGestureRecognizer:gestureRecognizer];

    
	if(_originIndex.section==0)
	{
		//edit
        DDLogVerbose(@"reading account number %@", _accountno);
		NSDictionary* settings=[[_db accountVals:_accountno] objectAtIndex:0]; //only one row
		
        //allow blank domains.. dont show @ if so
        if([[settings objectForKey:@"domain"] length]>0)
            self.jid=[NSString stringWithFormat:@"%@@%@",[settings objectForKey:@"username"],[settings objectForKey:@"domain"]];
		else
           self.jid=[NSString stringWithFormat:@"%@",[settings objectForKey:@"username"]];
        
		
        PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",_accountno]];
        self.password=[pass getPassword];
        
		self.server=[settings objectForKey:@"server"];
		
		self.port=[NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
		self.resource=[settings objectForKey:@"resource"];
		
        self.useSSL=[[settings objectForKey:@"secure"] boolValue];
		self.enabled=[[settings objectForKey:@"enabled"] boolValue];
        
        self.oldStyleSSL=[[settings objectForKey:@"oldstyleSSL"] boolValue];
		self.selfSignedSSL=[[settings objectForKey:@"selfsigned"] boolValue];
		
	
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
			self.server=@"talk.google.com";
			self.jid=@"@gmail.com";
		}
		
		self.port=@"5222";
		self.resource=@"Monal";
		self.useSSL=true;
		
        
		if(_originIndex.row==2)
		{
			self.server=@"chat.facebook.com";
			self.jid=@"@chat.facebook.com";
			self.useSSL=true;
		}
		
		self.oldStyleSSL=NO;
        self.selfSignedSSL=NO;
		
	}
    
    self.tableView.backgroundView=nil;
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
       
    }
    else {
        [self.tableView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
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
	
    [ [MLXMPPManager sharedInstance].passwordDic setObject:self.password forKey:self.accountno];
    
}

-(void) dealloc
{
     [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark actions

-(void) save
{
    [self.currentTextField resignFirstResponder];
    
	DDLogVerbose(@"Saving");

	if([self.jid length]==0)
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
	
	
	if([self.jid characterAtIndex:0]=='@')
	{
		//first char =@ means no username in jid
		return;
	}
    
	NSArray* elements=[self.jid componentsSeparatedByString:@"@"];
	
    //default just use JID
	if([self.server length]==0)
	{
		if([elements count]>1)
            self.server=[elements objectAtIndex:1];
	}
	
	
	//if it is a JID
	if([elements count]>1)
	{
		user= [elements objectAtIndex:0];
		domain = [elements objectAtIndex:1];
	}
	else
	{
		user=self.jid;
		domain= @"";
	}
	
	if(!self.editMode)
	{
        
		if(([self.jid length]==0) &&
           ([self.password length]==0)
           )
		{
			//ignoring blank
		}
		else
		{
			
			[_db addAccount:
             self.jid  :
             @"1":
                      user:
             @"":
             self.server:
             self.port :
             self.useSSL:
            self.resource:
                     domain:
             self.enabled:
             self.selfSignedSSL:
            self.oldStyleSSL
             ];
			
			
			// save password
			  NSString* val = [NSString stringWithFormat:@"%@", [_db executeScalar:@"select max(account_id) from account"]];
            PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",val]];
            [pass setPassword:self.password] ;

		
	
            
            [[MLXMPPManager sharedInstance]  connectIfNecessary];
			
		}
	}
    else
    {
        
		
        [_db updateAccount:
         self.jid  :
         @"1":
                    user :
         @"" :
         self.server:
         self.port :
         self.useSSL:
        self.resource:
                   domain:
         self.enabled:
                _accountno:
         self.selfSignedSSL:
        self.oldStyleSSL];
        

        PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",_accountno]];
        [pass setPassword:self.password] ;
  
        if(self.enabled)
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
    
	MLAccountCell* thecell=(MLAccountCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
    
    // load cells from interface builder
	if(indexPath.section==0)
	{
		//the user
		switch (indexPath.row)
		{
            case 0: {
                thecell.cellLabel.text=@"Jabber Id";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.tag=1;
                thecell.textInputField.text=self.jid;
                break;
            }
            case 1: {
                thecell.cellLabel.text=@"Password";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.secureTextEntry=YES;
                thecell.textInputField.tag=2;
                thecell.textInputField.text=self.password;
                break;
            }
            case 2: {
                thecell.cellLabel.text=@"Enabled";
                thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=1;
                thecell.toggleSwitch.on=self.enabled;
                break;
            }

		}
	}
	else
	{
		switch (indexPath.row)
		{
                //advanced
            case 0:  {
                thecell.cellLabel.text=@"Server";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.tag=3;
                 thecell.textInputField.text=self.server;
                break;
            }

            case 1:  {
                thecell.cellLabel.text=@"Port";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.tag=4;
                 thecell.textInputField.text=self.port;
                break;
            }

                
            case 2:  {
                thecell.cellLabel.text=@"Resource";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.tag=5;
                 thecell.textInputField.text=self.resource;
                break;
            }

            case 3: {
                thecell.cellLabel.text=@"SSL";
               thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=2;
               thecell.toggleSwitch.on=self.useSSL;
                break;
            }
            case 4: {
                thecell.cellLabel.text=@"Old Style SSL";
               thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=3;
                thecell.toggleSwitch.on=self.oldStyleSSL;
                break;
            }
            case 5: {
                thecell.cellLabel.text=@"Self Signed";
               thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=4;
                thecell.toggleSwitch.on=self.selfSignedSSL;
                break;
            }
				
			case 6:
			{
				if(self.editMode==true)
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
    
    if(indexPath.row!=6)
    {
        thecell.textInputField.delegate=self;
        if(thecell.textInputField.hidden==YES)
        {
            [thecell.toggleSwitch addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
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
        if(self.editMode==false)
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
#pragma mark text input  fielddelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    self.currentTextField=textField;
    if(textField.tag==1) //user input field
    {
        if(textField.text.length >0) {
            // Construct a new range using the object that adopts the UITextInput, our textfield
            UITextRange *newRange = [textField textRangeFromPosition:0 toPosition:0];
            
            // Set new range
            [textField setSelectedTextRange:newRange];
        }
    }
   
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    switch (textField.tag) {
        case 1: {
            self.jid=textField.text;
            break;
        }
        case 2: {
            self.password=textField.text;
            break;
        }
            
        case 3: {
            self.server=textField.text;
            break;
        }
            
        case 4: {
            self.port=textField.text;
            break;
        }
        case 5: {
            self.resource=textField.text;
            break;
        }
            
        default:
            break;
    }
    
}


- (BOOL)textFieldShouldReturn:(UITextField *)textField
{

	[textField resignFirstResponder];
	return true;
}


-(void) toggleSwitch:(id)sender
{
   UISwitch *toggle = (UISwitch *) sender;
    
    switch (toggle.tag) {
        case 1: {
            if(toggle.on)
            {
                self.enabled=YES;
            }
            else {
                self.enabled=NO;
            }
            break;
        }
        case 2: {
            if(toggle.on)
            {
                self.useSSL=YES;
            }
            else {
                self.useSSL=NO;
            }
            break;
        }
            
        case 3: {
            if(toggle.on)
            {
                self.oldStyleSSL=YES;
            }
            else {
                self.oldStyleSSL=NO;
            }
            break;
        }
        case 4: {
            if(toggle.on)
            {
                self.selfSignedSSL=YES;
            }
            else {
                self.selfSignedSSL=NO;
            }
            
            break;
        }
    }

 
}


@end
