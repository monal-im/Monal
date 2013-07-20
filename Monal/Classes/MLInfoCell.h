//
//  MLInfoCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/12/13.
//
//

#import <UIKit/UIKit.h>

@interface MLInfoCell : UITableViewCell
{
    UIActivityIndicatorView* _spinner;
}

@property (nonatomic,strong, readonly) UIButton* Cancel;
@property (nonatomic,strong) NSString* type;
@property (nonatomic,strong) NSString* accountId;

@end
