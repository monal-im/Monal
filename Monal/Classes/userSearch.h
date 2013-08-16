//
//  buddylist.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "DataLayer.h"
#import "tools.h"
#import "buddyAdd.h"


@interface userSearch : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate> {

  
    IBOutlet UITableView* currentTable; 
    IBOutlet UISearchDisplayController* searchDisplayController;
   
    NSString* contact;
    NSArray* thelist;
    NSString* accountno;
   
    	
}

-(void) showUsers:(id)sender; 
-(NSInteger) count;


@end


