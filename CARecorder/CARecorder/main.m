//
//  main.m
//  CARecorder
//
//  Created by Manthan Shah on 2020-04-25.
//  Copyright © 2020 Manthan Shah. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

# define kNumberRecordBuffers 3

# pragma mark user data struct
typedef struct MyRecorder {
    AudioFileID recordFile;
    SInt64 recordPacket;
    Boolean isRunning;
} MyRecorder;

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

static OSStatus MyGetDefaultInputDeviceSampleRate(Float64 *outSampleRate)
{
    OSStatus error = noErr;
    AudioDeviceID deviceID = 0;
    
    AudioObjectPropertyAddress propertyAddress;
    UInt32 propertySize;
    
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(AudioDeviceID);
    
    error = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                       &propertyAddress,
                                       0,
                                       NULL,
                                       &propertySize,
                                       &deviceID);
    
    if (error) return error;
    
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    
    propertySize = sizeof(Float64);
    
    error = AudioObjectGetPropertyData(deviceID,
                                       &propertyAddress,
                                       0,
                                       NULL,
                                       &propertySize,
                                       outSampleRate);
    
    return error;
}

static int MyComputeRecordBufferSize(const AudioStreamBasicDescription *format, AudioQueueRef queue, float seconds)
{
    int packets, frames, bytes;
    
    // Total number of frames in buffer
    frames = (int)ceil(seconds * format->mSampleRate);
    
    if (format->mBytesPerFrame > 0)
    {
        // If constant bit rate audio data
        bytes = frames * format->mBytesPerFrame;
    }
    else
    {
        // Variable bit rate
        
        UInt32 maxPacketSize;
        
        // Determine the size of each packet
        if (format->mBytesPerPacket > 0)
        {
            // Constant packet size
            maxPacketSize = format->mBytesPerPacket;
        }
        else
        {
            // Get the largest single packet size possible
            UInt32 propertySize = sizeof(maxPacketSize);
            
            OSStatus err = AudioQueueGetProperty(queue,
                                                 kAudioConverterPropertyMaximumOutputPacketSize,
                                                 &maxPacketSize,
                                                 &propertySize);
            CheckError(err, "Couldn't get queue's maximum output packet size");
        }
        
        // Determine total number of packets
        if (format->mFramesPerPacket > 0)
        {
            packets = frames / format->mFramesPerPacket;
        }
        else
        {
            // Worst case: 1 frame per packet
            packets = frames;
        }
        
        // Sanity check
        if (packets == 0)
        {
            packets = 1;
        }
        
        bytes = packets * maxPacketSize;
    }
    
    return bytes;
}

static void MyCopyEncoderCookieToFile(AudioQueueRef queue, AudioFileID theFile)
{
    OSStatus error;
    UInt32 propertySize;
    
    // Get the size of the magic cookie property
    error = AudioQueueGetPropertySize(queue,
                                      kAudioConverterCompressionMagicCookie,
                                      &propertySize);
    CheckError(error, "AudioQueueGetPropertySize failed");
    
    if (error == noErr && propertySize > 0)
    {
        Byte *magicCookie = (Byte *)malloc(propertySize);
        error = AudioQueueGetProperty(queue,
                                      kAudioQueueProperty_MagicCookie,
                                      magicCookie,
                                      &propertySize);
        CheckError(error, "Couldn't get audio queue's magic cookie");
        
        error = AudioFileSetProperty(theFile,
                                     kAudioFilePropertyMagicCookieData,
                                     propertySize,
                                     magicCookie);
        CheckError(error, "Couldn't set audio file's magic cookie");
        
        free(magicCookie);
    }
}

# pragma mark record callback function
static void MyAQInputCallback(void *inUserData,
                              AudioQueueRef inQueue,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc)
{
    MyRecorder *recorder = (MyRecorder *)inUserData;
    
    // Write packets to a file
    if (inNumPackets > 0)
    {
        OSStatus error = AudioFileWritePackets(recorder->recordFile,
                                               false,
                                               inBuffer->mAudioDataByteSize,
                                               inPacketDesc,
                                               recorder->recordPacket,
                                               &inNumPackets,
                                               inBuffer->mAudioData);
        CheckError(error, "AudioFileWritePackets failed");
        
        // Increment the packet index
        recorder->recordPacket += inNumPackets;
    }
    
    if (recorder->isRunning)
    {
        OSStatus error = AudioQueueEnqueueBuffer(inQueue,
                                                 inBuffer,
                                                 0,
                                                 NULL);
        CheckError(error, "AudioQueueEnqueueBuffer failed");
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        // Setup format 4.4 - 4.7
        MyRecorder recorder = { 0 };
        AudioStreamBasicDescription recordFormat = { 0 };
        memset(&recordFormat, 0, sizeof(recordFormat));
        
        // Configure the output data format
        recordFormat.mFormatID = kAudioFormatMPEG4AAC;
        recordFormat.mChannelsPerFrame = 2;
        
        // Grab the sample rate of the input recording hardware (e.g. microphone). This
        // is to adapt the output data format to match that of the hardware.
        MyGetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate);
        
        // We use the AudioFormat API to simplify the configuration of the ASBD.
        // Input: at least the mFormatID of the ASBD populated.
        // Output: the ASBD will be populated as much as possible based on the given
        // information we know about format.
        UInt32 propSize = sizeof(recordFormat);
        OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                              0,
                                              NULL,
                                              &propSize,
                                              &recordFormat);
        CheckError(err, "AudioFormatGetProperty failed");
        
        // Setup queue 4.8 - 4.9
        AudioQueueRef queue = { 0 };
        err = AudioQueueNewInput(&recordFormat,
                                 MyAQInputCallback,
                                 &recorder,
                                 NULL,
                                 NULL,
                                 0,
                                 &queue);
        CheckError(err, "AudioQueueNewInput failed");
        
        // We ask the queue's Audio Converter object for its ASBD that it has
        // configured. The file may require a more specific ASBD than was originally
        // required to initialize it.
        UInt32 size = sizeof(recordFormat);
        err = AudioQueueGetProperty(queue,
                                    kAudioConverterCurrentOutputStreamDescription,
                                    &recordFormat,
                                    &size);
        CheckError(err, "AudioQueueGetProperty failed");
        
        // Setup file 4.10 - 4.11
        NSString *filePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"output.caf"];
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        
        err = AudioFileCreateWithURL((__bridge CFURLRef)fileURL,
                                     kAudioFileCAFType,
                                     &recordFormat,
                                     kAudioFileFlags_EraseFile,
                                     &recorder.recordFile);
        CheckError(err, "AudioFileCreateWithURL failed");
        
        // Many encoded formats require a 'magic cookie' due to variable bit rates. We set the
        // cookie first on the audio file to give the file as much info as we know about the
        // incoming audio data.
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        // Other setup as needed 4.12 - 4.13
        int bufferByteSize = MyComputeRecordBufferSize(&recordFormat, queue, 0.5);
        
        int bufferIndex;
        for (bufferIndex = 0; bufferIndex < kNumberRecordBuffers; bufferIndex++)
        {
            AudioQueueBufferRef buffer;
            err = AudioQueueAllocateBuffer(queue,
                                           bufferByteSize,
                                           &buffer);
            CheckError(err, "AudioQueueAllocateBuffer failed");
            
            err = AudioQueueEnqueueBuffer(queue,
                                          buffer,
                                          0,
                                          NULL);
            CheckError(err, "AudioQueueEnqueueBuffer failed");
        }
        
        // Start queue 4.14 - 4.15
        recorder.isRunning = true;
        err = AudioQueueStart(queue, NULL);
        CheckError(err, "AudioQueueStart failed");
        
        printf("Recording, press <return> to stop:\n");
        getchar();
        
        // Stop queue 4.16 - 4.18
        printf("* recording done *\n");
        
        recorder.isRunning = false;
        err = AudioQueueStop(queue, true);
        CheckError(err, "AudioQueueStop failed");
        
        // It is possible that a codec may update its magic cookie, so we
        // apply it again to the audio file
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        AudioQueueDispose(queue, true);
        AudioFileClose(recorder.recordFile);
    }
    return 0;
}
