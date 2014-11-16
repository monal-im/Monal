//
//  SettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "SettingsViewController.h"
#import "MLConstants.h"
#import "DataLayer.h"


@interface SettingsViewController ()

@end

@implementation SettingsViewController

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
   
    _settingsTable=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _settingsTable.delegate=self;
    _settingsTable.dataSource=self;
    _settingsTable.backgroundView=nil;
    
    self.view=_settingsTable;
    self.tableView=_settingsTable;
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        
    }
    else
    {
        [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
//    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"6.0"))
//    {
//    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setColor:[UIColor whiteColor]];
//    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setShadowColor:nil];
//    }
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
    return 4;
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
            return 3; // removed staus ipod for now
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
                case 3:
                {
                    cell.textLabel.text=NSLocalizedString(@"Status iPod 🎵", @"");
                       cell.defaultKey=@"MusicStatus";
                    cell.switchEnabled=YES;
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
            
            
        default:
        {
            
        }
            break;
    }

    return nil;
}






@end
