//
//  SettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "SettingsViewController.h"

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
    [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setColor:[UIColor whiteColor]];
    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setShadowColor:nil];
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return @"Current Status";
            break;
        }
            
        case 1:
        {
            return @"Set Status";
            break;
        }
            
        case 2:
        {
            return @"Presence";
            break;
        }
            
        case 3:
        {
            return @"Alerts";
            break;
        }
            
        case 4:
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
            return 1;
            break;
        }
            
        case 2:
        {
            return 4;
            break;
        }
            
        case 3:
        {
            return 1;
            break;
        }
            
        case 4:
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
            //own image
            return cell;
            break;
        }
        case 1:
        {
            cell.textEnabled=YES;
            cell.textField.placeholder=NSLocalizedString(@"Status Message", @"");
            return cell;
            break;
        }
            
        case 2:
        {
            
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Away", @"");
                    cell.switchEnabled=YES;
                    break;
                }
                case 1:
                {
                    cell.textLabel.text=NSLocalizedString(@"Visible", @"");
                    cell.switchEnabled=YES;
                    break;
                }
                case 2:
                {
                    cell.textLabel.text=NSLocalizedString(@"XMPP Priority", @"");
                    cell.textField.placeholder=NSLocalizedString(@"Number", @"");
                    cell.textField.keyboardType=UIKeyboardTypeNumbersAndPunctuation;
                    cell.textEnabled=YES;
                    break;
                }
                case 3:
                {
                    cell.textLabel.text=NSLocalizedString(@"Status iPod 🎵", @"");
                    cell.switchEnabled=YES;
                    break;
                }
                    
                  
            }
             return cell; 
            break;
        }
            
        case 3:
        {
            cell.textLabel.text=NSLocalizedString(@"Sound Alerts", @"");
            cell.switchEnabled=YES;
              return cell;
            break;
        }
            
        case 4:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Message Preview", @"");
                    cell.switchEnabled=YES;
                    break; 
                }
                case 1:
                {
                    cell.textLabel.text=NSLocalizedString(@"Log Chats", @"");
                    cell.switchEnabled=YES;
                    break;
                }
                case 2:
                {
                    cell.textLabel.text=NSLocalizedString(@"Offline Contacts", @"");
                    cell.switchEnabled=YES;
                    break;
                }
                case 3:
                {
                    cell.textLabel.text=NSLocalizedString(@"Sort By Status", @"");
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
