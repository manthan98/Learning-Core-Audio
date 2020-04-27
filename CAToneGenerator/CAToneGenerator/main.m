//
//  main.m
//  CAToneGenerator
//
//  Created by Manthan Shah on 2020-04-24.
//  Copyright © 2020 Manthan Shah. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define SAMPLE_RATE 44100
#define DURATION 5.0

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        double hz = atof(argv[1]);
        assert(hz > 0);
        NSLog(@"Generating %f Hz tone", hz);
        
        NSString *fileName = [NSString stringWithFormat:@"%0.3f-square.aiff", hz];
        NSString *filePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:fileName];
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        
        // Prepare the format
        AudioStreamBasicDescription asbd;
        memset(&asbd, 0, sizeof(asbd));
        
        asbd.mSampleRate = SAMPLE_RATE;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        asbd.mBitsPerChannel = 16;
        asbd.mChannelsPerFrame = 1;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerFrame = 2;
        asbd.mBytesPerPacket = 2;
        
        // Setup the file
        AudioFileID audioFile;
        OSStatus err = AudioFileCreateWithURL((__bridge CFURLRef)fileURL,
                                              kAudioFileAIFFType,
                                              &asbd,
                                              kAudioFileFlags_EraseFile,
                                              &audioFile);
        assert(err == noErr);
        
        // Start writing samples
        long maxSampleCount = SAMPLE_RATE * DURATION;
        long sampleCount = 0;
        
        UInt32 byteSize = 2;
        long wavelengthInSamples = SAMPLE_RATE / hz;
        
        while (sampleCount < maxSampleCount)
        {
            for (int i = 0; i < wavelengthInSamples; i++)
            {
                SInt16 sample;
                if (i < wavelengthInSamples / 2)
                {
                    sample = CFSwapInt16BigToHost(SHRT_MAX);
                }
                else
                {
                    sample = CFSwapInt16BigToHost(SHRT_MIN);
                }
                
                err = AudioFileWriteBytes(audioFile,
                                          false,
                                          sampleCount * 2, // Because 1 byte = 8 bits, and we have 16 bit samples
                                          &byteSize,
                                          &sample);
                assert(err == noErr);
                
                sampleCount++;
            }
        }
        
        err = AudioFileClose(audioFile);
        assert(err == noErr);
        NSLog(@"wrote %ld samples", sampleCount);
        
    }
    return 0;
}
