//
//  chatViewController.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
// 

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#import "DataLayer.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLNotificationManager.h"
#import "MLChatCell.h"
#import "MLResizingTextView.h"


@interface chatViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextViewDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate>
{
    UIView *containerView;
	CGRect oldFrame;
	NSString* _contactFullName;
    
	BOOL _firstmsg;
	
	BOOL wasaway;
	BOOL wasoffline;
    
    NSArray* activeChats;
    
    NSDictionary* _contact;

    BOOL  _isMUC;
    NSString* _day;
    BOOL _keyboardVisible; 
}

@property (nonatomic, weak) IBOutlet UITableView* messageTable;
@property (nonatomic, weak) IBOutlet MLResizingTextView* chatInput;
@property (nonatomic, weak) IBOutlet UIButton* sendButton;
@property (nonatomic, weak) IBOutlet UIView* inputContainerView;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* inputContainerHeight;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* inputContainerBottom;

@property (nonatomic,strong)  NSString* contactName;

@property (nonatomic, weak) IBOutlet UIView* topBarView;
@property (nonatomic, weak) IBOutlet UILabel* topName;
@property (nonatomic, weak) IBOutlet UIImageView* topIcon;


-(IBAction)sendMessageText:(id)sender;
-(IBAction)attach:(id)sender;

-(IBAction)dismissKeyboard:(id)sender;

-(void) setupWithContact:(NSDictionary*) contact  ;

/**
 if day is specified this is a log
 */
-(id) initWithContact:(NSDictionary*) contact  andDay:(NSString* )day;

/**
 Receives the new message notice and will update if it is this user. 
 */
-(void) handleNewMessage:(NSNotification *)notification;
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId;

//notification
-(void) keyboardWillShow:(NSNotification *) note;
-(void) keyboardWillHide:(NSNotification *) note;

-(void) retry:(id) sender;

-(void) reloadTable; 

/**
 full own username with domain e.g. aa@gmail.com
 */
@property (nonatomic, strong) NSString* jid;

/**
 This is the account number of the account this user is for
 */
@property (nonatomic, strong) NSString* accountNo;

@end
