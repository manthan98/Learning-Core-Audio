//
//  main.m
//  CAPlayer
//
//  Created by Manthan Shah on 2020-04-27.
//  Copyright © 2020 Manthan Shah. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

// One buffer being played, one filled, and one last one to account for lag
#define kNumberPlaybackBuffers 3

# pragma mark user data struct
typedef struct MyPlayer {
    AudioFileID playbackFile;
    SInt64 packetPosition;
    UInt32 numPacketsToRead;
    AudioStreamPacketDescription *packetDescs;
    Boolean isDone;
} MyPlayer;

# pragma mark utility functions
static void CheckError(OSStatus err, const char *operation)
{
    if (err == noErr) return;
    
    char errorString[20];
    
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(err);
    
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4]))
    {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    }
    else
    {
        sprintf(errorString, "%d", (int)err);
    }
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}

// 5.14
// 5.15

# pragma mark playback callback function
static void MyAQOutputCallback(void *inUserData,
                               AudioQueueRef inAQ,
                               AudioQueueBufferRef inCompleteAQBuffer)
{
    // TODO:
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        MyPlayer player = { 0 };
        
        // Open the desired audio file for playback and read it into the user struct
        NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"time-passing" withExtension:@"mp3"];
        OSStatus err = AudioFileOpenURL((__bridge CFURLRef)fileURL,
                                        kAudioFileReadPermission,
                                        0,
                                        &player.playbackFile);
        CheckError(err, "AudioFileOpenURL failed");
        
        // Set up format - 5.5
        // Grab the ASBD that defines the audio data on the playback file
        AudioStreamBasicDescription dataFormat;
        UInt32 propertySize = sizeof(dataFormat);
        err = AudioFileGetProperty(player.playbackFile,
                                   kAudioFilePropertyDataFormat,
                                   &propertySize,
                                   &dataFormat);
        CheckError(err, "AudioFileGetProperty failed");
        
        // Set up queue - 5.6-5.10
        AudioQueueRef queue;
        err = AudioQueueNewOutput(&dataFormat,
                                  MyAQOutputCallback,
                                  &player,
                                  NULL,
                                  NULL,
                                  0,
                                  &queue);
        CheckError(err, "AudioQueueNewOutput failed");
        
        // We must account for the encoding characteristics of different audio files. We need
        // to inspect the elements of the audio file to figure out how large the buffers should
        // be, and the numbers of packets being read on each callback.
        UInt32 bufferBytesSize;
        CalculatBytesForTime(player.playbackFile,
                             dataFormat,
                             0.5,
                             &bufferBytesSize,
                             &player.numPacketsToRead);
        
        // Determine if we are dealing with variable bit rate, which means the frames per
        // packet will vary.
        bool isFormatVBR = (dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0);
        
        if (isFormatVBR) {
            player.packetDescs = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * player.numPacketsToRead);
        } else {
            player.packetDescs = NULL;
        }
        
        // Apply the magic cookie from the audio file (if one exists) to the playback queue.
        // Remember: magic cookie gives some additional info about audio data for certain encoded formats.
        MyCopyEncoderCookieToQueue(player.playbackFile, queue);
        
        AudioQueueBufferRef buffers[kNumberPlaybackBuffers];
        player.isDone = false;
        player.packetPosition = 0;
        for (int i = 0; i < kNumberPlaybackBuffers; i++) {
            err = AudioQueueAllocateBuffer(queue,
                                           bufferBytesSize,
                                           &buffers[i]);
            CheckError(err, "AudioQueueAllocateBuffer failed");
            
            MyAQOutputCallback(&player,
                               queue,
                               buffers[i]);
            
            // If we read through the entire file while priming the buffers, we need to bail.
            // This can happen for small files (3 buffers x 0.5 s = 1.5 s).
            if (player.isDone) {
                break;
            }
        }
        
        // Start queue - 5.11-5.12
        err = AudioQueueStart(queue,
                              NULL);
        CheckError(err, "AudioQueueStart failed");
        
        printf("Playing...");
        do {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode,
                               0.25,
                               false);
        } while (!player.isDone);
        
        // In case there are buffers that still have some audio data, we continue
        // running to completely drain out the buffers (2 sec > 1.5 sec).
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false);
        
        // Clean up queue
        player.isDone = true;
        err = AudioQueueStop(queue,
                             true);
        CheckError(err, "AudioQueueStop failed");
        
        AudioQueueDispose(queue,
                          true);
        
        AudioFileClose(player.playbackFile);
        
    }
    return 0;
}
