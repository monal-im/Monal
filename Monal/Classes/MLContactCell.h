//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//
#import "MLAttributedLabel.h"

@interface MLContactCell : UITableViewCell

@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSInteger accountNo;
@property (nonatomic, strong) NSString *username;

@property (nonatomic, weak) IBOutlet UILabel *displayName;
@property (nonatomic, weak) IBOutlet UILabel *centeredDisplayName;
@property (nonatomic, weak) IBOutlet UILabel *time;

@property (nonatomic, weak) IBOutlet MLAttributedLabel *statusText;
@property (nonatomic, weak) IBOutlet UIImageView *userImage;
@property (nonatomic, weak) IBOutlet UIButton *badge;
@property (nonatomic, weak) IBOutlet UIImageView *muteBadge;

@property (nonatomic, assign) BOOL isPinned;

-(void) showStatusText:(NSString *) text;
-(void) showStatusTextItalic:(NSString *) text withItalicRange:(NSRange)italicRange;
-(void) setStatusTextLayout:(NSString *) text;
-(void) showDisplayName:(NSString *) name;

-(void) setPinned:(BOOL) pinned;

@end
