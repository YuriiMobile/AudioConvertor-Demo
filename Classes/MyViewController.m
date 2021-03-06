/*
        File: MyViewController.m
    Abstract: The main view controller of this app.
     Version: 1.2.1
    
    Copyright (C) 2014 YuriiBogdan. All Rights Reserved.
    
*/

#import "MyViewController.h"

extern OSStatus DoConvertFile(CFURLRef sourceURL, CFURLRef destinationURL, OSType outputFormat, Float64 outputSampleRate);

#define kTransitionDuration	0.75

#pragma mark-

static Boolean IsAACEncoderAvailable(void)
{
    Boolean isAvailable = false;
 
    // get an array of AudioClassDescriptions for all installed encoders for the given format 
    // the specifier is the format that we are interested in - this is 'aac ' in our case
    UInt32 encoderSpecifier = kAudioFormatMPEG4AAC;
    UInt32 size;
 
    OSStatus result = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    if (result) { printf("AudioFormatGetPropertyInfo kAudioFormatProperty_Encoders result %lu %4.4s\n", result, (char*)&result); return false; }
 
    UInt32 numEncoders = size / sizeof(AudioClassDescription);
    AudioClassDescription encoderDescriptions[numEncoders];
    
    result = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, encoderDescriptions);
    if (result) { printf("AudioFormatGetProperty kAudioFormatProperty_Encoders result %lu %4.4s\n", result, (char*)&result); return false; }
    
    printf("Number of AAC encoders available: %lu\n", numEncoders);
    
    // with iOS 7.0 AAC software encode is always available
    // older devices like the iPhone 4s also have a slower/less flexible hardware encoded for supporting AAC encode on older systems
    // newer devices may not have a hardware AAC encoder at all but a faster more flexible software AAC encoder
    // as long as one of these encoders is present we can convert to AAC
    // if both are available you may choose to which one to prefer via the AudioConverterNewSpecific() API
    for (UInt32 i=0; i < numEncoders; ++i) {
        if (encoderDescriptions[i].mSubType == kAudioFormatMPEG4AAC && encoderDescriptions[i].mManufacturer == kAppleHardwareAudioCodecManufacturer) {
            printf("Hardware encoder available\n");
            isAvailable = true;
        }
        if (encoderDescriptions[i].mSubType == kAudioFormatMPEG4AAC && encoderDescriptions[i].mManufacturer == kAppleSoftwareAudioCodecManufacturer) {
            printf("Software encoder available\n");
            isAvailable = true;
        }
    }
        
    return isAvailable;
}

static void UpdateFormatInfo(UILabel *inLabel, CFURLRef inFileURL)
{
    AudioFileID fileID;
    
    OSStatus result = AudioFileOpenURL(inFileURL, kAudioFileReadPermission, 0, &fileID);
    if (noErr == result) {
        CAStreamBasicDescription asbd;
        UInt32 size = sizeof(asbd);
        result = AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &size, &asbd);
        if (noErr == result) {
            char formatID[5];
            CFStringRef lastPathComponent = CFURLCopyLastPathComponent(inFileURL);
            *(UInt32 *)formatID = CFSwapInt32HostToBig(asbd.mFormatID);
    
            NSString *labelText = [NSString stringWithFormat: @"%@ %4.4s%6.0fHz (%zuch.)", lastPathComponent, formatID, asbd.mSampleRate, asbd.NumberChannels(), nil];
            if (asbd.mBitsPerChannel > 0 )
                inLabel.text = [labelText stringByAppendingFormat: @" %zu-bit", asbd.mBitsPerChannel, nil];
            else
                inLabel.text = labelText;

            CFRelease(lastPathComponent);
        } else {
            printf("AudioFileGetProperty kAudioFilePropertyDataFormat result %lu %4.4s\n", result, (char*)&result);
        }
            
        AudioFileClose(fileID);
    } else {
        printf("AudioFileOpenURL failed! result %lu %4.4s\n", result, (char*)&result);
    }
}

#pragma mark-

@implementation MyViewController

@synthesize instructionsView, webView, contentView, outputFormatSelector, outputSampleRateSelector, startButton, activityIndicator, flipButton, doneButton;

- (void)dealloc
{
    [instructionsView release];
    [webView release];
    [contentView release];
    
    [fileInfo release];
    
    [outputFormatSelector release];
    [outputSampleRateSelector release];
    
    [startButton release];
    [activityIndicator release];
    
    [flipButton release];
    [doneButton release];
    
    [destinationFilePath release];
    CFRelease(sourceURL);
    CFRelease(destinationURL);
    
	[super dealloc];
}

- (void)viewDidLoad
{   
    // create the URLs we'll use for source and destination
    NSString *source = [[NSBundle mainBundle] pathForResource:@"sourceALAC" ofType:@"caf"];
    sourceURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)source, kCFURLPOSIXPathStyle, false);
    
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    destinationFilePath = [[NSString alloc] initWithFormat: @"%@/output.caf", documentsDirectory];
    destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)destinationFilePath, kCFURLPOSIXPathStyle, false);

	// load up the info text
    NSString *infoSouceFile = [[NSBundle mainBundle] pathForResource:@"info" ofType:@"html"];
	NSString *infoText = [NSString stringWithContentsOfFile:infoSouceFile encoding:NSUTF8StringEncoding error:nil];
    [self.webView loadHTMLString:infoText baseURL:nil];
    self.webView.backgroundColor = [UIColor whiteColor];
    
    // set up start button
    UIImage *greenImage = [[UIImage imageNamed:@"green_button.png"] stretchableImageWithLeftCapWidth:12.0 topCapHeight:0.0];
	UIImage *redImage = [[UIImage imageNamed:@"red_button.png"] stretchableImageWithLeftCapWidth:12.0 topCapHeight:0.0];
	
	[startButton setBackgroundImage:greenImage forState:UIControlStateNormal];
	[startButton setBackgroundImage:redImage forState:UIControlStateDisabled];
    
    // add the subview
	[self.view addSubview:contentView];
	
	// add our custom flip buttons as the nav bars custom right view
	UIButton* infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
	[infoButton addTarget:self action:@selector(flipAction:) forControlEvents:UIControlEventTouchUpInside];
	
    flipButton = [[UIBarButtonItem alloc] initWithCustomView:infoButton];
    self.navigationItem.rightBarButtonItem = flipButton;
	
	// create our done button as the nav bar's custom right view for the flipped view (used later)
	doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(flipAction:)];
    
    // default output format
    // sample rate of 0 indicates source file sample rate
    outputFormat = kAudioFormatLinearPCM;
    sampleRate = 0;
    
    // can we encode to AAC?
    if (IsAACEncoderAvailable()) {
        [self.outputFormatSelector setEnabled:YES forSegmentAtIndex:0];
    } else {
        // even though not enabled in IB, this segment will still be enabled
        // if not specifically turned off here which we'll assume is a bug
        [self.outputFormatSelector setEnabled:NO forSegmentAtIndex:0];
    }
    
    UpdateFormatInfo(fileInfo, sourceURL);

}

- (void)didReceiveMemoryWarning
{
	// Invoke super's implementation to do the Right Thing, but also release the input controller since we can do that	
	// In practice this is unlikely to be used in this application, and it would be of little benefit,
	// but the principle is the important thing.
    
	[super didReceiveMemoryWarning];
}

#pragma mark- Actions

- (void)flipAction:(id)sender
{
	[UIView setAnimationDelegate:self];
	[UIView setAnimationDidStopSelector:NULL];
	[UIView beginAnimations:nil context:nil];
	[UIView setAnimationDuration:kTransitionDuration];
	
	[UIView setAnimationTransition:([self.contentView superview] ? UIViewAnimationTransitionFlipFromLeft : UIViewAnimationTransitionFlipFromRight)
                                    forView:self.view
                                    cache:YES];
                                    
	if ([self.instructionsView superview]) {
		[self.instructionsView removeFromSuperview];
		[self.view addSubview:contentView];
	} else {
		[self.contentView removeFromSuperview];
		[self.view addSubview:instructionsView];
	}
	
	[UIView commitAnimations];
	
	// adjust our done/info buttons accordingly
	if ([instructionsView superview]) {
		self.navigationItem.rightBarButtonItem = doneButton;
	} else {
		self.navigationItem.rightBarButtonItem = flipButton;
    }
}

- (IBAction)convertButtonPressed:(id)sender
{
    // use AudioProcessing category for offline conversion when not playing or recording audio at the same time
    // if you are recording or playing audio at the same time you are encoding, use the same Audio Session category that you would normally
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAudioProcessing error:&error];
    
    if (error) {
        printf("Setting the AVAudioSessionCategoryAudioProcessing Category failed! %ld\n", (long)error.code);
        
        return;
    } 

    [self.startButton setTitle:@"Converting..." forState:UIControlStateDisabled];
	[startButton setEnabled:NO];
    
    [self.activityIndicator startAnimating];
    
    // run audio file code in a background thread
    [self performSelectorInBackground:(@selector(convertAudio)) withObject:nil];
}

- (IBAction)segmentedControllerValueChanged:(id)sender
{
    switch ([sender tag]) {
    case 0:
        switch ([sender selectedSegmentIndex]) {
        case 0:
            outputFormat = kAudioFormatMPEG4AAC;
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:0];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:1];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:2];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:3];
            break;
        case 1:
            outputFormat = kAudioFormatAppleIMA4;
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:0];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:1];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:2];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:3];
            break;
        case 2:
            // iLBC sample rate is 8K
            outputFormat = kAudioFormatiLBC;
            sampleRate = 8000.0;
            [self.outputSampleRateSelector setSelectedSegmentIndex:2];
            [self.outputSampleRateSelector setEnabled:NO forSegmentAtIndex:0];
            [self.outputSampleRateSelector setEnabled:NO forSegmentAtIndex:1];
            [self.outputSampleRateSelector setEnabled:NO forSegmentAtIndex:3];
            break;
        case 3:
            outputFormat = kAudioFormatLinearPCM;
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:0];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:1];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:2];
            [self.outputSampleRateSelector setEnabled:YES forSegmentAtIndex:3];
            break;
        }
        break;
    case 1:
        switch ([sender selectedSegmentIndex]) {
        case 0:
            sampleRate = 44100.0;
            break;
        case 1:
            sampleRate = 22050.0;
            break;
        case 2:
            sampleRate = 8000.0;
            break;
        case 3:
            sampleRate = 0;
            break;
        }
        break;
    }
}

#pragma mark- AVAudioPlayer

- (void)updateUI
{
    [startButton setEnabled:YES];
    UpdateFormatInfo(fileInfo, sourceURL);
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    NSLog(@"%@", [error localizedDescription]);
    [self audioPlayerDidFinishPlaying:player successfully:false];
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
    printf("Session interrupted! --- audioPlayerBeginInterruption ---\n");
    
    // if the player was interrupted during playback we don't continue
    [self audioPlayerDidFinishPlaying:player successfully:true];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
	if (flag == NO) NSLog(@"Playback finished unsuccessfully!");
    
    printf("audioPlayerDidFinishPlaying\n\n");
    
	[player setDelegate:nil];
    [player release];
    
    [self updateUI];
}

- (void)playAudio
{
    printf("playAudio\n");
    
    UpdateFormatInfo(fileInfo, destinationURL);
    [self.startButton setTitle:@"Playing Output File..." forState:UIControlStateDisabled];
    
    // set category back to something that will allow us to play audio since AVAudioSessionCategoryAudioProcessing will not
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    
    if (error) {
        printf("Setting the AVAudioSessionCategoryPlayback Category failed! %ld\n", (long)error.code);
        
        [self updateUI];
        
        return;
    } 
    
    // play the result
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:(NSURL *)destinationURL error:&error];
    if (nil == player) {
        printf("AVAudioPlayer alloc failed! %ld\n", (long)error.code);
        
        [self updateUI];
        
        return;
    } 

    [player setDelegate:self];
    [player play];
}

#pragma mark- ExtAudioFile

- (void)convertAudio
{    
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    OSStatus error = DoConvertFile(sourceURL, destinationURL, outputFormat, sampleRate);
    
    [self.activityIndicator stopAnimating];
    
    if (error) {
        // delete output file if it exists since an error was returned during the conversion process
        if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFilePath]) {
            [[NSFileManager defaultManager] removeItemAtPath:destinationFilePath error:nil];
        }
        
        printf("DoConvertFile failed! %ld\n", error);
        [self performSelectorOnMainThread:(@selector(updateUI)) withObject:nil waitUntilDone:NO];
    } else {        
        [self performSelectorOnMainThread:(@selector(playAudio)) withObject:nil waitUntilDone:NO];
    }
    
    [pool release];
}

@end