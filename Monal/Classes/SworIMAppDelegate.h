//
//  SworIMAppDelegate.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>

#import "xmpp.h"
#import "AIMTOC2.h"
#import "buddylist.h"
#import  "chat.h"
#import "DataLayer.h"

#import "Reachability.h"
#import "buddyAdd.h"

#import "SlidingMessageViewController.h"
#import "TabMoreController.h"
#import "StatusControl.h"

#import "GroupChat.h"
#import "askTempPass.h"
#import "PasswordManager.h"


@interface SworIMAppDelegate : UIViewController <UIApplicationDelegate, 
UINavigationControllerDelegate,UIAlertViewDelegate> {
    
    IBOutlet UIWindow *window;
   IBOutlet  UINavigationController *buddyNavigationController;
	  IBOutlet  UINavigationController *accountsNavigationController;
	  IBOutlet  UINavigationController *statusNavigationController;
	  IBOutlet  UINavigationController *activeNavigationController;
	
	
	// ipad specific stuff
	IBOutlet  UINavigationController *aboutNavigationControlleriPad;
	IBOutlet  UINavigationController *logsNavigationControlleriPad;
	IBOutlet UISplitViewController* split; 


	IBOutlet UITableView* buddyTable1; //same as noral one 
	IBOutlet UITableView* buddyTable2; // extra ipad one
	
	
	IBOutlet UITabBarController *tabcontroller; 
	IBOutlet UITabBarItem* buddyTab; 
	IBOutlet UITabBarItem* activeTab; 
	
	
	IBOutlet UITableView* buddyTable; 

	
    IBOutlet statusControl* statuscon; 
	IBOutlet GroupChat* joinGroup; 
	
	

	
	bool vibrateenabled; 
    bool uithreadrunning; 
	
	protocol* jabber;
	IBOutlet buddylist* buddylistDS;
	

	chat* chatwin;

	Reachability* reach; 

	DataLayer* db;
	NSString* iconPath; 
	
IBOutlet	UIView* activityView;
IBOutlet	UILabel* activityMsg;
IBOutlet	UIActivityIndicatorView* activitySun; 

	UITextField* nameField;
	BOOL listLoad;  
	
	
	

	
	NSString* accountno;
	
	int uiIter; 
	
	
	BOOL connectLock;
	
	BOOL screenLock; 
	BOOL backGround; 
	
	UIBackgroundTaskIdentifier bgTask ;
	
	bool idleMsgShown; 
	NSTimer* suspendTimer; 
	
	NSString * lasttitle; 
	
	TabMoreController* moreControl; 
	UINavigationController* morenav;
	

	bool playing; 
	bool buddylistdirty;
    
    NSString* tempPass; 
	
}



-(void) toggleiPadBuddyList;

-(void) toggleMusic;
- (void)handleNowPlayingItemChanged ;
- (void)handleNowPlayingItemStateChanged ;

-(void) uiUpdater;
-(void) keepAlive;
-(void) Connect; 
-(void) reconnect;

-(void) addBuddy;


-(void) reloadBuddies:(NSArray*) indexpaths;

-(void) setTempPass:(NSString*) thePass; 

-(IBAction) CancelLogin;

@property (nonatomic, retain) DataLayer* db;
@property (nonatomic, retain)  chat* chatwin;
@property (nonatomic, retain)  protocol* jabber;
@property (nonatomic, retain) NSString* accountno; 
@property (nonatomic, retain)  UINavigationController* morenav; 
@property (nonatomic, retain)  UINavigationController* activeNavigationController; 
@property (nonatomic, retain)  UINavigationController* accountsNavigationController; 

@property (nonatomic, retain)  UINavigationController* logsNavigationControlleriPad; 
@property (nonatomic, retain)  UINavigationController* aboutNavigationControlleriPad; 

@property (nonatomic, retain)  NSString* iconPath; 
@property (nonatomic,retain) UITabBarItem* activeTab; 
@property (nonatomic,retain)IBOutlet UITabBarController* tabcontroller; 



@end

