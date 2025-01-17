//
//  ViewController.m
//  mpeg_tester
//
//  Created by Laurence Bank on 1/16/25.
//

#import "ViewController.h"

static int iWidth, iHeight, samplerate;
float framerate;
static uint8_t *pLocalImage;
static plm_t *plm;
static plm_frame_t *theVideoFrame;
static plm_samples_t *theAudio;
static int bVideo, bAudio, bThrottle, bPlaying = 0;

void JPEGPixelRGB(uint32_t *pDest, int iY, int iCb, int iCr)
{
    int iCBB, iCBG, iCRG, iCRR;
    uint32_t u32Pixel;
    int32_t i32;

    iCBB = 7258  * (iCb-0x80);
    iCBG = -1409 * (iCb-0x80);
    iCRG = -2925 * (iCr-0x80);
    iCRR = 5742  * (iCr-0x80);
    u32Pixel = 0xff000000; // Alpha = 0xff
    i32 = ((iCBB + iY) >> 12);
    if (i32 < 0) i32 = 0;
    else if (i32 > 255) i32 = 255;
    u32Pixel |= (uint32_t)(i32<<16); // blue
    i32 = ((iCBG + iCRG + iY) >> 12); // green pixel
    if (i32 < 0) i32 = 0;
    else if (i32 > 255) i32 = 255;
    u32Pixel |= (uint32_t)(i32 << 8);
    i32 = ((iCRR + iY) >> 12); // red pixel
    if (i32 < 0) i32 = 0;
    else if (i32 > 255) i32 = 255;
    u32Pixel |= (uint32_t)(i32);
    pDest[0] = u32Pixel;
} /* JPEGPixelRGB() */

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)FileButtonPressed:(id)sender {
    NSOpenPanel *openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setAllowedFileTypes:@[@"mpg", @"mpeg", @"MPG", @"MPEG"]];
    [openDlg setAllowsMultipleSelection:NO];
    
    [openDlg beginWithCompletionHandler:^(NSInteger result) {
        if (NSModalResponseOK == result) {
            // set it in the config file text field
            self.FilenameLabel.stringValue = openDlg.URL.path;
        }
    }];
}

- (IBAction)ResetButtonPressed:(id)sender {
}
// Background thread to run the video
- (void) MPEGThread
{
    int iFrame;
    useconds_t delay;
    const char *filename = [self.FilenameLabel.stringValue UTF8String];
    // Initialize plmpeg, load the video file, install decode callbacks
    plm = plm_create_with_filename(filename);
    if (!plm) {
            NSLog(@"Couldn't open %s", filename);
            exit(1);
    }

    if (!plm_probe(plm, 5000 * 1024)) {
            NSLog(@"No MPEG video or audio streams found in %s", filename);
            exit(1);
    }

    samplerate = plm_get_samplerate(plm);
    framerate = plm_get_framerate(plm);
    
    NSLog(
            @"Opened %s - framerate: %f, samplerate: %d, duration: %f",
            filename,
            plm_get_framerate(plm),
            plm_get_samplerate(plm),
            plm_get_duration(plm)
    );
    iWidth = plm_get_width(plm);
    iHeight = plm_get_height(plm);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSString *info = [NSString stringWithFormat:@"%d x %d, %f fps", iWidth, iHeight, framerate];
        self.InfoLabel.stringValue = info;
    }];
    pLocalImage = (uint8_t *)malloc(iWidth * iHeight * 4); // allocate enough for 32-bit pixels
    
    // Decode
    iFrame = 0;
    delay = (useconds_t)(1000000.0f / framerate);
    do {
        theVideoFrame = plm_decode_video(plm);
        if (bVideo) {
            // Update the NSImageView on the GUI thread
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self updateDisplay];
            }];
        }
        theAudio = plm_decode_audio(plm);
        if (bAudio) {
            // do something with the audio
        }
        if (bThrottle) {
            usleep(delay);
        }
        iFrame++;
    } while (bPlaying && !plm_has_ended(plm));

    // All done
    plm_destroy(plm);
} /* MPEGThread() */

- (IBAction)PlayStopButtonPressed:(id)sender {
    static NSThread *mpegThread = nil;
    
    if (!bPlaying) {
        self.PlayStopButton.title = @"Stop";
        bVideo = (self.VideoCheck.state == NSControlStateValueOn);
        bAudio = (self.AudioCheck.state == NSControlStateValueOn);
        bThrottle = (self.ThrottleCheck.state == NSControlStateValueOn);
        // Start a new thread which waits for data on the socket
        bPlaying = 1;
        mpegThread = [[NSThread alloc] initWithTarget:self selector:@selector(MPEGThread) object:nil];
        [mpegThread start];
    } else { // stop the player
        bPlaying = 0;
        self.PlayStopButton.title = @"Play";
    }
}

- (void)updateDisplay
{
    // make an NSImage to display the current frame
    CGColorSpaceRef colorSpace;
    CGContextRef gtx;
    NSUInteger bitsPerComponent = 8;
    NSUInteger bytesPerRow = iWidth * 4;
    int x, y;
    uint8_t *pCb, *pCr, *pY;
    uint32_t *d;
    int iY, iCb, iCr;
    
    // Convert the MPEG frame from YUV to RGB32
    for (y=0; y<iHeight; y+=2) { // work in 2x2 subsampled blocks
        d = (uint32_t *)&pLocalImage[y * iWidth * 4];
        pY = &theVideoFrame->y.data[y * iWidth];
        pCb = &theVideoFrame->cb.data[y * iWidth/4];
        pCr = &theVideoFrame->cr.data[y * iWidth/4];
        for (x=0; x<iWidth; x+=2) {
            iY = pY[0] << 12;
            iCb = *pCb++;
            iCr = *pCr++;
            JPEGPixelRGB(d, iY, iCb, iCr);
            iY = pY[1] << 12;
            JPEGPixelRGB(&d[1], iY, iCb, iCr);
            iY = pY[iWidth] << 12;
            JPEGPixelRGB(&d[iWidth], iY, iCb, iCr);
            iY = pY[iWidth + 1] << 12;
            JPEGPixelRGB(&d[iWidth+1], iY, iCb, iCr);
            pY += 2; d += 2;
        }
    }
    // Convert the RGB8888 output of the display into a NSBitmap to display
    colorSpace = CGColorSpaceCreateDeviceRGB();
    gtx = CGBitmapContextCreate(pLocalImage, iWidth, iHeight, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGImageRef myimage = CGBitmapContextCreateImage(gtx);
//            CGContextSetInterpolationQuality(gtx, kCGInterpolationNone);
    NSImage *image = [[NSImage alloc]initWithCGImage:myimage size:NSZeroSize];
    _TheImage.image = image; // set it into the image view
    // Free temp objects
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(gtx);
    CGImageRelease(myimage);
} /* updateDisplay */
@end
