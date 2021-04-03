//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//
#import "MLAttributedLabel.h"
#import "MLContact.h"
#import "MLMessage.h"

@interface MLContactCell : UITableViewCell

@property (nonatomic, assign) NSInteger accountNo;
@property (nonatomic, strong) NSString* _Nullable username;

@property (nonatomic, weak) IBOutlet UILabel* _Nullable displayName;
@property (nonatomic, weak) IBOutlet UILabel* _Nullable centeredDisplayName;
@property (nonatomic, weak) IBOutlet UILabel* _Nullable time;

@property (nonatomic, weak) IBOutlet MLAttributedLabel* _Nullable statusText;
@property (nonatomic, weak) IBOutlet UIImageView* _Nullable userImage;
@property (nonatomic, weak) IBOutlet UIButton* _Nullable badge;
@property (nonatomic, weak) IBOutlet UIImageView* _Nullable muteBadge;

@property (nonatomic, assign) BOOL isPinned;

-(void) initCell:(MLContact* _Nonnull) contact withLastMessage:(MLMessage* _Nullable) lastMessage;

@end
