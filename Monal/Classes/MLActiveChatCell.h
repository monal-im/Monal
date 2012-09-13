//
//  MLActiveChatCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/12/12.
//
//

#import <UIKit/UIKit.h>

@interface MLActiveChatCell : UITableViewCell
{
    NSString* text;

}
- (void)drawRect:(CGRect)rect;

@property (nonatomic) NSString* text;


@end
