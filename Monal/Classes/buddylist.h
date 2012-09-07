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

		NSMutableArray* thelist; 
	NSMutableArray* theOfflineList; 
	
	chat* chatwin;
	
	NSIndexPath* currentPath; 
	UITableView* currentTable; 
	protocol* jabber;	
	NSString* iconPath; 
	
	UIBarButtonItem* plusButton; 
	UINavigationController* viewController; 

	UITabBarController* tabcontroller;
    
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



-(NSInteger) count;

@property (nonatomic) NSArray* theOfflineList;
@property (nonatomic) NSArray* thelist;
@property (nonatomic)  protocol* jabber;
@property (nonatomic) NSString* iconPath; 

@property (nonatomic) UITabBarController* tabcontroller;
@property (nonatomic) UIBarButtonItem* plusButton;
@property (nonatomic)  UINavigationController* viewController; 

@property MGSplitViewController* splitViewController; 
@property (nonatomic) BOOL refresh; 

@end


