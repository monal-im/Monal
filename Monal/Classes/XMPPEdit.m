//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "MLSwitchCell.h"
#import "MLButtonCell.h"
#import "MBProgressHUD.h"
#import "MLServerDetails.h"
#import "MLMAMPrefTableViewController.h"
#import "MLKeysTableViewController.h"
#import "MLPasswordChangeTableViewController.h"

#import "tools.h"




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
@property (nonatomic, assign) BOOL airDrop;

@property (nonatomic, weak) UITextField *currentTextField;
@property (nonatomic, strong) NSURL *oAuthURL;

@property (nonatomic, strong) NSDictionary *initialSettings;


@end


@implementation XMPPEdit


-(void) hideKeyboard
{
    [self.currentTextField resignFirstResponder];
}

#pragma mark view lifecylce

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell"
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
        [_db detailsForAccount:_accountno withCompletion:^(NSArray *result) {
            
            if(result.count==0 )
            {
                //present another UI here.
                return;
                
            }
            
            NSDictionary* settings=[result objectAtIndex:0]; //only one row
            self.initialSettings=settings;
            
            self.jid=[NSString stringWithFormat:@"%@@%@",[settings objectForKey:@"username"],[settings objectForKey:@"domain"]];
            
            NSString*pass= [SAMKeychain passwordForService:@"Monal" account:[NSString stringWithFormat:@"%@",self.accountno]];
            
            if(pass) {
                self.password =pass;
            }
            
            self.server=[settings objectForKey:@"server"];
            
            self.port=[NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
            // self.resource=[settings objectForKey:@"resource"];
            
            self.useSSL=[[settings objectForKey:@"secure"] boolValue];
            self.enabled=[[settings objectForKey:kEnabled] boolValue];
            
            self.oldStyleSSL=[[settings objectForKey:@"oldstyleSSL"] boolValue];
            self.selfSignedSSL=[[settings objectForKey:@"selfsigned"] boolValue];
            self.airDrop = [[settings objectForKey:kAirdrop] boolValue];
            
            if([[settings objectForKey:@"domain"] isEqualToString:@"gmail.com"])
            {
                self->JIDLabel.text=@"GTalk ID";
                self.accountType=kGtalk;
            }
        }];
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
        self.useSSL=true;
        srand([[NSDate date] timeIntervalSince1970]);
        self.resource=[NSString stringWithFormat:@"Monal-iOS.%d",rand()%100];
        
        
        self.oldStyleSSL=NO;
        self.selfSignedSSL=NO;
        
    }
    
    self.sectionArray = @[@"Account", @"Advanced Settings",@""];
    
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

}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark actions

-(IBAction) save:(id) sender
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

    if(user) [dic setObject:user forKey:kUsername];

    if(self.server) {
        [dic setObject:self.server  forKey:kServer];
    }
    if(self.port ) {
        [dic setObject:self.port forKey:kPort];
    }
    
    NSString *resource=[NSString stringWithFormat:@"Monal-iOS.%d",rand()%100];

    [dic setObject:resource forKey:kResource];

    [dic setObject:[NSNumber numberWithBool:self.useSSL] forKey:kSSL];
    [dic setObject:[NSNumber numberWithBool:self.enabled] forKey:kEnabled];
    [dic setObject:[NSNumber numberWithBool:self.selfSignedSSL] forKey:kSelfSigned];
    [dic setObject:[NSNumber numberWithBool:self.oldStyleSSL] forKey:kOldSSL];
    [dic setObject:[NSNumber numberWithBool:self.airDrop] forKey:kAirdrop];
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
            [[DataLayer sharedInstance] doesAccountExistUser:user andDomain:domain withCompletion:^(BOOL result) {
                if(!result) {
                    [[DataLayer sharedInstance] addAccountWithDictionary:dic andCompletion:^(BOOL result) {
                        if(result) {
                            [self showSuccessHUD];
                            [[DataLayer sharedInstance] accountIDForUser:user andDomain:domain withCompletion:^(NSString* accountid) {
                                if(accountid) {
                                    self.accountno=[NSString stringWithFormat:@"%@",accountid];
                                    self.editMode=YES;
                                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                                    [SAMKeychain setPassword:self.password forService:@"Monal" account:self.accountno];
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
                } else  {
                    dispatch_async(dispatch_get_main_queue(), ^{
                   UIAlertController* alert= [UIAlertController alertControllerWithTitle:@"Account Exists" message:@"This account already exists in Monal." preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    }]];

                    [self presentViewController:alert animated:YES completion:^{

                    }];

                    });
                }
            }];
        }
    }
    else
    {
        [[DataLayer sharedInstance] updateAccounWithDictionary:dic andCompletion:^(BOOL result) {

            [[MLXMPPManager sharedInstance] updatePassword:self.password forAccount:self.accountno];
            if(self.enabled)
            {
                [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
            }
            else
            {
                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
            }
            
            if(self.airDrop != [[self.initialSettings objectForKey:kAirdrop] boolValue])
            {
                xmpp *account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
                account.airDrop=self.airDrop;
                
                 [[MLXMPPManager sharedInstance] connectAccount:self.accountno]; //we "connect" 
            }
            
            [self showSuccessHUD];
        }];

        [[DataLayer sharedInstance] resetContactsForAccount:self.accountno];

    }
}

-(void) showSuccessHUD
{
    dispatch_async(dispatch_get_main_queue(), ^{
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeCustomView;
        hud.removeFromSuperViewOnHide=YES;
        hud.label.text =@"Success";
        hud.detailsLabel.text =@"The account has been saved";
        UIImage *image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        hud.customView = [[UIImageView alloc] initWithImage:image];

        [hud hideAnimated:YES afterDelay:1.0f];
    });
}

- (IBAction) delClicked: (id) sender
{
    DDLogVerbose(@"Deleting");

    UIAlertController *questionAlert =[UIAlertController alertControllerWithTitle:@"Delete Account" message:@"This will remove this account and the associated data from this device." preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *noAction =[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {

    }];

    UIAlertAction *yesAction =[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {

        [SAMKeychain deletePasswordForService:@"Monal"  account:[NSString stringWithFormat:@"%@",self.accountno]];
        [self.db removeAccount:self.accountno];
        [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];


        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeCustomView;
        hud.removeFromSuperViewOnHide=YES;
        hud.label.text =@"Success";
        hud.detailsLabel.text =@"The account has been deleted";
        UIImage *image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        hud.customView = [[UIImageView alloc] initWithImage:image];

        [hud hideAnimated:YES afterDelay:1.0f];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });

    }];

    [questionAlert addAction:noAction];
    [questionAlert addAction:yesAction];
    questionAlert.popoverPresentationController.sourceView=sender;

    [self presentViewController:questionAlert animated:YES completion:nil];

}

#pragma mark table view datasource methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return 40;

}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DDLogVerbose(@"xmpp edit view section %ld, row %ld", indexPath.section, indexPath.row);

    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];

    // load cells from interface builder
    if(indexPath.section==0)
    {
        //the user
        switch (indexPath.row)
        {
            case 0: {
                thecell.cellLabel.text=@"Jabber ID";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.tag=1;
                thecell.textInputField.keyboardType = UIKeyboardTypeEmailAddress;
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
                thecell.accessoryType=UITableViewCellAccessoryDetailButton;
                break;
            }

            case 1:  {
                thecell.cellLabel.text=@"Port";
                thecell.toggleSwitch.hidden=YES;
                thecell.textInputField.tag=4;
                thecell.textInputField.text=self.port;
                break;
            }

            case 2: {
                thecell.cellLabel.text=@"TLS";
                thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=2;
                thecell.toggleSwitch.on=self.useSSL;
                break;
            }
            case 3: {
                thecell.cellLabel.text=@"Old Style TLS";
                thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=3;
                thecell.toggleSwitch.on=self.oldStyleSSL;
                break;
            }
            case 4: {
                thecell.cellLabel.text=@"Validate certificate";
                thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=4;
                thecell.toggleSwitch.on=!self.selfSignedSSL;
                break;
            }
            case 5: {
                thecell.cellLabel.text=@"Message Archive Pref";
                thecell.toggleSwitch.hidden=YES;

                thecell.textInputField.hidden=YES;
                thecell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            case 6: {
                thecell.cellLabel.text=@"My Keys";
                thecell.toggleSwitch.hidden=YES;

                thecell.textInputField.hidden=YES;
                thecell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            case 7: {
                thecell.cellLabel.text=@"Change Password";
                thecell.toggleSwitch.hidden=YES;

                thecell.textInputField.hidden=YES;
                thecell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            case 8: {
                thecell.cellLabel.text=@"Use AirDrop";
                thecell.textInputField.hidden=YES;
                thecell.toggleSwitch.tag=5;
                thecell.toggleSwitch.on=self.airDrop;
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

    tempLabel.textColor=[UIColor darkGrayColor];
    tempLabel.text=  tempLabel.text.uppercaseString;
    tempLabel.shadowColor =[UIColor clearColor];
    tempLabel.font=[UIFont systemFontOfSize:[UIFont systemFontSize]];

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
        return 9;
    }
    else  if(section == 2&&  self.editMode==false)
    {
        return 0;
    }
    else return 1;

    return 0; //default

}

#pragma mark -  table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
    DDLogVerbose(@"selected log section %ld , row %ld", newIndexPath.section, newIndexPath.row);
    if(newIndexPath.section==0 && newIndexPath.row==1)
    {
        if([self.accountType isEqualToString:kGtalk]){
            [self authenticateWithOAuth];
        }
    }
    else if (newIndexPath.section==1)
    {  switch (newIndexPath.row)
        {
            case 5:  {
                [self performSegueWithIdentifier:@"showMAMPref" sender:self];
                break;
            }case 6:  {
                [self performSegueWithIdentifier:@"showKeyTrust" sender:self];
                break;
            }
            case 7:  {
                [self performSegueWithIdentifier:@"showPassChange" sender:self];
                break;
            }
        }
    }
    else if(newIndexPath.section==2)
    {
        [self delClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
    }

}

-(void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section==1)
    {
        switch (indexPath.row)
        {

            case 0:  {
                [self performSegueWithIdentifier:@"showServerDetails" sender:self];
            }

        }
    }
}


#pragma mark - segeue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"showServerDetails"])
    {
        MLServerDetails *server= (MLServerDetails *)segue.destinationViewController;
        server.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
    }

    else if ([segue.identifier isEqualToString:@"showMAMPref"])
    {
        MLMAMPrefTableViewController *mam= (MLMAMPrefTableViewController *)segue.destinationViewController;
        mam.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
    }
    else if ([segue.identifier isEqualToString:@"showKeyTrust"])
    {
        if(self.jid && self.accountno) {
            MLKeysTableViewController *keys= (MLKeysTableViewController *)segue.destinationViewController;
            keys.ownKeys = YES;
            MLContact *contact = [[MLContact alloc] init];
            contact.contactJid=self.jid;
            contact.accountId=self.accountno;
            keys.contact=contact;
        }
    }
    else if ([segue.identifier isEqualToString:@"showPassChange"])
    {
        if(self.jid && self.accountno) {
            MLPasswordChangeTableViewController *pwchange= (MLPasswordChangeTableViewController *)segue.destinationViewController;
           pwchange.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
        }
    }


}

#pragma mark -  text input  fielddelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    self.currentTextField=textField;
    if(textField.tag==1) //user input field
    {
        if(textField.text.length >0) {
            UITextPosition *startPos=  textField.beginningOfDocument;
            UITextRange *newRange = [textField textRangeFromPosition:startPos toPosition:startPos];

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
                self.selfSignedSSL=NO;
            }
            else {
                self.selfSignedSSL=YES;
            }

            break;
        }

        case 5: {
            if(toggle.on)
            {
                self.airDrop=YES;
            }
            else {
                self.airDrop=NO;
            }

            break;
        }
    }


}


@end
