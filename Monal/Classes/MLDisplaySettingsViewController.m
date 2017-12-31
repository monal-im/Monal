//
//  SettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "MLDisplaySettingsViewController.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import <DropboxSDK/DropboxSDK.h>


@interface MLDisplaySettingsViewController ()

@end

@implementation MLDisplaySettingsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"Settings",@"");
   
    _settingsTable=self.tableView;
    _settingsTable.delegate=self;
    _settingsTable.dataSource=self;
    _settingsTable.backgroundView=nil;
    

}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[NSUserDefaults standardUserDefaults] setBool:[DBSession sharedSession].isLinked forKey:@"DropBox"];

}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    //update logs if needed
   if(! [[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"])
   {
       [[DataLayer sharedInstance] messageHistoryCleanAll];
   }
  
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark tableview datasource delegate
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 5;
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
    switch (section) {
        case 0:
        {
            return @"Status";
            break;
        }
            
        case 1:
        {
            return @"Presence";
            break;
        }
            
        case 2:
        {
            return @"Alerts";
            break;
        }
            
        case 3:
        {
            return @"General";
            break;
        }
            
        case 4:
        {
            return @"Cloud Storage";
            break;
        }
            
        default:
        {
            return  nil;
        }
            break;
    }
}




- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return 1;
            break;
        }
            
        case 1:
        {
            return 3;
            break;
        }
            
        case 2:
        {
            return 1;
            break;
        }
            
        case 3:
        {
            return 4;
            break;
        }
          
            
        case 4:
        {
            return 1;
            break;
        }
            
        default:
        {
            return 0; 
        }
            break;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    MLSettingCell* cell=[[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
    cell.parent= self;
   
    switch (indexPath.section) {
        case 0:
        {
            
            cell.textInputField.placeholder=NSLocalizedString(@"Status Message", @"");
            cell.textInputField.keyboardType=UIKeyboardTypeAlphabet;
            cell.defaultKey=@"StatusMessage";
            cell.textEnabled=YES;
            return cell; 
            break;
        }
   
        case 1:
        {
            
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Away", @"");
                    cell.defaultKey=@"Away";
                    cell.switchEnabled=YES;
                    break;
                }
                case 1:
                {
                    cell.textLabel.text=NSLocalizedString(@"Visible", @"");
                    cell.defaultKey=@"Visible";
                    cell.switchEnabled=YES;
                    break;
                }
                case 2:
                {
                    cell.textLabel.text=NSLocalizedString(@"XMPP Priority", @"");
                    cell.textInputField.placeholder=NSLocalizedString(@"Number", @"");
                    cell.textInputField.keyboardType=UIKeyboardTypeNumbersAndPunctuation;
                       cell.defaultKey=@"XMPPPriority";
                    cell.textEnabled=YES;
                    break;
                }
               
                    
                  
            }
             return cell; 
            break;
        }
            
        case 2:
        {
            cell.textLabel.text=NSLocalizedString(@"Sound Alerts", @"");
               cell.defaultKey=@"Sound";
            cell.switchEnabled=YES;
              return cell;
            break;
        }
            
        case 3:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Message Preview", @"");
                    cell.defaultKey=@"MessagePreview";
                    cell.switchEnabled=YES;
                    break; 
                }
                case 1:
                {
                    cell.textLabel.text=NSLocalizedString(@"Log Chats", @"");
                    cell.defaultKey=@"Logging";
                    cell.switchEnabled=YES;
                    break;
                }
                case 2:
                {
                    cell.textLabel.text=NSLocalizedString(@"Offline Contacts", @"");
                       cell.defaultKey=@"OfflineContact";
                    cell.switchEnabled=YES;
                    break;
                }
                case 3:
                {
                    cell.textLabel.text=NSLocalizedString(@"Sort By Status", @"");
                       cell.defaultKey=@"SortContacts";
                    cell.switchEnabled=YES;
                    break;
                }
            }
            return cell; 
            break;
        }
           
        case 4:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Connect DropBox", @"");
                    cell.defaultKey=@"DropBox";
                    cell.switchEnabled=YES;
                    break;
                }
            }
            return cell;
            break;
        }
            
        default:
        {
            
        }
            break;
    }

    return nil;
}


-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}



@end
