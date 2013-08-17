//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "ContactDetails.h"


@implementation ContactDetails

#pragma mark view lifecycle
-(void) viewDidLoad
{
    [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];

}

-(void) viewWillAppear:(BOOL)animated
{
    
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

-(IBAction) callPress
{
    // send jingle stuff
    //    [jabber startCallUser:buddyName.text];
    //
    //    call = [callScreen alloc] ;
    //
    //    if([[tools machine] isEqualToString:@"iPad"])
    //    {
    //        call.splitViewController=splitViewController;
    //    }
    //    else
    //    {
    //
    //    call.navigationController=navigationController;
    //    }
    //
    //    [call show:jabber:buddyName.text];
    
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
		if(indexPath.section==1) //bottom
		{
			thecell=_bottomcell;
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
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
	return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	
	
	return 2;
	
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=@"";
    if(section==1)
        toreturn= @"Message";

    return toreturn;
}


-(id) initWithContact:(NSDictionary*) contact
{
	
    self=[super init];
    
    
//	if([domain isEqualToString:@"gmail.com"])
//	{
//		//gtalk
//		_protocolImage.image=[UIImage imageNamed:@"google_g.png"];
//	}
//	else
//        if([domain isEqualToString:@"chat.facebook.com"])
//        {
//            //gtalk
//            _protocolImage.image=[UIImage imageNamed:@"Facebook_big.png"];
//        }
//        else
//        {
//            //xmpp
//            _protocolImage.image=[UIImage imageNamed:@"XMPP.png"];
//        }
	
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
