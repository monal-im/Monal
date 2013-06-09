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


#import "MBProgressHud.h"
#import "Appirater.h"



@interface SworIMAppDelegate : UIViewController <UIApplicationDelegate, 
UINavigationControllerDelegate,UIAlertViewDelegate, UISplitViewControllerDelegate> {
    
    IBOutlet UIWindow *window;
    IBOutlet  UINavigationController *buddyNavigationController;
    IBOutlet  UINavigationController *statusNavigationController;
  
	
	
	// ipad specific stuff

	IBOutlet UISplitViewController* split; 


	IBOutlet UITabBarItem* buddyTab; 

	
	IBOutlet UITableView* buddyTable; 

	
    IBOutlet statusControl* statuscon; 
	IBOutlet GroupChat* joinGroup;
    
    IBOutlet buddylist* buddylistDS;
    
	MBProgressHUD* loginProgressHud;

	TabMoreController* moreControl;

    
   
    callScreen* call;
    
    
	bool vibrateenabled; 
    bool uithreadrunning; 
	
	

  
	Reachability* reach;

	DataLayer* db;

	
	UITextField* nameField;
	BOOL listLoad;  
	

	int uiIter; 
	
	
	BOOL connectLock;
	
	BOOL screenLock; 
	BOOL backGround; 
	
	UIBackgroundTaskIdentifier bgTask ;
	
	bool idleMsgShown; 
	NSTimer* suspendTimer; 
	
	NSString * lasttitle; 
	
	
	

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


@property (nonatomic, retain)  chat* chatwin;
@property (nonatomic, retain )  protocol* jabber;
@property (nonatomic, retain) NSString* accountno;
@property (nonatomic, weak)  UINavigationController* morenav;
@property (nonatomic, assign)  UINavigationController* activeNavigationController; 
@property (nonatomic, assign)  UINavigationController* accountsNavigationController; 

@property (nonatomic, assign)  UINavigationController* logsNavigationControlleriPad; 
@property (nonatomic, assign)  UINavigationController* aboutNavigationControlleriPad; 

@property (nonatomic, strong)  NSString* iconPath;
@property (nonatomic, assign) UITabBarItem* activeTab; 
@property (nonatomic, retain)IBOutlet UITabBarController* tabcontroller;



@end

