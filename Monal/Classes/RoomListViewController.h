//
//  RoomLitViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 10/8/13.
//
//

#import <UIKit/UIKit.h>

@interface RoomListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    IBOutlet UITableView* _tableView;
    NSArray* _roomList; // this should be an item list stle array from xmpp 
}

-(id) initWithRoomList:(NSArray*) roomList;

@end
