//
//  buddylist.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "chat.h"
#import "xmpp.h"
#import "buddyDetails.h"
#import "tools.h"
#import "CustomCell.h"




@interface buddylist : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate> {

	
	
	chat* chatwin;
	
	NSIndexPath* currentPath; 
	UITableView* currentTable; 
		
	
	
	
    
    BOOL refresh; 
   
	
	
}


//table view delegat methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath;
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;


- (void)setEditing:(BOOL)editing animated:(BOOL)animated;



//table view datasource methods
//required
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;

//table manipulation functions


//others
-(void)initList:(chat*) chatWin; 
-(void) dealloc;


//buddylist functions
-(NSArray*) update:(NSArray*) list;
-(NSArray*) add:(NSArray*) list:(NSArray*) dblist;
-(NSArray*) remove:(NSArray*) list:(NSArray*) dblist;
-(int) indexofString:(NSString*)name;

-(NSArray*) addOffline:(NSArray*) list:(NSArray*) dblist;
-(NSArray*) removeOffline:(NSArray*) list:(NSArray*) dblist;
-(int) indexofStringOffline:(NSString*)name;


-(void) setList:(NSArray*) list; 
-(void) setOfflineList:(NSArray*) list; 

-(void) showChatForUser:(NSString*)user withFullName:(NSString*)fullname;

-(NSInteger) count;

@property (nonatomic,strong) NSArray* theOfflineList;
@property (nonatomic,strong) NSArray* thelist;
@property (nonatomic,strong)  protocol* jabber;
@property (nonatomic, strong) NSString* iconPath;

@property (nonatomic,strong) UITabBarController* tabcontroller;
@property (nonatomic,strong) UIBarButtonItem* plusButton;
@property (nonatomic,strong)  UINavigationController* viewController;

@property (nonatomic, strong)MGSplitViewController* splitViewController;
@property (nonatomic) BOOL refresh;

@end


