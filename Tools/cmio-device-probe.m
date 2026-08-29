#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>

static NSString *StringProperty(CMIOObjectID objectID, CMIOObjectPropertySelector selector) {
    CMIOObjectPropertyAddress address = {
        selector,
        kCMIOObjectPropertyScopeGlobal,
        kCMIOObjectPropertyElementMain
    };
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    OSStatus status = CMIOObjectGetPropertyData(objectID, &address, 0, NULL, size, &size, &value);
    if (status != noErr || value == NULL) {
        return @"";
    }
    return CFBridgingRelease(value);
}

static UInt32 UInt32Property(CMIOObjectID objectID, CMIOObjectPropertySelector selector) {
    CMIOObjectPropertyAddress address = {
        selector,
        kCMIOObjectPropertyScopeGlobal,
        kCMIOObjectPropertyElementMain
    };
    UInt32 value = 0;
    UInt32 size = sizeof(value);
    CMIOObjectGetPropertyData(objectID, &address, 0, NULL, size, &size, &value);
    return value;
}

static NSString *FourCC(UInt32 value) {
    char text[5] = {
        (char)((value >> 24) & 0xff),
        (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff),
        (char)(value & 0xff),
        0
    };
    return [NSString stringWithUTF8String:text] ?: @"";
}

int main(void) {
    @autoreleasepool {
        CMIOObjectPropertyAddress devicesAddress = {
            kCMIOHardwarePropertyDevices,
            kCMIOObjectPropertyScopeGlobal,
            kCMIOObjectPropertyElementMain
        };
        UInt32 dataSize = 0;
        OSStatus status = CMIOObjectGetPropertyDataSize(
            kCMIOObjectSystemObject,
            &devicesAddress,
            0,
            NULL,
            &dataSize
        );
        if (status != noErr || dataSize == 0) {
            fprintf(stderr, "No CMIO devices (status=%d)\n", (int)status);
            return 1;
        }

        NSUInteger count = dataSize / sizeof(CMIOObjectID);
        NSMutableData *deviceData = [NSMutableData dataWithLength:dataSize];
        status = CMIOObjectGetPropertyData(
            kCMIOObjectSystemObject,
            &devicesAddress,
            0,
            NULL,
            dataSize,
            &dataSize,
            deviceData.mutableBytes
        );
        if (status != noErr) {
            fprintf(stderr, "Unable to read CMIO devices (status=%d)\n", (int)status);
            return 1;
        }

        CMIOObjectID *deviceIDs = deviceData.mutableBytes;
        for (NSUInteger index = 0; index < count; index += 1) {
            CMIOObjectID deviceID = deviceIDs[index];
            NSString *name = StringProperty(deviceID, kCMIOObjectPropertyName);
            NSString *manufacturer = StringProperty(deviceID, kCMIOObjectPropertyManufacturer);
            NSString *model = StringProperty(deviceID, kCMIODevicePropertyModelUID);
            UInt32 transport = UInt32Property(deviceID, kCMIODevicePropertyTransportType);
            printf("name=%s\n", name.UTF8String);
            printf("manufacturer=%s\n", manufacturer.UTF8String);
            printf("model=%s\n", model.UTF8String);
            printf("transport=%s (%u)\n", FourCC(transport).UTF8String, transport);
            printf("---\n");
        }
    }
    return 0;
}
