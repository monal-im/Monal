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
    BOOL _keyboardVisible; 
}

@property (nonatomic, weak) IBOutlet UITableView* messageTable;
@property (nonatomic, weak) IBOutlet MLResizingTextView* chatInput;
@property (nonatomic, weak) IBOutlet UIButton* sendButton;
@property (nonatomic, weak) IBOutlet UIView* inputContainerView;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* inputContainerHeight;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* inputContainerBottom;

@property (nonatomic, strong) NSString* day;
@property (nonatomic,strong)  NSString* contactName;


-(IBAction)sendMessageText:(id)sender;
-(IBAction)attach:(id)sender;

-(IBAction)dismissKeyboard:(id)sender;

-(void) setupWithContact:(NSDictionary*) contact  ;

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
