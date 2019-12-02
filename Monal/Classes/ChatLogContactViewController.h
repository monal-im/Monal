//
//  ChatLogContactViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/12/13.
//
//

#import <UIKit/UIKit.h>
#import "DataLayer.h"

@interface ChatLogContactViewController : UITableViewController

@property (nonatomic, strong) MLContact* contact;
@property (nonatomic, strong) NSArray* tableData;

@end
