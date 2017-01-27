//
//  weixinWalk.mm
//  weixinWalk
//
//  Created by Eular on 6/19/16.
//  Copyright (c) 2016 __MyCompanyName__. All rights reserved.
//

// CaptainHook by Ryan Petrich
// see https://github.com/rpetrich/CaptainHook/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CaptainHook/CaptainHook.h"

CHDeclareClass(WCDeviceStepObject);

CHPropertyGetter(WCDeviceStepObject, m7StepCount, unsigned int)
{
    NSLog(@"## Weixin Walk ##");
    return 23333;
}


// Alert
//UIAlertController *alertView = [UIAlertController alertControllerWithTitle:@"Urinx" message:@"test" preferredStyle: UIAlertControllerStyleAlert];
//UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
//UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil];
//[alertView addAction:cancelAction];
//[alertView addAction:okAction];
//[self presentViewController:alertView animated:YES completion:nil];


CHConstructor
{
	@autoreleasepool
	{
        CHLoadLateClass(WCDeviceStepObject);
		CHHook(0, WCDeviceStepObject, m7StepCount);
	}
}
