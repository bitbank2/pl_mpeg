//
//  ViewController.h
//  mpeg_tester
//
//  Created by Laurence Bank on 1/16/25.
//

#import <Cocoa/Cocoa.h>
#define PL_MPEG_IMPLEMENTATION
#include "../../pl_mpeg.h"

@interface ViewController : NSViewController
@property (weak) IBOutlet NSTextField *FilenameLabel;
@property (weak) IBOutlet NSTextField *InfoLabel;
@property (weak) IBOutlet NSButton *VideoCheck;
@property (weak) IBOutlet NSButton *AudioCheck;
@property (weak) IBOutlet NSButton *ThrottleCheck;
@property (weak) IBOutlet NSImageView *TheImage;
@property (weak) IBOutlet NSButton *PlayStopButton;

- (void)updateDisplay;
@end

