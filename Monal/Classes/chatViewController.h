//
//  chatViewController.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"
#import "HPGrowingTextView.h"


@interface chatViewController : UIViewController <HPGrowingTextViewDelegate,UIWebViewDelegate>{

    UIView *containerView;
    HPGrowingTextView *chatInput;
    
	NSString*  myuser;
	NSString*  lastuser;

	
	CGRect oldFrame;
	NSString* myIcon; 
	NSString* buddyIcon; 
	NSString* buddyFullName; 
	NSString* buddyName; ;
	
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
	
    UIWebView* chatView;
	bool firstmsg;
	bool groupchat;
	
	bool wasaway; 
	bool wasoffline; 
	bool msgthread;
    UIPageControl* pages; 
    NSArray* activeChats; 
 
}

@property (nonatomic,strong)  NSString* buddyName;
@property (nonatomic,strong)  NSString* accountno;

-(id) initWithContact:(NSDictionary*) contact  ;
-(void) showLogDate:(NSString*) buddy:(NSString*) fullname:(UINavigationController*) vc:(NSString*) date;
-(void) addMessage:(NSString*) to:(NSString*) message;


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
-(NSString*) makeMessageHTMLfrom:(NSString*) from withMessage:(NSString*) themessage andTime:(NSString*) time isLive:(BOOL) liveChat;
-(NSString*) emoticonsHTML:(NSString*) message; 

@property (nonatomic,strong) NSString* iconPath;
@property (nonatomic,strong) NSString* domain;
@property (nonatomic,strong) UITabBarController* tabController;
@property (nonatomic,strong)  UITableView* contactList;

/**
 full username with domain e.g. aa@gmail.com
 */
@property (nonatomic, strong) NSString* jid;

/**
 This is the account number of the account this user is for
 */
@property (nonatomic, strong) NSString* accountNo;

@end
