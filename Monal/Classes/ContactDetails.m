//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "ContactDetails.h"
#import "MLImageManager.h"
#import "MLConstants.h"
#import "CallViewController.h"
#import "MLXMPPManager.h"
#import "MLPortraitNavController.h"


@implementation ContactDetails

#pragma mark view lifecycle
-(void) viewDidLoad
{
    [super viewDidLoad];
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        //        [self.view setBackgroundColor:[UIColor o]];
    }
    else
    {
        [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    
    UIImage *buttonImage2 = [[UIImage imageNamed:@"greenButton"]
                             resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 18, 18)];
    UIImage *buttonImageHighlight2 = [[UIImage imageNamed:@"greenButtonHighlight"]
                                      resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 18, 18)];
    
    [_callButton setBackgroundImage:buttonImage2 forState:UIControlStateNormal];
    [_callButton setBackgroundImage:buttonImageHighlight2 forState:UIControlStateSelected];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _buddyName.text =[_contact objectForKey:@"buddy_name"];
    
    _buddyMessage.text=[_contact objectForKey:@"status"];
    if([ _buddyMessage.text isEqualToString:@"(null)"])  _buddyMessage.text=@"";
    
    _buddyStatus.text=[_contact objectForKey:@"state"];
    if([ _buddyStatus.text isEqualToString:@"(null)"])  _buddyStatus.text=@"";
    
    _fullName.text=[_contact objectForKey:@"full_name"];
    if([ _fullName.text isEqualToString:@"(null)"])  _fullName.text=@"";
    
    NSArray* parts= [_buddyName.text componentsSeparatedByString:@"@"];
    if([parts count]>1)
    {
        NSString* domain= [parts objectAtIndex:1];
    	if([domain isEqualToString:@"gmail.com"])
    	{
    		//gtalk
    		_protocolImage.image=[UIImage imageNamed:@"GTalk"];
    	}
    	else
            
                //xmpp
                _protocolImage.image=[UIImage imageNamed:@"XMPP"];
          
    }
    NSString* accountNo=[NSString stringWithFormat:@"%@", [_contact objectForKey:@"account_id"]];
    UIImage* contactImage=[[MLImageManager sharedInstance] getIconForContact:[_contact objectForKey:@"buddy_name"] andAccount:accountNo];
    _buddyIconView.image=contactImage;
    
    NSArray* resources= [[DataLayer sharedInstance] resourcesForContact:[_contact objectForKey:@"buddy_name"]];
    self.resourcesTextView.text=@"";
    for(NSDictionary* row in resources)
    {
        self.resourcesTextView.text=[NSString stringWithFormat:@"%@\n%@\n",self.resourcesTextView.text, [row objectForKey:@"resource"]];
        
    }
    
    
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

-(IBAction) callContact:(id)sender;
{
    CallViewController *callScreen= [[CallViewController alloc] initWithContact:_contact];
    MLPortraitNavController* callNav = [[MLPortraitNavController alloc] initWithRootViewController:callScreen];
    callNav.navigationBar.hidden=YES;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        callNav.modalPresentationStyle=UIModalPresentationFormSheet;
        [self.popOverController dismissPopoverAnimated:NO];
    }
    
    [self.currentNavController presentModalViewController:callNav animated:YES];
    [[MLXMPPManager sharedInstance] callContact:_contact];
}


#pragma mark tableview stuff

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)] ;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)] ;
    label.text = [self tableView:_theTable titleForHeaderInSection:section];
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView addSubview:label];
    
    // [headerView setBackgroundColor:[UIColor clearColor]];
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        label.textColor=[UIColor darkGrayColor];
        label.text=  label.text.uppercaseString;
        label.shadowColor =[UIColor clearColor];
        label.font=[UIFont systemFontOfSize:[UIFont systemFontSize]];
        
    }
    
    return headerView;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* thecell;
	if(indexPath.section==0) //top
	{
		thecell=_topcell;
	}
	else
		if(indexPath.section==1) //message
		{
			thecell=_bottomcell;
		}
        else if(indexPath.section==2) //resources
        {
            thecell=_resourceCell;
        }
    return thecell;
    
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(indexPath.section==0) //top
	{
		return _topcell.frame.size.height;
	}
	else
		if(indexPath.section==1) //bottom
		{
			return _bottomcell.frame.size.height;
		}
    if(indexPath.section==2) //bottom
    {
        return _resourceCell.frame.size.height;
    }
    
    //default
    return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
	return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    
	return 3;
	
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=@"";
    if(section==1)
        toreturn= @"Message";
    
    if(section==2)
        toreturn= @"Resources";
    
    return toreturn;
}


-(id) initWithContact:(NSDictionary*) contact
{
	
    self=[super init];
    _contact=contact;
    
    self.navigationItem.title=NSLocalizedString(@"Details", @"");
    
    
	
    // see if this user  has  jingle call
    // check caps for audio
    
    //    BOOL hasAudio=NO;
    //
    //    hasAudio=[db checkCap:@"urn:xmpp:jingle:apps:rtp:audio" forUser:buddy accountNo:jabber.accountNumber];
    //
    //
    //    if(!hasAudio)
    //    {
    //        // check legacy cap as well
    //        hasAudio=[db checkLegacyCap:@"voice-v1"  forUser:buddy accountNo:jabber.accountNumber];
    //
    //    }
    //
    //    if(!hasAudio)
    //    {
    //        _callButton.hidden=YES;
    //    }
    
    return self;
    
}



@end
