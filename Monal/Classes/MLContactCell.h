//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

typedef enum {
    kStatusOnline=1,
    kStatusOffline,
    kStatusAway
} statusType;

@interface MLContactCell : UITableViewCell

@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSInteger accountNo;
@property (nonatomic, strong) NSString *username;

@property (nonatomic, weak) IBOutlet UILabel *displayName;
@property (nonatomic, weak) IBOutlet UILabel *centeredDisplayName;

@property (nonatomic, weak) IBOutlet UILabel *statusText;
@property (nonatomic, weak) IBOutlet UIImageView *statusOrb;
@property (nonatomic, weak) IBOutlet UIImageView *userImage;
@property (nonatomic, weak) IBOutlet UIButton *badge;

-(void) setOrb;

-(void) showStatusText:(NSString *) text;
-(void) showDisplayName:(NSString *) name;

@end
