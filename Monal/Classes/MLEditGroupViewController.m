//
//  MLEditGroupViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLEditGroupViewController.h"
#import "DataLayer.h"
#import "SAMKeychain.h"
#import "MLSwitchCell.h"
#import "UIColor+Theme.h"
#import "MLButtonCell.h"

@interface MLEditGroupViewController ()

@end

@implementation MLEditGroupViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"AccountCell"];
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ButtonCell"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger toreturn=0;
    
    switch (section)
    {
        case 0:
        {
            toreturn=1;
            break;
        }
            
        case 1:
        {
            toreturn=5;
            break;
        }
            
        case 2:
        {
            toreturn=1;
            break;
        }
            
    }
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=0;
    
    switch (section)
    {
        case 0:
        {
            toreturn=@"Account To Use";
            break;
        }
            
        case 1:
        {
            toreturn=@"Group Information";
            break;
        }
            
        default:
        {
            toreturn=@"";
            break;
        }
            
    }
    return toreturn;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
    
    switch (indexPath.section)
    {
        case 0:
        {
           //Account selection.
            break;
        }
            
        case 1:
        {
            switch (indexPath.row)
            {
                case 0:{
                    thecell.cellLabel.text=@"Room";
                    thecell.toggleSwitch.hidden=YES;
                    thecell.textInputField.tag=1;
                    thecell.textInputField.keyboardType = UIKeyboardTypeEmailAddress;
                    break;
                }
                case 1:{
                    thecell.cellLabel.text=@"Nickname";
                    thecell.toggleSwitch.hidden=YES;
                    thecell.textInputField.secureTextEntry=NO;
                    thecell.textInputField.tag=2;
                   // thecell.textInputField.text=self.password;
                    break;
                }
                case 2:{
                    thecell.cellLabel.text=@"Password";
                    thecell.toggleSwitch.hidden=YES;
                    thecell.textInputField.secureTextEntry=YES;
                    thecell.textInputField.tag=3;
                   // thecell.textInputField.text=self.password;
                    break;
                }
                case 3:{
                    thecell.cellLabel.text=@"Favorite";
                    thecell.textInputField.hidden=YES;
                    thecell.toggleSwitch.tag=4;
                  //  thecell.toggleSwitch.on=self.enabled;
                    break;
                }
                case 4:{
                    thecell.cellLabel.text=@"Auto Join";
                    thecell.textInputField.hidden=YES;
                    thecell.toggleSwitch.tag=2;
                   // thecell.toggleSwitch.on=self.enabled;
                    break;
                }
                    
            }
            
            break;
        }
            
        case 2:
        {
            //save button
            MLButtonCell *buttonCell =(MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
            buttonCell.buttonText.text=@"Save";
            buttonCell.buttonText.textColor= [UIColor monalGreen];
            buttonCell.selectionStyle= UITableViewCellSelectionStyleNone;
            return buttonCell;
            break;
        }
            
    }
    
    
    return thecell;
}

@end
