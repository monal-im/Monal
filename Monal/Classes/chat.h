//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "protocol.h"
#import "DataLayer.h"
#import "tools.h"
#import "HPGrowingTextView.h"




@interface chat : UIViewController <HPGrowingTextViewDelegate,UIWebViewDelegate,UIAlertViewDelegate>{

	
    protocol* jabber;
	UINavigationController* navController; 
	
	UITabBarController* tabController; 
     UIBarButtonItem* contactsButton; // ipad portrait button 
     UIPopoverController *popOverController;
    
    UIView *containerView;
    HPGrowingTextView *chatInput;
    
    UITableView* contactList; 
    
    
	//dataset for current chat window
	//NSArray* thelist; 
	
	NSString*  myuser;
	
	NSString*  lastuser;
	
		DataLayer* db;
    bool dontscroll;
    
    bool keyboardVisible; 

	 NSString* iconPath; 
	 NSString* domain; 
	
	CGRect oldFrame;
	NSString* myIcon; 
	NSString* buddyIcon; 
	NSString* buddyFullName; 
	NSString* buddyName; ;
	
	NSString* accountno; 
	
	NSMutableString* HTMLPage; 
	
	NSString* topHTML; 
	NSString* bottomHTML; 
	NSMutableString* inHTML; 
	NSMutableString* outHTML; 
	
	NSMutableString* inNextHTML; 
	NSMutableString* outNextHTML; 
	
	NSMutableString* statusHTML; 

	NSString* webroot;
	NSString* lastFrom; 
	NSString* lastDiv; 
	
	IBOutlet  UIActivityIndicatorView* spinner;
    UIWebView* chatView;
	bool firstmsg;
	bool groupchat;
	
	bool wasaway; 
	bool wasoffline; 
	bool msgthread;
    UIPageControl* pages; 
    NSArray* activeChats; 
 
}

@property (nonatomic)  NSString* buddyName; 


@property (nonatomic)  NSString* accountno; 

-(void) init: (protocol*) jabberIn:(UINavigationController*) nav:(NSString*)username: (DataLayer*) thedb; 
-(void) show:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc;
-(void) showLogDate:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc:(NSString*) date;
-(void) addMessage:(NSString*) to:(NSString*) message;
-(void) signalNewMessages; 
-(void) signalStatus;
-(void) signalOffline;
-(void) hideKeyboard; 



-(NSString*) setIcon:(NSString*) msguser;


#pragma mark gesture stuff

-(void) showSignal:(NSNotification*) note; 
- (void)swipeDetected:(UISwipeGestureRecognizer *)recognizer;



-(void) handleInput:(NSString *)text;
//notification 
-(void) keyboardWillShow:(NSNotification *) note;
-(void) keyboardWillHide:(NSNotification *) note;


//content generation 
-(NSMutableString*) createPage:(NSArray*)thelist;
-(NSString*) makeMessageHTML:(NSString*) from:(NSString*) themessage:(NSString*) time:(BOOL) liveChat;
-(NSString*) emoticonsHTML:(NSString*) message; 

@property (nonatomic) NSString* iconPath; 
@property (nonatomic) NSString* domain; 
@property (nonatomic)	UITabBarController* tabController; 
@property (nonatomic)  UITableView* contactList;

@end
