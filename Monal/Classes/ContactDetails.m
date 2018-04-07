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
#import "MLDetailsTableViewCell.h"


@implementation ContactDetails

#pragma mark view lifecycle
-(void) viewDidLoad
{
    [super viewDidLoad];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[MLXMPPManager sharedInstance] getVCard:_contact];
    self.tableView.rowHeight= UITableViewAutomaticDimension;
    
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

-(IBAction) callContact:(id)sender
{
    [self performSegueWithIdentifier:@"ShowCall" sender:self];
    [[MLXMPPManager sharedInstance] callContact:_contact];
}


-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"ShowCall"])
    {
        CallViewController *callScreen = segue.destinationViewController;
        callScreen.contact=_contact; 
    }
}


#pragma mark tableview stuff

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)] ;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)] ;
    label.text = [self tableView:self.tableView titleForHeaderInSection:section];
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView addSubview:label];
    
    label.textColor=[UIColor darkGrayColor];
    label.text=  label.text.uppercaseString;
    label.shadowColor =[UIColor clearColor];
    label.font=[UIFont systemFontOfSize:[UIFont systemFontSize]];
    
    
    return headerView;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLDetailsTableViewCell* thecell;
  
    switch(indexPath.section) {
        case 0: {
            thecell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"topCell"];
            
            thecell.buddyName.text=[self.contact objectForKey:@"buddy_name"];
            thecell.fullName.text=[self.contact objectForKey:@"buddy_name"];
            thecell.buddyStatus.text=[self.contact objectForKey:@"buddy_name"];
            
            if([thecell.buddyStatus.text isEqualToString:@"(null)"])  thecell.buddyStatus.text=@"";
            if([thecell.fullName.text isEqualToString:@"(null)"])  thecell.fullName.text=@"";
            
            NSString* accountNo=[NSString stringWithFormat:@"%@", [self.contact objectForKey:@"account_id"]];
            [[MLImageManager sharedInstance] getIconForContact:[self.contact objectForKey:@"buddy_name"] andAccount:accountNo withCompletion:^(UIImage *image) {
                thecell.buddyIconView.image=image;
            }];
            
            break;
        }
        case 1: {
            thecell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"bottomCell"];
            thecell.detailTextLabel.text=[_contact objectForKey:@"status"];
            if([  thecell.detailTextLabel.text isEqualToString:@"(null)"])  thecell.detailTextLabel.text=@"";
            break;
        }
        case 2: {
            thecell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"resourceCell"];
            NSArray* resources= [[DataLayer sharedInstance] resourcesForContact:[_contact objectForKey:@"buddy_name"]];
            thecell.detailTextLabel.text=@"";
            for(NSDictionary* row in resources)
            {
                thecell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@\n", thecell.detailTextLabel.text, [row objectForKey:@"resource"]];
            }
            break;
        }
    }
    return thecell;
    
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

-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
