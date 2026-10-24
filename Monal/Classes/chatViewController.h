//
//  chatViewController.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
// 

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <PhotosUI/PHPicker.h>

#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLXMPPManager.h>
#import "MLNotificationManager.h"
#import "MLResizingTextView.h"
#import "MLSearchViewController.h"
#import "MLFileTransferDataCell.h"
#import "MLFileTransferVideoCell.h"
#import "MLFileTransferTextCell.h"
#import "MLFileTransferFileViewController.h"
#import "MLAudioRecoderManager.h"
#import "MLUploadQueueCell.h"

@interface chatViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextViewDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIDocumentPickerDelegate, UICollectionViewDataSource, CLLocationManagerDelegate, SearchResultDelegate, OpenFileDelegate, AudioRecoderManagerDelegate, MLUploadQueueCellDelegate, UIDropInteractionDelegate, PHPickerViewControllerDelegate>
{
    UIView* containerView;
	BOOL _firstmsg;
}

@property (nonatomic, retain) CLLocationManager* locationManager;

@property (nonatomic, weak) IBOutlet UITableView* messageTable;
@property (nonatomic, weak) IBOutlet MLResizingTextView* chatInput;
@property (nonatomic, weak) IBOutlet UILabel* placeHolderText;
@property (nonatomic, weak) IBOutlet UIButton* sendButton;
@property (nonatomic, weak) IBOutlet UIButton* plusButton;
@property (nonatomic, weak) IBOutlet UIButton* audioButton;
@property (weak, nonatomic) IBOutlet UICollectionView* uploadMenuView;

@property (nonatomic, weak) IBOutlet UIView* inputContainerView;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* tableviewBottom;
@property (nonatomic, strong) UILabel* navBarContactJid;
@property (nonatomic, strong) UILabel* navBarLastInteraction;
@property (nonatomic, strong) IBOutlet UIImageView* navBarIcon;
@property (nonatomic, strong) UIBarButtonItem* customHeader;

@property (weak, nonatomic) IBOutlet UIBarButtonItem* navBarEncryptToggleButton;

@property (nonatomic, weak) IBOutlet UIImageView* backgroundImage;
@property (nonatomic, weak) IBOutlet UIView* transparentLayer;
@property (weak, nonatomic) IBOutlet UIButton* audioRecordButton;

@property (nonatomic, strong) MLContact* contact;

/**
 full own username with domain e.g. user@example.org
 */
@property (nonatomic, strong) NSString* jid;

-(IBAction)sendMessageText:(id)sender;
// attach image
-(IBAction)attach:(id)sender;
// attach file
-(IBAction)attachfile:(id)sender;

-(IBAction)dismissKeyboard:(id)sender;

-(void) setupWithContact:(MLContact *) contact;

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations;
-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error;

/**
 Receives the new message notice and will update if it is this user.
 */
-(void) handleNewMessage:(NSNotification *)notification;

-(void) retry:(id) sender;

-(void) reloadTable;

-(void) showUploadHUD;
-(void) hideUploadHUD;
-(void) scrollToBottomAnimated:(BOOL) animated;

@end
