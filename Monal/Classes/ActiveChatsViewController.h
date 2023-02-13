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
#import <DZNEmptyDataSet/UIScrollView+EmptyDataSet.h>

NS_ASSUME_NONNULL_BEGIN

@class chatViewController;
@class MLCall;

@interface ActiveChatsViewController : UITableViewController  <DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>

@property (nonatomic, strong) UITableView* chatListTable;
@property (nonatomic, weak) IBOutlet UIBarButtonItem* settingsButton;
@property (nonatomic, weak) IBOutlet UIBarButtonItem* composeButton;
@property (nonatomic, strong) chatViewController* currentChatViewController;
@property (nonatomic, strong) UIActivityIndicatorView* spinner;

-(void) showCallContactNotFoundAlert:(NSString*) jid;
-(void) callContact:(MLContact*) contact;
-(void) presentAccountPickerForContacts:(NSArray<MLContact*>*) contacts;
-(void) presentCall:(MLCall*) call;
-(void) presentChatWithContact:(MLContact* _Nullable) contact;
-(void) presentChatWithContact:(MLContact* _Nullable) contact andCompletion:(monal_id_block_t _Nullable) completion;
-(void) refreshDisplay;

-(void) showContacts;
-(void) deleteConversation;
-(void) showSettings;
-(void) showPrivacySettings;
-(void) showDetails;
-(void) showRegisterWithUsername:(NSString*) username onHost:(NSString*) host withToken:(NSString* _Nullable) token usingCompletion:(monal_id_block_t _Nullable) callback;
-(void) showAddContactWithJid:(NSString*) jid andPreauthToken:(NSString* _Nullable) preauthToken;

@end

NS_ASSUME_NONNULL_END
