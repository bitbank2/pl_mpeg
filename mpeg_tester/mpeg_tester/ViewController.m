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
static int16_t i16Samples[2400];

AudioFileID file;
UInt32 currentPacket;
AudioQueueRef audioQueue;
AudioQueueBufferRef buffer[3];
AudioStreamBasicDescription audioStreamBasicDescription;
static int iAudioHead, iAudioTail, iAudioTotal, iAudioSampleSize, iAudioAvailable;
static unsigned char *pAudioBuffer;
#define SAMPLE_CHUNK 256

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

void AudioPopSamples(unsigned char *pSamples, int iCount)
{
    if (iAudioAvailable < iCount) //NSLog(@"not enough audio available\n");
    {
        memset(pSamples, 0, iCount * iAudioSampleSize);
        return;
    }
    if (iAudioHead + iCount <= iAudioTotal) // simple case, no wrap around
    {
        memcpy(pSamples, &pAudioBuffer[iAudioHead*iAudioSampleSize], iCount*iAudioSampleSize);
        iAudioHead += iCount;
    }
    else // must wrap around
    {
        int iFirst = iAudioTotal - iAudioHead;
        memcpy(pSamples, &pAudioBuffer[iAudioHead*iAudioSampleSize], iFirst*iAudioSampleSize);
        memcpy(&pSamples[iFirst*iAudioSampleSize], pAudioBuffer, (iCount-iFirst)*iAudioSampleSize);
        iAudioHead = iCount - iFirst;
    }
    iAudioAvailable -= iCount;
    //    g_print("leaving SG_PopSamples(), head=%d, tail=%d\n", iAudioHead, iAudioTail);
} /* AudioPopSamples() */

void AudioEngineOutputBufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
//    static int iCount = 0;
//    if (file == NULL) return;
    
//    UInt32 bytesRead = bufferSizeInSamples * 4;
//    UInt32 packetsRead = bufferSizeInSamples;
//    AudioFileReadPacketData(file, false, &bytesRead, NULL, currentPacket, &packetsRead, inBuffer->mAudioData);
    inBuffer->mAudioDataByteSize = SAMPLE_CHUNK * 4; //bytesRead;
    AudioPopSamples(inBuffer->mAudioData, SAMPLE_CHUNK);
        //        memcpy(inBuffer->mAudioData, pSoundBuf, bufferSizeInSamples * 4);
//    iCount++;
//    if (iCount % 60 == 0) NSLog(@"Audio packets requested = %d", iCount);
//    currentPacket += packetsRead;
    
//    if (bytesRead == 0) {
//        AudioQueueStop(inAQ, false);
//    }
//    else {
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
//    }
} /* AudioEngineOutputBufferCallback() */

void AudioEnginePropertyListenerProc (void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID) {
    //We are only interested in the property kAudioQueueProperty_IsRunning
    if (inID != kAudioQueueProperty_IsRunning) return;
    
    //Get the status of the property
    UInt32 isRunning = false;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &isRunning, &size);
    
    if (isRunning) {
        currentPacket = 0;
        
//        NSString *fileName = @"/Users/roy/Documents/XCodeProjectsData/FUZZ/03.wav";
//        NSURL *fileURL = [[NSURL alloc] initFileURLWithPath: fileName];
//        AudioFileOpenURL((__bridge CFURLRef) fileURL, kAudioFileReadPermission, 0, &file);
        
        // Prime the audio queue by giving it a few buffers to work with
        // a single buffer will cause choppy audio. Three seems to work smoothly
        for (int i = 0; i < 3; i++)
        {
            AudioQueueAllocateBuffer(audioQueue, SAMPLE_CHUNK * 4, &buffer[i]);
            buffer[i]->mAudioDataByteSize = SAMPLE_CHUNK * 4;
            AudioPopSamples(buffer[i]->mAudioData, SAMPLE_CHUNK);
            AudioQueueEnqueueBuffer(audioQueue, buffer[i], 0, NULL);
        } // for each buffer
    }
    
//                AudioQueueFreeBuffer(audioQueue, buffer[i]);
//                buffer[i] = NULL;
//            }
//        }
//    }
}

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set up the audio
    audioStreamBasicDescription.mBitsPerChannel = 16;
    audioStreamBasicDescription.mBytesPerFrame = 4;
    audioStreamBasicDescription.mBytesPerPacket = 4;
    audioStreamBasicDescription.mChannelsPerFrame = 2;
    audioStreamBasicDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioStreamBasicDescription.mFormatID = kAudioFormatLinearPCM;
    audioStreamBasicDescription.mFramesPerPacket = 1;
    audioStreamBasicDescription.mReserved = 0;

} /* viewDidLoad() */

void AudioPushSamples(unsigned char *pSamples, int iCount)
{
    if (iAudioAvailable + iCount > iAudioTotal)
    {
        NSLog(@"too much audio generated\n");
        return; // have to throw it away
    }
    //    g_print("entering SG_PushSamples(), pSamples =%d, pAudioBuffer=%d\n",(int)pSamples, (int)pAudioBuffer);
    if (iAudioTail + iCount <= iAudioTotal) // simple case, no wrap around
    {
        memcpy(&pAudioBuffer[iAudioTail*iAudioSampleSize], pSamples, iCount*iAudioSampleSize);
        iAudioTail += iCount;
    }
    else // have to wrap around
    {
        int iFirst = iAudioTotal - iAudioTail;
        memcpy(&pAudioBuffer[iAudioTail*iAudioSampleSize], pSamples, iFirst*iAudioSampleSize);
        memcpy(pAudioBuffer, &pSamples[iFirst*iAudioSampleSize], (iCount-iFirst)*iAudioSampleSize);
        iAudioTail = iCount - iFirst;
    }
    iAudioAvailable += iCount;
    //    g_print("leaving SG_PushSamples(), head=%d, tail=%d\n", iAudioHead, iAudioTail);
} /* AudioPushSamples() */

- (void) StopAudio
{
    int i;
    AudioQueueFlush( audioQueue );
    AudioQueueStop( audioQueue, false );
    for (i = 0; i < 3; i++)
    {
        AudioQueueFreeBuffer(audioQueue, buffer[i]);
    }
    
} /* StopAudio */


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
    int iFrame, iSamplesPerFrame, iSamplesNeeded, iTotalSamples;
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
    iSamplesNeeded = iTotalSamples = 0;
    iSamplesPerFrame = (int)((float)samplerate / framerate);
//    NSLog(
//            @"Opened %s - framerate: %f, samplerate: %d, duration: %f",
//            filename,
//            plm_get_framerate(plm),
//            plm_get_samplerate(plm),
//            plm_get_duration(plm)
//    );
    iWidth = plm_get_width(plm);
    iHeight = plm_get_height(plm);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSString *info = [NSString stringWithFormat:@"%d x %d, %f fps", iWidth, iHeight, framerate];
        self.InfoLabel.stringValue = info;
    }];
    pLocalImage = (uint8_t *)malloc(iWidth * iHeight * 4); // allocate enough for 32-bit pixels
    if (bAudio) {
        audioStreamBasicDescription.mSampleRate = samplerate;
        iAudioTotal = samplerate/10;
        pAudioBuffer = malloc(iAudioTotal * 4);
        iAudioTail = iAudioHead = 0;
        iAudioAvailable = 0;
        iAudioSampleSize = 4;
        // start Audio on the GUI thread
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            int rc = AudioQueueNewOutput(&audioStreamBasicDescription, AudioEngineOutputBufferCallback, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &audioQueue);
            NSLog(@"AudioQueueNewOutput returned %d", rc);
            AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, AudioEnginePropertyListenerProc, NULL);
   
//        AudioQueueAllocateBuffer(audioQueue, SAMPLE_CHUNK * 4, &buffer[0/*i*/]);
            AudioQueueStart(audioQueue, NULL);
        }];
    }

    // Decode
    iFrame = 0;
    delay = (useconds_t)(1000000.0f / framerate);
    do {
        iSamplesNeeded += iSamplesPerFrame; // audio needed to keep up with the given sample rate
        theVideoFrame = plm_decode_video(plm);
        if (bVideo) {
            // Update the NSImageView on the GUI thread
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self updateDisplay];
            }];
        }
        theAudio = plm_decode_audio(plm);
        if (bAudio) {
            while (iTotalSamples < iSamplesNeeded) {
                theAudio = plm_decode_audio(plm);
                if (theAudio) {
                    for (int i=0; i<theAudio->count*2; i++) { // stereo pairs
                        i16Samples[i] = (int16_t)(theAudio->interleaved[i] * 32767.0f); // convert to 16-bit signed integers
                    }
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        AudioPushSamples((uint8_t *)i16Samples, theAudio->count);
                    }];
                    iTotalSamples += theAudio->count;
                } else {
                    break; // need to decode a video frame before we can get more audio
                }
            }
        }
        if (bThrottle) {
            usleep(delay);
        }
        iFrame++;
    } while (bPlaying && !plm_has_ended(plm));

    // All done
    plm_destroy(plm);
    if (bAudio) {
        [self StopAudio];
        free(pAudioBuffer);
    }
    free(pLocalImage);
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
