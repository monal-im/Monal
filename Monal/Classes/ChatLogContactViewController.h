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
{
    NSString* _accountId;
    NSDictionary* _contact;
    NSArray* _tableData;
}

-(id) initWithAccountId:(NSString*) accountId andContact: (NSDictionary*) contact;

@end
