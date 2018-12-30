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
#import "MLContactDetailHeader.h"


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
    self.navigationItem.title=[self.contact objectForKey:@"full_name"];
    
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

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if(section==0) return 2; // table view does not like <=1

    return 30.0;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* thecell;
  
   switch(indexPath.section) {
        case 0: {
            MLContactDetailHeader *detailCell=  (MLContactDetailHeader *)[tableView dequeueReusableCellWithIdentifier:@"headerCell"];

            detailCell.jid.text=[self.contact objectForKey:@"buddy_name"];
//            thecell.fullName.text=[self.contact objectForKey:@"full_name"];
//            thecell.buddyStatus.text=[self.contact objectForKey:@"state"];

//            if([thecell.buddyStatus.text isEqualToString:@"(null)"])  thecell.buddyStatus.text=@"";
//            if([thecell.fullName.text isEqualToString:@"(null)"])  thecell.fullName.text=@"";

            NSString* accountNo=[NSString stringWithFormat:@"%@", [self.contact objectForKey:@"account_id"]];
            [[MLImageManager sharedInstance] getIconForContact:[self.contact objectForKey:@"buddy_name"] andAccount:accountNo withCompletion:^(UIImage *image) {
                detailCell.buddyIconView.image=image;
                detailCell.background.image=image;
            }];

            thecell=detailCell;
            break;
        }
        case 1: {
            MLDetailsTableViewCell *cell=  (MLDetailsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"MessageCell"];
            cell.cellDetails.text=[_contact objectForKey:@"status"];
            if([cell.cellDetails.text isEqualToString:@"(null)"])  cell.cellDetails.text=@"";
            thecell=cell;
            break;
        }
        case 2: {
            thecell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Sub"];
            if(indexPath.row==1) {
                thecell.textLabel.text=@"Resources"; //if muc change to participants
            } else  {
                thecell.textLabel.text=@"Encryption Keys"; //if muc change to participants
            }
            thecell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
   }
    return thecell;
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    if(section==2) return 2;
    else  return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    
	return 3;
	
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=nil; 
    if(section==1)
        toreturn= @"Status Message";
    
    if(section==2)
        toreturn= @"Connection Details";
    
    return toreturn;
}


-(id) initWithContact:(NSDictionary*) contact
{
    self=[super init];
    _contact=contact;
    return self;
}

-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
