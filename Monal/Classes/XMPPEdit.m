//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "MLAccountCell.h"
#import "MLButtonCell.h"
#import "NXOAuth2.h"
#import "MLOAuthViewController.h"

#import "tools.h"


static const int ddLogLevel = LOG_LEVEL_VERBOSE;

NSString *const kGtalk = @"Gtalk";

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
@property (nonatomic, strong) NSURL *oAuthURL;
@property (nonatomic, assign) BOOL autoSave;

@end


@implementation XMPPEdit


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
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ButtonCell"];
    
    _db= [DataLayer sharedInstance];
    
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
        
        
        PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@-%@",self.accountno,self.jid]];
        self.password=[pass getPassword];
        if(!self.password.length>0)
        {
            pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",self.accountno]];
            self.password=[pass getPassword];
        }
        
        self.server=[settings objectForKey:@"server"];
        
        self.port=[NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
        self.resource=[settings objectForKey:@"resource"];
        
        self.useSSL=[[settings objectForKey:@"secure"] boolValue];
        self.enabled=[[settings objectForKey:kEnabled] boolValue];
        
        self.oldStyleSSL=[[settings objectForKey:@"oldstyleSSL"] boolValue];
        self.selfSignedSSL=[[settings objectForKey:@"selfsigned"] boolValue];
        
        
        if([[settings objectForKey:@"domain"] isEqualToString:@"gmail.com"])
        {
            JIDLabel.text=@"GTalk ID";
            self.accountType=kGtalk;
        }
        
    }
    else
    {
        
        if(_originIndex.row==1)
        {
            JIDLabel.text=@"GTalk ID";
            self.server=@"talk.google.com";
            self.jid=@"@gmail.com";
            self.accountType=kGtalk;
        }
        
        self.port=@"5222";
        self.resource=@"Monal-iOS";
        self.useSSL=true;
        
        
        self.oldStyleSSL=NO;
        self.selfSignedSSL=NO;
        
    }
    
    self.sectionArray = @[@"Account", @"Advanced Settings",@""];
    
    self.tableView.backgroundView=nil;
    
    if(!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        [self.tableView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreAccountsDidChangeNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification){
                                                      
                                                      for (NXOAuth2Account *account in [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:self.jid]) {
                                                          
                                                          self.password= account.accessToken.accessToken;
                                                          
                                                      };
                                                      
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreDidFailToRequestAccessNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification){
                                                      NSError *error = [aNotification.userInfo objectForKey:NXOAuth2AccountStoreErrorKey];
                                                      // Do something with the error
                                                  }];
    
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    DDLogVerbose(@"xmpp edit view will appear");
    self.autoSave=YES;
    
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    DDLogVerbose(@"xmpp edit view will hide");
    if(self.autoSave) {
        [self save];
    }
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
    
    
    NSMutableDictionary *dic  = [[NSMutableDictionary alloc] init];
    [dic setObject:domain forKey:kDomain];
    
    
    [dic setObject:user forKey:kUsername];
    [dic setObject:self.server  forKey:kServer];
    [dic setObject:self.port forKey:kPort];
    [dic setObject:self.resource forKey:kResource];
    
    [dic setObject:[NSNumber numberWithBool:self.useSSL] forKey:kSSL];
    [dic setObject:[NSNumber numberWithBool:self.enabled] forKey:kEnabled];
    [dic setObject:[NSNumber numberWithBool:self.selfSignedSSL] forKey:kSelfSigned];
    [dic setObject:[NSNumber numberWithBool:self.oldStyleSSL] forKey:kOldSSL];
    [dic setObject:self.accountno forKey:kAccountID];
    
    BOOL isGtalk=NO;
    if([self.accountType isEqualToString:kGtalk]) {
        isGtalk=YES;
    }
    
    [dic setObject:[NSNumber numberWithBool:isGtalk] forKey:kOauth];
    
    
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
            
            [[DataLayer sharedInstance] addAccountWithDictionary:dic andCompletion:^(BOOL result) {
                if(result) {
                    [[DataLayer sharedInstance] executeScalar:@"select max(account_id) from account" withCompletion:^(NSObject * accountid) {
                        if(accountid) {
                            self.accountno=[NSString stringWithFormat:@"%@",accountid];
                            if(!isGtalk) {
                                PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@-%@",self.accountno,self.jid]];
                                [pass setPassword:self.password] ;
                            }
                            
                            if(self.enabled)
                            {
                                DDLogVerbose(@"calling connect... ");
                                [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
                            }
                            else
                            {
                                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
                            }
                        }
                    }];
                }
            }];
            
        }
    }
    else
    {
        [[DataLayer sharedInstance] updateAccounWithDictionary:dic andCompletion:^(BOOL result) {
            if(!isGtalk) {
                PasswordManager* pass= [[PasswordManager alloc] init:self.accountno];
                [pass setPassword:self.password] ;
            }
            if(self.enabled)
            {
                [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
            }
            else
            {
                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
            }
        }];
        
    }
    
}



-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(buttonIndex==0)
    {
        
        NSArray *accounts= [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:self.jid];
        NXOAuth2Account *oauthAccount;
        if([accounts count]>0)
        {
            oauthAccount= [accounts objectAtIndex:0];
            [[NXOAuth2AccountStore sharedStore] removeAccount:oauthAccount];
        }
        
        //TODO remove password
        self.autoSave=NO;
        [self.db removeAccount:self.accountno];
        [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
        [self.navigationController popViewControllerAnimated:true];
        
    }
}

- (IBAction) delClicked: (id) sender
{
    DDLogVerbose(@"Deleting");
  
    UIActionSheet *popupQuery = [[UIActionSheet alloc] initWithTitle:@"Delete this account?" delegate:self
                                                   cancelButtonTitle:@"No"
                                              destructiveButtonTitle:@"Yes"
                                                   otherButtonTitles:nil, nil];
    
    popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
   [popupQuery showFromTabBar:((UITabBarController*)self.navigationController.parentViewController).tabBar];
    
}



-(void)authenticateWithOAuth
{
    self.password=@""; 
    [[NXOAuth2AccountStore sharedStore] setClientID:@"472865344000-q63msgarcfs3ggiabdobkkis31ehtbug.apps.googleusercontent.com"
                                             secret:@"IGo7ocGYBYXf4znad5Qhumjt"
                                              scope:[NSSet setWithArray:@[@"https://www.googleapis.com/auth/googletalk"]]
                                   authorizationURL:[NSURL URLWithString:@"https://accounts.google.com/o/oauth2/auth"]
                                           tokenURL:[NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/token"]
                                        redirectURL:[NSURL URLWithString:@"urn:ietf:wg:oauth:2.0:oob:auto"]
                                      keyChainGroup:@"MonalGTalk"
                                     forAccountType:self.jid];
    
    [[NXOAuth2AccountStore sharedStore] requestAccessToAccountWithType:self.jid
                                   withPreparedAuthorizationURLHandler:^(NSURL *preparedURL){
                                       
                                       
                                       self.oAuthURL= preparedURL;
                                
                                       MLOAuthViewController *oauthVC = [[MLOAuthViewController alloc] init];
                                       
                                       oauthVC.oAuthURL= self.oAuthURL;
                                       oauthVC.completionHandler=^(NSString *token) {
                                           //  self.password.stringValue = token;
                                           NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"urn:ietf:wg:oauth:2.0:oob:auto?code=%@", token]];
                                           [[NXOAuth2AccountStore sharedStore] handleRedirectURL:url];
                                           
                                       };
                                       self.autoSave=NO;
                                       [self.navigationController pushViewController:oauthVC animated:YES];
                                       
                                       
                                   }];
}


#pragma mark table view datasource methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return 40;
    
}

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
                if([self.accountType isEqualToString:kGtalk]){
                    MLButtonCell *buttonCell =(MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                    UIColor *monalGreen =[UIColor colorWithRed:128.0/255 green:203.0/255 blue:182.0/255 alpha:1.0f];
                    buttonCell.buttonText.textColor= monalGreen;
                    buttonCell.buttonText.text=@"Authenticate";
                    buttonCell.selectionStyle= UITableViewCellSelectionStyleNone;
                    return buttonCell;
                    
                } else  {
                    thecell.cellLabel.text=@"Password";
                    thecell.toggleSwitch.hidden=YES;
                    thecell.textInputField.secureTextEntry=YES;
                    thecell.textInputField.tag=2;
                    thecell.textInputField.text=self.password;
                }
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
    else if (indexPath.section==1)
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
                
        }
        
        
    }
    else if (indexPath.section==2)
    {
        switch (indexPath.row) {
            case 0:
            {
                if(self.editMode==true)
                {
                    
                    MLButtonCell *buttonCell =(MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                    buttonCell.buttonText.text=@"Delete";
                    buttonCell.buttonText.textColor= [UIColor redColor];
                    buttonCell.selectionStyle= UITableViewCellSelectionStyleNone;
                    return buttonCell;
                }
                break;
            }
                
                
        }
    }
    
    
    thecell.textInputField.delegate=self;
    if(thecell.textInputField.hidden==YES)
    {
        [thecell.toggleSwitch addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
    }
    
    thecell.selectionStyle= UITableViewCellSelectionStyleNone;
    
    return thecell;
}



- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
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
    
    if(section==0){
        return 3;
    }
    else if( section ==1) {
        return 6;
    }
    else  if(section == 2&&  self.editMode==false)
    {
        return 0;
    }
    else return 1;
    
    return 0; //default
    
}



#pragma mark table view delegate

//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
    DDLogVerbose(@"selected log section %d , row %d", newIndexPath.section, newIndexPath.row);
    if(newIndexPath.section==0 && newIndexPath.row==1)
    {
        if([self.accountType isEqualToString:kGtalk]){
            [self authenticateWithOAuth];
        }
    }
    else if(newIndexPath.section==2)
    {
        [self delClicked:self];
    }
    
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
