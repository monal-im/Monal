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
#import "CallScreen.h"

#import "PasswordManager.h"

#import "MGSplitViewController.h"
#import "MBProgressHud.h"




@interface SworIMAppDelegate : UIViewController <UIApplicationDelegate, 
UINavigationControllerDelegate,UIAlertViewDelegate, MGSplitViewControllerDelegate> {
    
    IBOutlet UIWindow *window;
   IBOutlet  UINavigationController *buddyNavigationController;
	  IBOutlet  UINavigationController *accountsNavigationController;
	  IBOutlet  UINavigationController *statusNavigationController;
	  IBOutlet  UINavigationController *activeNavigationController;
	
	
	// ipad specific stuff
	IBOutlet  UINavigationController *aboutNavigationControlleriPad;
	IBOutlet  UINavigationController *logsNavigationControlleriPad;
	IBOutlet MGSplitViewController* split; 



	
	
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
    callScreen* call;
    
	Reachability* reach;

	DataLayer* db;
	NSString* iconPath; 
	


	UITextField* nameField;
	BOOL listLoad;  
	
	MBProgressHUD* loginProgressHud;
	

	
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


-(void) showCall:(NSNotification*) notification;
-(void) dismissCall;

-(void) reloadBuddies:(NSArray*) indexpaths;

-(void) setTempPass:(NSString*) thePass; 

-(IBAction) CancelLogin;


@property (nonatomic)  chat* chatwin;
@property (nonatomic)  protocol* jabber;
@property (nonatomic) NSString* accountno; 
@property (nonatomic)  UINavigationController* morenav; 
@property (nonatomic)  UINavigationController* activeNavigationController; 
@property (nonatomic)  UINavigationController* accountsNavigationController; 

@property (nonatomic)  UINavigationController* logsNavigationControlleriPad; 
@property (nonatomic)  UINavigationController* aboutNavigationControlleriPad; 

@property (nonatomic)  NSString* iconPath; 
@property (nonatomic) UITabBarItem* activeTab; 
@property (nonatomic)IBOutlet UITabBarController* tabcontroller; 



@end

