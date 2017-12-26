//
//  MLChatCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import <UIKit/UIKit.h>
#import "MLBaseCell.h"

@interface MLChatCell : MLBaseCell


#define kNameLabelHeight 10.0

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier Muc:(BOOL) isMUC andParent:(UIViewController*) parent;
+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width;

-(void) openlink: (id) sender;

@end
