//
//  Cycript_Reveal.mm
//  Cycript-Reveal
//
//  Created by Eular on 7/8/16.
//  Copyright (c) 2016 __MyCompanyName__. All rights reserved.
//

#import <Cycript/Cycript.h>
#import <CaptainHook/CaptainHook.h>

#define CYCRIPT_PORT 8888

CHDeclareClass(UIApplication);
CHDeclareClass(MicroMessengerAppDelegate);

CHOptimizedMethod2(self, void, MicroMessengerAppDelegate, application, UIApplication *, application, didFinishLaunchingWithOptions, NSDictionary *, options)
{
    CHSuper2(MicroMessengerAppDelegate, application, application, didFinishLaunchingWithOptions, options);
    
    NSLog(@"## Start Cycript ##");
    CYListenServer(CYCRIPT_PORT);
}


CHConstructor {
    @autoreleasepool {
        NSLog(@"## Start Reveal ##");
        
        CHLoadLateClass(MicroMessengerAppDelegate);
        CHHook2(MicroMessengerAppDelegate, application, didFinishLaunchingWithOptions);
    }
}
