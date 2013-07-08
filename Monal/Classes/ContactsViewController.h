//
//  ContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>


@interface ContactsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    NSMutableArray* _contacts;
}

@property (nonatomic, strong) UITableView* contactsTable;

@end
