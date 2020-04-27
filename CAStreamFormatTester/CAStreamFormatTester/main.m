//
//  main.m
//  CAStreamFormatTester
//
//  Created by Manthan Shah on 2020-04-24.
//  Copyright © 2020 Manthan Shah. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        AudioFileTypeAndFormatID typeAndFormat;
        typeAndFormat.mFileType = kAudioFileCAFType;
        typeAndFormat.mFormatID = kAudioFormatLinearPCM;
        
        UInt32 infoSize = 0;
        OSStatus err = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                                  sizeof(typeAndFormat),
                                                  &typeAndFormat,
                                                  &infoSize);
        assert(err == noErr);
        
        AudioStreamBasicDescription *asbds = malloc(infoSize);
        
        err = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                     sizeof(typeAndFormat),
                                     &typeAndFormat,
                                     &infoSize,
                                     asbds);
        assert(err == noErr);
        
        int asbdCount = infoSize / sizeof(AudioStreamBasicDescription);
        
        for (int i = 0; i < asbdCount; i++) {
            UInt32 format4cc = CFSwapInt32HostToBig(asbds[i].mFormatID);
            
            NSLog(@"%d: mFormatID: %4.4s, mFormatFlags: %d, mBitsPerChannel: %d", i, (char *)(&format4cc), asbds[i].mFormatFlags, asbds[i].mBitsPerChannel);
        }
        
        free(asbds);
        
    }
    return 0;
}
