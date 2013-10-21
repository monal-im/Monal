//
//  RoomLitViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 10/8/13.
//
//

#import "RoomListViewController.h"

@interface RoomListViewController ()

@end

@implementation RoomListViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(id) initWithRoomList:(NSArray*) roomList
{
    self=[super init];
    _roomList=roomList;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    self.navigationItem.title=@"Chat Rooms";
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark tableview datasource delegate


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_roomList count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"RoomCell"];
    
    cell.textLabel.text=[[_roomList objectAtIndex:indexPath.row] objectForKey:@"name"];

    return cell;

}


@end
