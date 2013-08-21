//
//  MLChatCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import <UIKit/UIKit.h>

@interface MLChatCell : UITableViewCell
{
    UIImageView* _bubbleImage;
}

@property (nonatomic, strong) UITextView* messageView; 
@property (nonatomic, strong) NSString* time;
@property (nonatomic, assign) BOOL outBound;

+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width;
@end
