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




@interface chat : UIViewController <UITextViewDelegate,UIWebViewDelegate,UIAlertViewDelegate>{

	 UITextView *chatInput;
	UIWebView* chatView;
	protocol* jabber;
	UINavigationController* navController; 
	
	UITabBarController* tabController; 

	
	//dataset for current chat window
	//NSArray* thelist; 
	
	NSString*  myuser;
	
	NSString*  lastuser;
	
		DataLayer* db;


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
	
	bool firstmsg;
	bool groupchat;
	
	bool wasaway; 
	bool wasoffline; 
	bool msgthread;
}

@property (nonatomic, retain)  NSString* buddyName; 
@property (nonatomic, retain) IBOutlet UITextView *chatInput;
@property (nonatomic, retain) IBOutlet UIWebView* chatView;
@property (nonatomic, retain)  NSString* accountno; 

-(void) init: (protocol*) jabberIn:(UINavigationController*) nav:(NSString*)username: (DataLayer*) thedb; 
-(void) show:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc;
-(void) showLog:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc;
-(void) addMessage:(NSString*) to:(NSString*) message;
-(void) signalNewMessages; 
-(void) signalStatus;
-(void) signalOffline;
-(void) hideKeyboard; 

-(void) htmlonMainThread:(NSString*) theText; 

-(NSString*) setIcon:(NSString*) msguser;


//textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
- (void)textFieldDidBeginEditing:(UITextField *)textField;
- (void)textFieldDidEndEditing:(UITextField *)textField;

-(void) handleInput:(NSString *)text;
//notification 
-(void) keyboardWillShow:(NSNotification *) note;
-(void) keyboardWillHide:(NSNotification *) note;


//content generation 
-(NSMutableString*) createPage:(NSArray*)thelist;
-(NSString*) makeMessageHTML:(NSString*) from:(NSString*) themessage:(NSString*) time:(BOOL) liveChat;
-(NSString*) emoticonsHTML:(NSString*) message; 

@property (nonatomic, retain) NSString* iconPath; 
@property (nonatomic, retain) NSString* domain; 
@property (nonatomic, retain)	UITabBarController* tabController; 
@end
