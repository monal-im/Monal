//
//  ActiveChatsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"
#import "MLContact.h"
#import "MLCall.h"
#import <DZNEmptyDataSet/UIScrollView+EmptyDataSet.h>

NS_ASSUME_NONNULL_BEGIN

@class chatViewController;
@class MLCall;

@interface ActiveChatsViewController : UITableViewController  <DZNEmptyDataSetSource, DZNEmptyDataSetDelegate, UIAdaptivePresentationControllerDelegate>

@property (nonatomic, strong) UITableView* chatListTable;
@property (nonatomic, weak) IBOutlet UIBarButtonItem* settingsButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem* spinnerButton;
@property (nonatomic, weak) IBOutlet UIBarButtonItem* composeButton;
@property (nonatomic, strong) chatViewController* currentChatViewController;
@property (nonatomic, strong) UIActivityIndicatorView* spinner;
@property (nonatomic) BOOL enqueueGeneralSettings;

-(void) showCallContactNotFoundAlert:(NSString*) jid;
-(void) callContact:(MLContact*) contact withUIKitSender:(_Nullable id) sender;
-(void) callContact:(MLContact*) contact withCallType:(MLCallType) callType;
-(void) presentAccountPickerForContacts:(NSArray<MLContact*>*) contacts andCallType:(MLCallType) callType;
-(void) presentCall:(MLCall*) call;
-(void) presentChatWithContact:(MLContact* _Nullable) contact;
-(void) presentChatWithContact:(MLContact* _Nullable) contact andCompletion:(monal_id_block_t _Nullable) completion;
-(void) refreshDisplay;

-(void) showContacts;
-(void) deleteConversation;
-(void) showSettings;
-(void) showGeneralSettings;
-(void) showOnboarding;
-(void) showNotificationSettings;
-(void) showDetails;
-(void) showRegisterWithUsername:(NSString*) username onHost:(NSString*) host withToken:(NSString* _Nullable) token usingCompletion:(monal_id_block_t _Nullable) callback;
-(void) showAddContactWithJid:(NSString*) jid preauthToken:(NSString* _Nullable) preauthToken prefillAccount:(xmpp* _Nullable) account andOmemoFingerprints:(NSDictionary* _Nullable) fingerprints;

@end

NS_ASSUME_NONNULL_END
